#!/bin/bash
# Simple wrapper script for the DagKnows installation wizard

set -e

echo "Starting DagKnows Installation Wizard..."
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y python3
fi

# Run the Python installation script
python3 install.py

