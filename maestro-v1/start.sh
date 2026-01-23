#!/bin/bash

# Maestro Assessment System Launcher
# Starts the form server and opens the browser

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
PORT=8080
SERVER_SCRIPT="form-server.py"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Maestro Assessment System Launcher                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 is required but not installed${NC}"
    exit 1
fi

# Check if form server exists
if [[ ! -f "$SERVER_SCRIPT" ]]; then
    echo -e "${RED}❌ Form server not found: $SERVER_SCRIPT${NC}"
    exit 1
fi

# Check if port is already in use
if lsof -i :$PORT &> /dev/null; then
    echo -e "${YELLOW}⚠️  Port $PORT is already in use${NC}"
    echo -e "Either:"
    echo -e "  1. Stop the existing server: ${GREEN}kill \$(lsof -t -i:$PORT)${NC}"
    echo -e "  2. Use the existing server at: ${GREEN}http://localhost:$PORT${NC}"
    echo
    read -p "Open browser to existing server? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "http://localhost:$PORT/form" 2>/dev/null || xdg-open "http://localhost:$PORT/form" 2>/dev/null || echo "Please open: http://localhost:$PORT/form"
    fi
    exit 0
fi

# Create necessary directories
echo -e "${BLUE}Creating directories...${NC}"
mkdir -p form_submissions
mkdir -p artifacts/{raw,processed,metadata,logs}
echo -e "${GREEN}✓ Directories created${NC}"

# Make scripts executable
echo -e "${BLUE}Setting permissions...${NC}"
chmod +x 00-input/process-assessment.sh 2>/dev/null || true
chmod +x generate-test-data.sh 2>/dev/null || true
chmod +x form-server.py 2>/dev/null || true
echo -e "${GREEN}✓ Permissions set${NC}"

# Start the server
echo
echo -e "${GREEN}🚀 Starting form server on port $PORT...${NC}"
echo
echo -e "${YELLOW}Options:${NC}"
echo -e "  • Submit form:     ${GREEN}http://localhost:$PORT/form${NC}"
echo -e "  • View status:     ${GREEN}http://localhost:$PORT/status${NC}"
echo -e "  • Quick test form: ${GREEN}Open online-assessment-form-ajax.html${NC}"
echo
echo -e "${YELLOW}Press Ctrl+C to stop the server${NC}"
echo

# Start Python server
python3 "$SERVER_SCRIPT"