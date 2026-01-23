#!/usr/bin/env python3

"""
Simple Form Submission Server for Maestro Assessment
Receives form data via POST and saves it as JSON files
"""

import json
import os
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
from datetime import datetime
import subprocess
import webbrowser
from pathlib import Path

# Configuration
PORT = 8080
SAVE_DIR = "./form_submissions"
ARTIFACTS_DIR = "./artifacts"

class FormHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        """Serve the HTML form"""
        if self.path == '/':
            # Redirect to the form
            self.send_response(301)
            self.send_header('Location', '/form')
            self.end_headers()
        elif self.path == '/form':
            # Serve the assessment form with proper submission handling
            try:
                with open('online-assessment-form-v2.html', 'r') as f:
                    content = f.read()

                    # Replace the generateAssessment function to submit to server
                    content = content.replace(
                        'function generateAssessment() {',
                        '''function generateAssessment() {
                        // Submit to server instead of just showing command
                        const form = document.getElementById('assessment-form');
                        const formData = new FormData(form);

                        // Add auth mode and iac mode
                        formData.append('auth_mode', authMode || 'adc');
                        formData.append('iac_mode', iacMode || 'no_iac');
                        formData.append('k8s_mode', contextMode || 'custom');

                        // Submit form
                        form.action = '/submit';
                        form.method = 'POST';
                        form.submit();
                        return;

                        // Original function continues below (unused now)
                        '''
                    )

                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html')
                    self.end_headers()
                    self.wfile.write(content.encode())
            except FileNotFoundError:
                self.send_error(404, "Form not found")
        elif self.path == '/status':
            # Show submission status
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(self.get_status_page().encode())
        else:
            self.send_error(404)

    def do_POST(self):
        """Handle form submission"""
        if self.path == '/submit':
            # Get content length
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length).decode('utf-8')

            # Parse form data
            form_data = parse_qs(post_data)

            # Clean up form data (remove array notation and empty values)
            cleaned_data = {}
            for key, values in form_data.items():
                clean_key = key.replace('[]', '')
                # Filter out empty values
                non_empty_values = [v for v in values if v]
                if non_empty_values:
                    if len(non_empty_values) == 1:
                        cleaned_data[clean_key] = non_empty_values[0]
                    else:
                        cleaned_data[clean_key] = non_empty_values

            # Add metadata
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            run_id = f"maestro_{timestamp}"
            cleaned_data['form_version'] = '2.0'
            cleaned_data['submitted_at'] = datetime.now().isoformat()
            cleaned_data['run_id'] = run_id

            # Create save directory if it doesn't exist
            os.makedirs(SAVE_DIR, exist_ok=True)

            # Save form data
            filename = f"{SAVE_DIR}/form_data_{timestamp}.json"
            with open(filename, 'w') as f:
                json.dump(cleaned_data, f, indent=2)

            print(f"\n✅ Form data saved to: {filename}")

            # Generate response HTML
            response_html = self.get_success_page(filename, run_id, cleaned_data)

            # Send response
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(response_html.encode())

            # Auto-run Phase 00 if requested
            if 'auto_process' in form_data and form_data['auto_process'][0] == 'yes':
                self.run_phase_00(filename, run_id)

    def get_success_page(self, filename, run_id, data):
        """Generate success page with next steps"""
        confidence = self.calculate_confidence(data)

        return f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Form Submitted Successfully</title>
            <style>
                body {{
                    font-family: system-ui, -apple-system, sans-serif;
                    max-width: 900px;
                    margin: 40px auto;
                    padding: 20px;
                    background: #f5f5f5;
                }}
                .container {{
                    background: white;
                    border-radius: 12px;
                    padding: 40px;
                    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
                }}
                h1 {{ color: #10B981; }}
                .info-box {{
                    background: #F0FDF4;
                    border: 1px solid #10B981;
                    border-radius: 8px;
                    padding: 20px;
                    margin: 20px 0;
                }}
                .command-box {{
                    background: #1a1a1a;
                    color: #10B981;
                    padding: 15px;
                    border-radius: 6px;
                    font-family: 'Courier New', monospace;
                    margin: 10px 0;
                    overflow-x: auto;
                }}
                .metric {{
                    display: inline-block;
                    margin: 10px 20px 10px 0;
                }}
                .metric-label {{
                    color: #666;
                    font-size: 12px;
                }}
                .metric-value {{
                    font-size: 24px;
                    font-weight: bold;
                    color: #333;
                }}
                button {{
                    background: #4F46E5;
                    color: white;
                    border: none;
                    padding: 12px 24px;
                    border-radius: 6px;
                    cursor: pointer;
                    margin: 5px;
                }}
                button:hover {{
                    background: #4338CA;
                }}
                .actions {{
                    margin-top: 30px;
                    padding-top: 30px;
                    border-top: 1px solid #E5E7EB;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>✅ Assessment Form Submitted Successfully!</h1>

                <div class="info-box">
                    <div class="metric">
                        <div class="metric-label">Run ID</div>
                        <div class="metric-value">{run_id}</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Confidence Score</div>
                        <div class="metric-value">{confidence}%</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Company</div>
                        <div class="metric-value">{data.get('company_name', 'N/A')}</div>
                    </div>
                </div>

                <h2>📁 File Saved</h2>
                <div class="command-box">{filename}</div>

                <h2>🚀 Next Steps</h2>

                <h3>Option 1: Run Phase 00 Now</h3>
                <div class="command-box">
cd {os.getcwd()}
./00-input/process-assessment.sh --form-data {filename} --run-id {run_id}
                </div>
                <button onclick="runPhase00()">▶️ Run Phase 00 Automatically</button>

                <h3>Option 2: Manual Processing</h3>
                <ol>
                    <li>Review the saved form data</li>
                    <li>Run Phase 00 with the command above</li>
                    <li>Check artifacts in: <code>./artifacts/processed/</code></li>
                </ol>

                <h3>Option 3: View Raw Data</h3>
                <div class="command-box">cat {filename} | python3 -m json.tool</div>

                <div class="actions">
                    <button onclick="window.location='/form'">📝 Submit Another Form</button>
                    <button onclick="window.location='/status'">📊 View All Submissions</button>
                    <button onclick="copyCommand()">📋 Copy Phase 00 Command</button>
                </div>
            </div>

            <script>
                function runPhase00() {{
                    fetch('/run-phase00?file={filename}&run_id={run_id}', {{method: 'POST'}})
                        .then(response => response.text())
                        .then(data => {{
                            alert('Phase 00 started! Check terminal for output.');
                        }});
                }}

                function copyCommand() {{
                    const command = './00-input/process-assessment.sh --form-data {filename} --run-id {run_id}';
                    navigator.clipboard.writeText(command).then(() => {{
                        alert('Command copied to clipboard!');
                    }});
                }}
            </script>
        </body>
        </html>
        """

    def get_status_page(self):
        """Show all submissions"""
        os.makedirs(SAVE_DIR, exist_ok=True)
        files = sorted([f for f in os.listdir(SAVE_DIR) if f.endswith('.json')], reverse=True)

        rows = ""
        for f in files[:20]:  # Show last 20 submissions
            path = os.path.join(SAVE_DIR, f)
            try:
                with open(path, 'r') as file:
                    data = json.load(file)
                    rows += f"""
                    <tr>
                        <td>{data.get('run_id', 'N/A')}</td>
                        <td>{data.get('company_name', 'N/A')}</td>
                        <td>{data.get('cloud_provider', 'N/A')}</td>
                        <td>{data.get('submitted_at', 'N/A')}</td>
                        <td>
                            <button onclick="window.location='/process?file={f}'">Process</button>
                            <button onclick="window.location='/view?file={f}'">View</button>
                        </td>
                    </tr>
                    """
            except:
                continue

        return f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Form Submissions</title>
            <style>
                body {{
                    font-family: system-ui, -apple-system, sans-serif;
                    max-width: 1200px;
                    margin: 40px auto;
                    padding: 20px;
                    background: #f5f5f5;
                }}
                .container {{
                    background: white;
                    border-radius: 12px;
                    padding: 40px;
                    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
                }}
                table {{
                    width: 100%;
                    border-collapse: collapse;
                    margin-top: 20px;
                }}
                th, td {{
                    text-align: left;
                    padding: 12px;
                    border-bottom: 1px solid #E5E7EB;
                }}
                th {{
                    background: #F9FAFB;
                    font-weight: 600;
                }}
                button {{
                    background: #4F46E5;
                    color: white;
                    border: none;
                    padding: 6px 12px;
                    border-radius: 4px;
                    cursor: pointer;
                    margin: 0 2px;
                }}
                button:hover {{
                    background: #4338CA;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📊 Form Submissions</h1>
                <button onclick="window.location='/form'">📝 New Submission</button>

                <table>
                    <thead>
                        <tr>
                            <th>Run ID</th>
                            <th>Company</th>
                            <th>Provider</th>
                            <th>Submitted</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {rows if rows else '<tr><td colspan="5">No submissions yet</td></tr>'}
                    </tbody>
                </table>
            </div>
        </body>
        </html>
        """

    def calculate_confidence(self, data):
        """Calculate confidence score"""
        confidence = 0

        # Required fields (60 points)
        required = ['company_name', 'website_url', 'contact_email', 'industry',
                   'cloud_provider', 'serving_customers', 'migration_timeline', 'current_budget']
        for field in required:
            if data.get(field):
                confidence += 7.5

        # Optional valuable fields (40 points)
        if data.get('terraform_repo'): confidence += 10
        if data.get('app_repos'): confidence += 5
        if data.get('current_hosting'): confidence += 5
        if data.get('databases'): confidence += 5
        if data.get('k8s_context'): confidence += 5
        if data.get('compliance'): confidence += 5
        if data.get('special_requirements'): confidence += 5

        return min(int(confidence), 100)

    def run_phase_00(self, filename, run_id):
        """Execute Phase 00 processing"""
        try:
            cmd = f"./00-input/process-assessment.sh --form-data {filename} --run-id {run_id}"
            subprocess.Popen(cmd, shell=True)
            print(f"✅ Started Phase 00 processing for {run_id}")
        except Exception as e:
            print(f"❌ Error running Phase 00: {e}")

    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

def main():
    # Create directories
    os.makedirs(SAVE_DIR, exist_ok=True)
    os.makedirs(ARTIFACTS_DIR, exist_ok=True)

    # Start server
    server_address = ('', PORT)
    httpd = HTTPServer(server_address, FormHandler)

    print(f"""
╔════════════════════════════════════════════════════════════════╗
║           Maestro Assessment Form Server v1.0                  ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Server running at: http://localhost:{PORT}                      ║
║                                                                ║
║  Available endpoints:                                          ║
║    • http://localhost:{PORT}/form    - Assessment form          ║
║    • http://localhost:{PORT}/status  - View submissions         ║
║                                                                ║
║  Form submissions saved to: {SAVE_DIR}/              ║
║                                                                ║
║  Press Ctrl+C to stop the server                              ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
    """)

    # Auto-open browser
    webbrowser.open(f'http://localhost:{PORT}/form')

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\n✅ Server stopped gracefully")
        httpd.server_close()

if __name__ == '__main__':
    main()