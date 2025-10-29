import http.server
import threading
from http import HTTPStatus

class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(HTTPStatus.OK)
            self.end_headers()
            self.wfile.write(b'OK')
        else:
            self.send_response(HTTPStatus.NOT_FOUND)
            self.end_headers()

def start_health_server():
    server = http.server.HTTPServer(('0.0.0.0', 8000), HealthHandler)
    print("🩺 Health check server running on port 8000")
    server.serve_forever()

# Start health server in background thread
health_thread = threading.Thread(target=start_health_server, daemon=True)
health_thread.start()
