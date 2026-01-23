# 🚀 Maestro Assessment - Quick Start Guide

## Option 1: Web Server with Form Submission (Recommended)

### Start the server:
```bash
./start.sh
```

This will:
1. Start a local web server on port 8080
2. Open your browser automatically
3. Show the assessment form

### Submit a form:
1. Fill out the form fields
2. Click "Submit Assessment"
3. Form data is automatically saved to `form_submissions/`
4. You'll get a success page with the Phase 00 command

### Process the submission:
The success page shows the exact command to run Phase 00.

---

## Option 2: AJAX-Enabled Form (Standalone)

### Open the AJAX form:
```bash
open online-assessment-form-ajax.html
```

This form works without a server:
- Submits via AJAX if server is running
- Falls back to downloading JSON file if server is not running
- Shows success modal with next steps

---

## Option 3: Manual Process (Original)

### 1. Open the full form:
```bash
open online-assessment-form-v2.html
```

### 2. Extract data using browser console:
Press F12, go to Console tab, and run:
```javascript
const form = document.getElementById('assessment-form');
const formData = new FormData(form);
const data = {};

for (let [key, value] of formData.entries()) {
    if (key.endsWith('[]')) {
        const cleanKey = key.slice(0, -2);
        if (!data[cleanKey]) data[cleanKey] = [];
        if (value) data[cleanKey].push(value);
    } else {
        data[key] = value;
    }
}

data.form_version = '2.0';
data.submitted_at = new Date().toISOString();
copy(JSON.stringify(data, null, 2));
console.log('✅ Copied to clipboard!');
```

### 3. Save as JSON file and process:
```bash
# Save clipboard content to file
pbpaste > form_data.json  # macOS

# Run Phase 00
./00-input/process-assessment.sh --form-data ./form_data.json
```

---

## Option 4: Quick Test Data

### Generate and process test data:
```bash
# Generate test data
./generate-test-data.sh "Test Company" gcp adc

# Process it
./00-input/process-assessment.sh --form-data ./form_data_*.json
```

---

## 📁 Where Everything Gets Saved

### Form Submissions:
```
form_submissions/
└── form_data_TIMESTAMP.json    # Raw form submissions
```

### Processing Artifacts:
```
artifacts/
├── raw/                        # Original form data
├── processed/                  # Processed configurations
│   ├── form_processed_*.json   # Structured data
│   ├── discovery_config_*.json # Config for Phase 01
│   └── execute_phase_01_*.sh   # Ready-to-run script
├── metadata/                   # Run metadata
└── logs/                       # Execution logs
```

---

## 🎯 Complete Workflow Example

### 1. Start the server:
```bash
./start.sh
```

### 2. Fill and submit form in browser

### 3. Run Phase 00 (from success page command):
```bash
./00-input/process-assessment.sh \
    --form-data ./form_submissions/form_data_20260119_130000.json \
    --run-id maestro_20260119_130000
```

### 4. Check the results:
```bash
# View the discovery config
cat artifacts/processed/discovery_config_*.json | python3 -m json.tool

# Run Phase 01 (when ready)
./artifacts/processed/execute_phase_01_*.sh
```

---

## 🛠️ Troubleshooting

### Port already in use:
```bash
# Find process using port 8080
lsof -i :8080

# Kill it
kill $(lsof -t -i:8080)
```

### Python not found:
```bash
# Check Python installation
python3 --version

# Install if needed
# macOS: brew install python3
# Ubuntu: sudo apt install python3
```

### Permission denied:
```bash
# Make all scripts executable
chmod +x *.sh
chmod +x 00-input/*.sh
chmod +x *.py
```

---

## 📋 Server Endpoints

When the server is running:

- **http://localhost:8080/form** - Assessment form
- **http://localhost:8080/status** - View all submissions
- **http://localhost:8080/submit** - Form submission endpoint

---

## 💡 Tips

1. **Use the web server** (Option 1) for the smoothest experience
2. **Test data generator** is great for quick testing
3. **AJAX form** works even without the server running
4. **Check artifacts/** directory for all generated files
5. **Confidence score** shows data quality (aim for >70%)

---

## Need Help?

Check the main README.md for detailed documentation or look at the generated artifacts in the `artifacts/processed/` directory after running Phase 00.