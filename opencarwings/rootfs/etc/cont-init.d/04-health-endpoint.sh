#!/command/with-contenv bashio
# shellcheck shell=bash
source /etc/cont-init.d/00-log-fix.sh

# Create a simple standalone health check script
cat > /opt/opencarwings/healthcheck.py << 'EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import sys

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health' or self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'ok', 'service': 'OpenCarwings'}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logs

try:
    import datetime
    def log(level, msg, color="32"):
        now = datetime.datetime.now().strftime("%H:%M:%S")
        print(f"[{now}] \033[{color}m{level}: {msg}\033[0m", flush=True)

    server = HTTPServer(('0.0.0.0', 8899), HealthHandler)
    log('INFO', 'Health check server started on port 8899')
    server.serve_forever()
except Exception as e:
    log('ERROR', f'Health check server failed: {e}', color="31")
    sys.exit(1)
EOF

chmod +x /opt/opencarwings/healthcheck.py

bashio::log.info "Health check server script created"