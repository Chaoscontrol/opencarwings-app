#!/usr/bin/env bashio
# shellcheck shell=bash

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
    server = HTTPServer(('0.0.0.0', 8899), HealthHandler)
    print('[INFO] Health check server started on port 8899', flush=True)
    sys.stdout.flush()
    server.serve_forever()
except Exception as e:
    print(f'[ERROR] Health check server failed: {e}', flush=True)
    sys.exit(1)
EOF

chmod +x /opt/opencarwings/healthcheck.py

bashio::log.info "Health check server script created"