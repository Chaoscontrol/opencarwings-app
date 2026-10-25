#!/usr/bin/env python3
"""Exercise the actual startup Python patches on a disposable upstream copy.

Usage: python3 .github/scripts/test-startup-patches.py /path/to/upstream
No Django installation, running services, database or vehicle access is needed.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from types import SimpleNamespace
import warnings


class Logger:
    def __init__(self):
        self.warning_count = 0

    def __getattr__(self, name):
        def log(*args, **kwargs):
            if name == "warning":
                self.warning_count += 1
        return log


def heredocs(script):
    lines = script.splitlines(keepends=True)
    index = 0
    while index < len(lines):
        header = lines[index]
        match = re.match(r"^\s*(python3\s+-|cat)\s+.*?<<\s*'EOF'.*$", header)
        index += 1
        if not match:
            continue
        start = index
        while index < len(lines) and lines[index].strip() != "EOF":
            index += 1
        assert index < len(lines), "Unterminated startup heredoc"
        yield ("python" if match[1].startswith("python") else "settings"), header, "".join(lines[start:index])
        index += 1


def literals(code):
    result = {}
    for node in ast.walk(ast.parse(code)):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    try:
                        result[target.id] = ast.literal_eval(node.value)
                    except (ValueError, TypeError):
                        pass
    return result


def run_python(code, root, *, should_fail=False):
    code = code.replace("/opt/opencarwings", str(root))
    result = subprocess.run([sys.executable, "-"], input=code, cwd=root, text=True,
                            capture_output=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    if should_fail:
        assert result.returncode and "compatibility patch does not match upstream" in result.stderr, result.stderr
    elif result.returncode:
        raise AssertionError(result.stderr)


def apply_patches(blocks, root):
    settings = root / "carwings/settings.py"
    for kind, header, code in blocks:
        if kind == "settings":
            assert "$SETTINGS_FILE" in header, "Unexpected non-settings cat heredoc"
            marker = next(line for line in code.splitlines() if line.startswith("# --- OpenCarwings"))
            if marker not in settings.read_text():
                with settings.open("a") as stream:
                    stream.write(code.replace("/opt/opencarwings", str(root)))
        else:
            if "django.setup()" in code:
                continue  # Explicitly exclude the final persistent-database cleanup.
            values = literals(code)
            marker = values.get("new_lines", [""])[0].strip()
            filename = values.get("file_path")
            # These two shell guards surround non-idempotent instrumentation blocks.
            if marker and filename and marker in Path(filename.replace("/opt/opencarwings", str(root))).read_text():
                continue
            run_python(code, root)


def python_hashes(root):
    return {path.relative_to(root): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob("*.py")}


def test_crm(root):
    tree = ast.parse((root / "tculink/carwings_proto/probe_crm.py").read_text())
    values = literals(ast.unparse(tree))
    nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef)
             and node.name in {"parse_crmfile", "parse_crm_datablocks"}]
    assert len(nodes) == 2, "Expected both upstream CRM parser functions"
    logger = Logger()
    labels = literals((root / "tculink/carwings_proto/crm_labels.py").read_text())["CRM_LABELS"]
    labelmap = {int(item["label"], 16): {key: int(item[field], 16) for key, field in
                (("size", "dataSize"), ("type", "dataType"), ("structure", "dataStructur"))} for item in labels}
    namespace = {"logger": logger, "first_blocks": values["first_blocks"],
                 "sections": values["sections"], "crm_labelmap": labelmap}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), "<patched-crm>", "exec"), namespace)
    parse = namespace["parse_crm_datablocks"]
    assert parse([])["latest"] == {}
    block = {"type": 0xE1, "struct": "latest", "data": b"\x00\x07"}
    assert parse([block])["latest"]["phone_contacts_saved"] == 7
    assert parse([{"type": 0xB5, "struct": "trips", "data": b"\x01"}])["trips"] == []
    assert logger.warning_count == 1, "Malformed block should preserve upstream warning"
    merged = parse([block, {"type": 0xE2, "struct": "latest",
                             "ficosa": {"phone_contacts_saved": 999, "cabin_temp": 20.5}}])["latest"]
    assert merged == {"phone_contacts_saved": 7, "cabin_temp": 20.5}
    assert namespace["parse_crmfile"](b"\x00" * 38 + b"\xe1\x00\x07")["latest"]["phone_contacts_saved"] == 7


def test_cp(code, root, pristine):
    path = root / "tculink/carwings_proto/applications/cp.py"
    patched = path.read_text()
    values = literals(code)
    for provider, key, output in (("ocm", "OPENCHARGEMAP_API_KEY", "chargers_resp"),
                                  ("iternio", "ITERNIO_API_KEY", "chargers")):
        assert f"if not settings.{key}" in patched, f"Missing {provider} protection"
        snippet = textwrap.dedent(values[f"new_{provider}_block"])
        def forbidden_request(*args, **kwargs):
            raise AssertionError("Missing API key must prevent outbound requests")
        namespace = {"settings": SimpleNamespace(**{key: ""}), "logger": Logger(),
                     "requests": SimpleNamespace(get=forbidden_request),
                     "location_center": (0, 0), "boundingbox_tl": 0, "boundingbox_br": 0}
        exec(compile(snippet, "<cp-missing-key>", "exec"), namespace)
        assert namespace[output] == []
        for status, invalid_json in ((503, False), (200, True)):
            def response_json():
                if invalid_json:
                    raise ValueError("Malformed provider response")
                raise AssertionError("Non-success HTTP responses must not be decoded")
            namespace["settings"] = SimpleNamespace(**{key: "test-key"})
            response = SimpleNamespace(status_code=status, json=response_json)
            namespace["requests"] = SimpleNamespace(get=lambda *args, **kwargs: response)
            exec(compile(snippet, "<cp-provider-error>", "exec"), namespace)
            assert namespace[output] == []
        old = values[f"old_{provider}_block"]
        assert old in pristine, f"Unknown pristine {provider} anchor"
        corrupt = pristine.replace(old, old.replace("requests.get", "requests.get_changed", 1), 1)
        path.write_text(corrupt)
        run_python(code, root, should_fail=True)
        assert path.read_text() == corrupt, "A failed patch must not write partial changes"
    path.write_text(patched)


def test_storage(blocks):
    code = next(code for kind, _, code in blocks if kind == "settings" and "STORAGES" in code)
    tree = ast.parse(code)
    tree.body = [node for node in tree.body if not isinstance(node, ast.ImportFrom)]
    default = {"BACKEND": "django.core.files.storage.FileSystemStorage"}
    namespace = {"MIDDLEWARE": ["django.middleware.security.SecurityMiddleware"],
                 "global_settings": SimpleNamespace(STORAGES={"default": default})}
    exec(compile(tree, "<static-storage-patch>", "exec"), namespace)
    assert namespace["STORAGES"]["default"] == default
    assert namespace["STORAGES"]["staticfiles"]["BACKEND"] == "whitenoise.storage.CompressedStaticFilesStorage"
    assert namespace["MIDDLEWARE"][1] == "whitenoise.middleware.WhiteNoiseMiddleware"



def test_redis(blocks, live=False):
    code = next(code for kind, _, code in blocks if kind == "settings" and "# --- OpenCarwings Redis Patch ---" in code)
    namespace = {"ALLOWED_HOSTS": []}
    exec(compile(code, "<redis-settings-patch>", "exec"), namespace)
    configuration = namespace["CHANNEL_LAYERS"]["default"]
    assert configuration["BACKEND"] == "channels_redis.core.RedisChannelLayer"
    host = configuration["CONFIG"]["hosts"][0]
    assert isinstance(host, dict), "Redis host must override redis-py's blocking-read timeout"
    assert "socket_timeout" in host and host["socket_timeout"] is None
    assert host["socket_connect_timeout"] == 5
    if not live:
        return
    # Optional inside the disposable CI image; no Django, database or live API.
    import asyncio
    from contextlib import suppress
    import socket
    import time
    from uuid import uuid4
    from channels_redis.core import RedisChannelLayer

    async def receive_after_idle():
        layer = RedisChannelLayer(**configuration["CONFIG"])
        channel = await layer.new_channel("idle.regression")
        group = "idle.regression." + uuid4().hex
        event = {"type": "regression.idle", "probe": uuid4().hex}
        task = None
        try:
            await layer.group_add(group, channel)
            task = asyncio.create_task(layer.receive(channel))
            done, _ = await asyncio.wait({task}, timeout=12)
            assert not done, "Redis channel receive ended before 12 seconds of idle"
            await layer.group_send(group, event)
            assert await asyncio.wait_for(task, timeout=5) == event
        finally:
            if task is not None:
                task.cancel()
                with suppress(asyncio.CancelledError, Exception):
                    await task
            with suppress(Exception):
                await layer.group_discard(group, channel)
            await layer.close_pools()

    with socket.socket() as probe:
        assert probe.connect_ex(("127.0.0.1", 6379)) != 0, "Refusing to use an existing Redis server"
    with tempfile.TemporaryDirectory(prefix="ocw-redis-idle-") as directory:
        server = subprocess.Popen(["redis-server", "--bind", "127.0.0.1", "--port", "6379", "--save", "",
                                   "--appendonly", "no", "--daemonize", "no", "--dir", directory],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 5
            while True:
                assert server.poll() is None, "Disposable Redis server exited during startup"
                with socket.socket() as probe:
                    if probe.connect_ex(("127.0.0.1", 6379)) == 0:
                        break
                assert time.monotonic() < deadline, "Disposable Redis did not become ready"
                time.sleep(0.1)
            asyncio.run(receive_after_idle())
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)
    print("redis-idle-ok: actual configured channel survived 12s idle and delivered a group event")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("upstream", type=Path)
    parser.add_argument("--wrapper-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--redis-idle", action="store_true", help="Run real Channels/Redis idle regression in the disposable image")
    args = parser.parse_args()
    scripts = args.wrapper_root / "opencarwings/rootfs/etc"
    setup = (scripts / "cont-init.d/03-django-setup.sh").read_text()
    runtime = (scripts / "cont-init.d/05-patch-settings.sh").read_text()
    blocks = [*heredocs(setup), *heredocs(runtime)]
    cp_code = next(code for kind, _, code in blocks if kind == "python" and "old_ocm_block" in code)
    assert len([code for kind, _, code in blocks if kind == "python" and "django.setup()" in code]) == 1
    assert "STATICFILES_STORAGE =" not in runtime
    assert runtime.index("STORAGES['staticfiles']") < runtime.index("manage.py collectstatic")
    assert "record.name == \"tcuserver\"" in runtime
    periodic = (scripts / "services.d/periodic/run").read_text()
    guard = periodic.index("periodic_tasks_enabled")
    sleep = periodic.index("exec sleep infinity")
    tasks = list(re.finditer(r"python3\s+manage\.py\s+(\w+)", periodic))
    assert tasks and all(guard < sleep < task.start() for task in tasks)
    assert "flushexpiredtransfers" in {task[1] for task in tasks}
    test_storage(blocks)
    test_redis(blocks, live=args.redis_idle)
    with tempfile.TemporaryDirectory(prefix="ocw-startup-patches-") as temporary:
        root = Path(temporary) / "upstream"
        shutil.copytree(args.upstream, root, ignore=shutil.ignore_patterns(".git", "__pycache__", "node_modules"))
        pristine_cp = (root / "tculink/carwings_proto/applications/cp.py").read_text()
        shutil.copy2(root / "carwings/settings.docker.py", root / "carwings/settings.py")
        apply_patches(blocks, root)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", SyntaxWarning)
            for path in root.rglob("*.py"):
                compile(path.read_bytes(), str(path), "exec")
        first = python_hashes(root)
        apply_patches(blocks, root)
        assert python_hashes(root) == first, "Startup patches are not idempotent"
        test_crm(root)
        test_cp(cp_code, root, pristine_cp)
    print("startup-patches-ok: syntax, idempotence, CRM, CP guards/anchor failures, storage, Redis timeout and scheduler isolation")


if __name__ == "__main__":
    main()
