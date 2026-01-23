#!/usr/bin/env python3

import http.server
import re

class DebugHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        body = self.rfile.read(content_length)

        print("\n=== RAW BODY (first 500 bytes hex) ===")
        print(body[:500].hex())

        print("\n=== RAW BODY (first 500 bytes) ===")
        print(body[:500])

        # Extract boundary
        content_type = self.headers['Content-Type']
        boundary_match = re.search(r'boundary=([^;]+)', content_type)
        if boundary_match:
            boundary = boundary_match.group(1).strip('"')
            print(f"\n=== BOUNDARY: '{boundary}' ===")

            # Show how body is split
            parts = body.split(f'--{boundary}'.encode())
            print(f"\nNumber of parts: {len(parts)}")

            for i, part in enumerate(parts[:3]):  # Show first 3 parts
                print(f"\n--- Part {i} (first 200 bytes) ---")
                print(repr(part[:200]))

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Debug complete")

if __name__ == '__main__':
    server = http.server.HTTPServer(('', 8080), DebugHandler)
    print("Debug server at http://localhost:8080")
    server.serve_forever()