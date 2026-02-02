#!/bin/bash
# Bootstrap script for the DagKnows installation wizard
#
# Usage:
#   ./install.sh
#
# This script is the RECOMMENDED entry point for fresh installations.
# It ensures all prerequisites (make, python3) are installed before
# running the full installation wizard.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo -e "${GREEN}${BOLD}  $1${NC}"
    echo -e "${GREEN}${BOLD}============================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_header "DagKnows Installation Bootstrap"

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
print_info "Working directory: $SCRIPT_DIR"
echo ""

# Check if running as root (warn but don't block)
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root. Some operations may behave differently."
    echo ""
fi

# Detect OS
print_info "Detecting operating system..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    print_success "Detected: $PRETTY_NAME"
else
    OS="unknown"
    print_warning "Could not detect OS. Assuming Debian-based system."
fi
echo ""

# Install make if not present
print_info "Checking prerequisites..."

if ! command -v make &> /dev/null; then
    print_warning "make is not installed. Installing..."

    case "$OS" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y make
            ;;
        amzn|rhel|centos|fedora)
            sudo yum install -y make
            ;;
        *)
            # Try apt first, then yum
            if command -v apt-get &> /dev/null; then
                sudo apt-get update
                sudo apt-get install -y make
            elif command -v yum &> /dev/null; then
                sudo yum install -y make
            else
                print_error "Could not install make. Please install it manually."
                exit 1
            fi
            ;;
    esac

    if command -v make &> /dev/null; then
        print_success "make installed successfully"
    else
        print_error "Failed to install make"
        exit 1
    fi
else
    print_success "make is installed"
fi

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    print_warning "Python 3 is not installed. Installing..."

    case "$OS" in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y python3
            ;;
        amzn|rhel|centos|fedora)
            sudo yum install -y python3
            ;;
        *)
            if command -v apt-get &> /dev/null; then
                sudo apt-get update
                sudo apt-get install -y python3
            elif command -v yum &> /dev/null; then
                sudo yum install -y python3
            else
                print_error "Could not install Python 3. Please install it manually."
                exit 1
            fi
            ;;
    esac

    if command -v python3 &> /dev/null; then
        print_success "Python 3 installed successfully"
    else
        print_error "Failed to install Python 3"
        exit 1
    fi
else
    print_success "Python 3 is installed"
fi

echo ""
print_info "All prerequisites satisfied. Starting installation wizard..."
echo ""

# Run the Python installation script directly
# (We run python3 directly instead of 'make install' to avoid any make-related issues)
python3 install.py

