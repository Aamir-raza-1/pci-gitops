#!/usr/bin/env python3

import http.server
import urllib.parse
import json
import os
from datetime import datetime
import io
import re

class FormHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        """Serve the HTML form and status page"""
        if self.path == '/' or self.path == '/index.html':
            # Serve the form
            if os.path.exists('online-assessment-form-v2.html'):
                with open('online-assessment-form-v2.html', 'rb') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_error(404, "Form not found")
        elif self.path == '/test-upload.html':
            # Serve test page
            if os.path.exists('test-upload.html'):
                with open('test-upload.html', 'rb') as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.send_header('Content-Length', str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_error(404, "Test page not found")
        elif self.path == '/status':
            # Serve status page
            self.serve_status_page()
        elif self.path.startswith('/view/'):
            # View individual form submission
            self.serve_form_view()
        else:
            self.send_error(404)

    def serve_form_view(self):
        """Serve a page to view individual form submission data"""
        # Extract filename from path
        filename = self.path.replace('/view/', '')
        filepath = os.path.join('form_submissions', filename)

        if not os.path.exists(filepath):
            self.send_error(404, "Form submission not found")
            return

        try:
            with open(filepath, 'r') as f:
                form_data = json.load(f)
        except Exception as e:
            self.send_error(500, f"Error reading form data: {str(e)}")
            return

        # Generate HTML for viewing form data
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>View Form Submission - {form_data.get('run_id', 'Unknown')}</title>
            <style>
                body {{ font-family: 'Courier New', monospace; padding: 20px; background: #f5f5f5; }}
                .container {{ max-width: 1000px; margin: auto; }}
                h1 {{ color: #333; border-bottom: 2px solid #4a90e2; padding-bottom: 10px; }}
                h2 {{ color: #555; margin-top: 20px; }}
                .data-box {{ background: white; padding: 20px; border-radius: 8px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
                .field {{ margin: 10px 0; padding: 10px; background: #f8f9fa; border-left: 3px solid #4a90e2; }}
                .field-name {{ font-weight: bold; color: #333; margin-bottom: 5px; }}
                .field-value {{ color: #555; padding-left: 20px; }}
                .btn {{ display: inline-block; padding: 10px 20px; background: #4a90e2; color: white; text-decoration: none; border-radius: 4px; margin: 5px; }}
                .btn:hover {{ background: #357abd; }}
                .meta-info {{ color: #666; font-size: 12px; margin: 10px 0; }}
                .file-list {{ padding: 10px; background: #e8f4f8; border-radius: 4px; margin: 10px 0; }}
                .file-item {{ padding: 5px 0; }}
                pre {{ background: #f4f4f4; padding: 15px; border-radius: 4px; overflow-x: auto; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Form Submission Details</h1>
                <div class="meta-info">
                    Run ID: {form_data.get('run_id', 'Unknown')} |
                    Submitted: {form_data.get('submitted_at', 'Unknown')}
                </div>

                <div class="data-box">
                    <h2>Basic Information</h2>
                    <div class="field">
                        <div class="field-name">Company Name</div>
                        <div class="field-value">{form_data.get('company_name', 'Not provided')}</div>
                    </div>
                    <div class="field">
                        <div class="field-name">Cloud Provider</div>
                        <div class="field-value">{form_data.get('cloud_provider', 'Not provided')}</div>
                    </div>
                    <div class="field">
                        <div class="field-name">Project/Account ID</div>
                        <div class="field-value">{form_data.get('gcloud_project', '') or form_data.get('aws_account', '') or 'Not provided'}</div>
                    </div>
                    <div class="field">
                        <div class="field-name">Kubernetes Clusters</div>
                        <div class="field-value">{form_data.get('kubernetes_clusters', 'Not provided')}</div>
                    </div>
                    <div class="field">
                        <div class="field-name">Database Types</div>
                        <div class="field-value">{form_data.get('database_types', 'Not provided')}</div>
                    </div>
                </div>

                <div class="data-box">
                    <h2>Uploaded Files</h2>
                    {self._format_uploaded_files(form_data.get('uploaded_files_details', []))}
                </div>

                <div class="data-box">
                    <h2>Additional Details</h2>
                    <div class="field">
                        <div class="field-name">Application Repos</div>
                        <div class="field-value">{form_data.get('app_repos', 'Not provided')}</div>
                    </div>
                    <div class="field">
                        <div class="field-name">Infrastructure Repos</div>
                        <div class="field-value">{form_data.get('infra_repos', 'Not provided')}</div>
                    </div>
                    <div class="field">
                        <div class="field-name">Website URLs</div>
                        <div class="field-value">{form_data.get('websites', 'Not provided')}</div>
                    </div>
                </div>

                <div class="data-box">
                    <h2>Raw JSON Data</h2>
                    <pre>{json.dumps(form_data, indent=2)}</pre>
                </div>

                <div style="margin: 20px 0;">
                    <a href="/status" class="btn">Back to Status</a>
                    <a href="/" class="btn">New Submission</a>
                </div>
            </div>
        </body>
        </html>
        """

        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

    def _format_uploaded_files(self, files):
        """Format uploaded files for display"""
        if not files:
            return "<div class='file-list'>No files uploaded</div>"

        html = "<div class='file-list'>"
        for file_info in files:
            html += f"""
            <div class='file-item'>
                <strong>{file_info.get('original_name', 'Unknown')}</strong> -
                {file_info.get('size', 0)} bytes -
                Saved as: {file_info.get('saved_as', 'Unknown')}
            </div>
            """
        html += "</div>"
        return html

    def serve_status_page(self):
        """Serve a status page showing recent submissions and system info"""
        # Get recent submissions
        submissions = []
        if os.path.exists('form_submissions'):
            for filename in sorted(os.listdir('form_submissions'), reverse=True)[:10]:
                if filename.endswith('.json'):
                    filepath = os.path.join('form_submissions', filename)
                    try:
                        with open(filepath, 'r') as f:
                            data = json.load(f)
                            submissions.append({
                                'filename': filename,
                                'run_id': data.get('run_id', 'unknown'),
                                'submitted_at': data.get('submitted_at', 'unknown'),
                                'company': data.get('company_name', 'unknown'),
                                'provider': data.get('cloud_provider', 'unknown'),
                                'project': data.get('gcloud_project', '') or data.get('aws_account', ''),
                                'files': len(data.get('uploaded_files', [])),
                                'size': os.path.getsize(filepath)
                            })
                    except:
                        pass

        # Get uploaded files
        uploaded_docs = []
        if os.path.exists('docs'):
            for filename in sorted(os.listdir('docs'), reverse=True)[:10]:
                filepath = os.path.join('docs', filename)
                uploaded_docs.append({
                    'filename': filename,
                    'size': os.path.getsize(filepath),
                    'modified': datetime.fromtimestamp(os.path.getmtime(filepath)).isoformat()
                })

        # Count artifacts
        artifact_counts = {
            'form_submissions': len(os.listdir('form_submissions')) if os.path.exists('form_submissions') else 0,
            'docs': len(os.listdir('docs')) if os.path.exists('docs') else 0,
            'processed': len(os.listdir('artifacts/processed')) if os.path.exists('artifacts/processed') else 0,
            'access_validations': len([d for d in os.listdir('artifacts') if d.startswith('access_')]) if os.path.exists('artifacts') else 0
        }

        # Generate HTML
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <title>Maestro Assessment Server Status</title>
            <style>
                body {{ font-family: 'Courier New', monospace; padding: 20px; background: #f5f5f5; }}
                .container {{ max-width: 1200px; margin: auto; }}
                h1 {{ color: #333; border-bottom: 2px solid #4a90e2; padding-bottom: 10px; }}
                h2 {{ color: #555; margin-top: 30px; }}
                .status-box {{ background: white; padding: 15px; border-radius: 8px; margin: 10px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
                .metric {{ display: inline-block; margin: 10px 20px 10px 0; }}
                .metric-label {{ color: #666; font-size: 12px; }}
                .metric-value {{ font-size: 24px; font-weight: bold; color: #4a90e2; }}
                table {{ width: 100%; border-collapse: collapse; background: white; }}
                th {{ background: #4a90e2; color: white; padding: 10px; text-align: left; }}
                td {{ padding: 8px; border-bottom: 1px solid #eee; }}
                tr:hover {{ background: #f8f8f8; }}
                .success {{ color: #28a745; }}
                .warning {{ color: #ffc107; }}
                .info {{ color: #17a2b8; }}
                .btn {{ display: inline-block; padding: 10px 20px; background: #4a90e2; color: white; text-decoration: none; border-radius: 4px; margin: 5px; }}
                .btn:hover {{ background: #357abd; }}
                .timestamp {{ color: #666; font-size: 11px; }}
                .empty {{ color: #999; font-style: italic; padding: 20px; text-align: center; }}
            </style>
            <meta http-equiv="refresh" content="30">
        </head>
        <body>
            <div class="container">
                <h1>Maestro Assessment Server Status</h1>

                <div class="status-box">
                    <h2>System Metrics</h2>
                    <div class="metric">
                        <div class="metric-label">Form Submissions</div>
                        <div class="metric-value">{artifact_counts['form_submissions']}</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Uploaded Files</div>
                        <div class="metric-value">{artifact_counts['docs']}</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Processed Configs</div>
                        <div class="metric-value">{artifact_counts['processed']}</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Access Validations</div>
                        <div class="metric-value">{artifact_counts['access_validations']}</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Server Status</div>
                        <div class="metric-value success">Running</div>
                    </div>
                </div>

                <div class="status-box">
                    <h2>Recent Form Submissions (Last 10)</h2>
                    {"<table><tr><th>Run ID</th><th>Company</th><th>Provider</th><th>Project/Account</th><th>Files</th><th>Submitted</th><th>Action</th></tr>" +
                     "".join([f"<tr><td>{s['run_id']}</td><td>{s['company']}</td><td>{s['provider']}</td><td>{s['project']}</td><td>{s['files']}</td><td class='timestamp'>{s['submitted_at']}</td><td><a href='/view/{s['filename']}'>View</a></td></tr>" for s in submissions]) +
                     "</table>" if submissions else "<div class='empty'>No submissions yet</div>"}
                </div>

                <div class="status-box">
                    <h2>Recent Uploaded Files (Last 10)</h2>
                    {"<table><tr><th>Filename</th><th>Size</th><th>Modified</th></tr>" +
                     "".join([f"<tr><td>{d['filename']}</td><td>{d['size']} bytes</td><td class='timestamp'>{d['modified']}</td></tr>" for d in uploaded_docs]) +
                     "</table>" if uploaded_docs else "<div class='empty'>No files uploaded yet</div>"}
                </div>

                <div class="status-box">
                    <h2>Quick Links</h2>
                    <a href="/" class="btn">Assessment Form</a>
                    <a href="/test-upload.html" class="btn">Test Upload</a>
                    <a href="/status" class="btn">Refresh Status</a>
                </div>

                <div class="status-box">
                    <p class="timestamp">Page refreshes every 30 seconds | Last updated: {datetime.now().isoformat()}</p>
                </div>
            </div>
        </body>
        </html>
        """

        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.end_headers()
        self.wfile.write(html.encode('utf-8'))

    def parse_multipart(self, content_type, body):
        """Parse multipart form data without cgi module"""
        # Extract boundary
        boundary_match = re.search(r'boundary=([^;]+)', content_type)
        if not boundary_match:
            return {}, []

        boundary = boundary_match.group(1).strip('"')
        if boundary.startswith('----'):
            boundary = boundary[2:]  # Remove extra dashes if present

        # Split by boundary
        parts = body.split(f'--{boundary}'.encode())

        form_data = {}
        files = []

        for part in parts[1:-1]:  # Skip first (empty) and last (closing)
            if not part:
                continue

            # Split headers and content
            header_end = part.find(b'\r\n\r\n')
            if header_end == -1:
                header_end = part.find(b'\n\n')
                if header_end == -1:
                    continue

            headers = part[:header_end].decode('utf-8', errors='ignore')
            # Get raw content - be careful with the offset based on line ending type
            if part.find(b'\r\n\r\n') != -1:
                content = part[header_end+4:]  # Skip \r\n\r\n
            else:
                content = part[header_end+2:]  # Skip \n\n

            # Remove only trailing \r\n, NOT the content itself
            content = content.rstrip(b'\r\n')

            # Parse content-disposition header
            name_match = re.search(r'name="([^"]+)"', headers)
            if not name_match:
                continue

            field_name = name_match.group(1)
            filename_match = re.search(r'filename="([^"]+)"', headers)

            if filename_match:
                # It's a file
                filename = filename_match.group(1)
                if filename:  # Only process if there's actually a file
                    # Clean file content - remove any trailing boundary markers
                    file_content = content
                    if file_content.endswith(b'\r\n--'):
                        file_content = file_content[:-4]
                    elif file_content.endswith(b'\n--'):
                        file_content = file_content[:-3]
                    elif file_content.endswith(b'--'):
                        file_content = file_content[:-2]

                    files.append({
                        'field_name': field_name,
                        'filename': filename,
                        'content': file_content
                    })
            else:
                # Regular field - clean up the value
                try:
                    # Decode and remove boundary markers from form fields
                    value = content.decode('utf-8').strip()
                    if value.endswith('\r\n--'):
                        value = value[:-4]
                    elif value.endswith('\n--'):
                        value = value[:-3]
                    elif value.endswith('--'):
                        value = value[:-2]
                    value = value.strip()

                    if field_name in form_data:
                        # Multiple values for same field
                        if not isinstance(form_data[field_name], list):
                            form_data[field_name] = [form_data[field_name]]
                        form_data[field_name].append(value)
                    else:
                        form_data[field_name] = value
                except:
                    form_data[field_name] = content

        return form_data, files

    def do_POST(self):
        """Handle form submission with file uploads"""
        if self.path == '/submit':
            # Create directories if they don't exist
            os.makedirs('form_submissions', exist_ok=True)
            os.makedirs('docs', exist_ok=True)

            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            form_data = {}
            uploaded_files = []

            content_type = self.headers['Content-Type']
            content_length = int(self.headers['Content-Length'])
            body = self.rfile.read(content_length)

            if 'multipart/form-data' in content_type:
                # Parse multipart data
                fields, files = self.parse_multipart(content_type, body)
                form_data.update(fields)

                # Save uploaded files
                for file_info in files:
                    if file_info['filename']:
                        # Clean filename
                        safe_filename = os.path.basename(file_info['filename'])
                        safe_filename = safe_filename.replace(' ', '_')
                        safe_filename = re.sub(r'[^\w\-_\.]', '', safe_filename)

                        # Save to docs directory
                        file_path = os.path.join('docs', f'{timestamp}_{safe_filename}')

                        with open(file_path, 'wb') as f:
                            f.write(file_info['content'])

                        uploaded_files.append({
                            'original_name': file_info['filename'],
                            'saved_as': f'{timestamp}_{safe_filename}',
                            'path': file_path,
                            'size': len(file_info['content'])
                        })
                        print(f"Saved file: {file_path}")

            else:
                # Handle URL-encoded form data (no files)
                parsed_data = urllib.parse.parse_qs(body.decode('utf-8'))
                for key, values in parsed_data.items():
                    form_data[key] = values[0] if len(values) == 1 else values

            # Add metadata
            form_data['form_version'] = '2.0'
            form_data['submitted_at'] = datetime.now().isoformat()
            form_data['run_id'] = f'maestro_{timestamp}'

            # Add uploaded files info
            if uploaded_files:
                form_data['uploaded_files'] = [f['original_name'] for f in uploaded_files]
                form_data['uploaded_files_details'] = uploaded_files

            # Save form data
            filename = f'form_data_{timestamp}.json'
            filepath = os.path.join('form_submissions', filename)

            with open(filepath, 'w') as f:
                json.dump(form_data, f, indent=2)

            print(f"Form data saved to: {filepath}")
            if uploaded_files:
                print(f"Uploaded {len(uploaded_files)} files to docs/")

            # Send response
            response = f"""
            <html>
            <body style="font-family: monospace; padding: 20px;">
                <h2>✅ Form Submitted Successfully!</h2>
                <p>Saved to: form_submissions/{filename}</p>
                <p>Uploaded files: {len(uploaded_files)}</p>
                <ul>
                    {''.join([f"<li>📄 {f['original_name']} → docs/{f['saved_as']}</li>" for f in uploaded_files])}
                </ul>
                <p>Run ID: maestro_{timestamp}</p>
                <a href="/">Submit another form</a>
            </body>
            </html>
            """

            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(response.encode())

    def do_OPTIONS(self):
        """Handle CORS preflight"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

def run_server(port=8080):
    """Run the form server"""
    server_address = ('', port)
    httpd = http.server.HTTPServer(server_address, FormHandler)

    print(f"""
╔═══════════════════════════════════════════════════════════╗
║          Maestro Assessment Form Server v2.0              ║
╠═══════════════════════════════════════════════════════════╣
║  Server running at: http://localhost:{port}              ║
║  Form: http://localhost:{port}/                          ║
║  Status: http://localhost:{port}/status                  ║
║  Test Upload: http://localhost:{port}/test-upload.html   ║
║  Form submissions saved to: form_submissions/             ║
║  Uploaded files saved to: docs/                           ║
║  Press Ctrl+C to stop                                     ║
╚═══════════════════════════════════════════════════════════╝
    """)

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\nServer stopped.")
        httpd.server_close()

if __name__ == '__main__':
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    run_server(port)