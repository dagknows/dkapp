#!/bin/bash
# Setup automatic restart for DagKnows on system boot

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${DKAPP_INSTALL_DIR:-$SCRIPT_DIR}"
PASSPHRASE_FILE="/root/.dkapp-passphrase"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${GREEN}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

print_header "DagKnows Auto-Restart Setup"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check prerequisites
if [ ! -f "$SCRIPT_DIR/.env.gpg" ]; then
    print_error "No encrypted environment file found (.env.gpg)"
    echo "Please run the installation first to configure DagKnows."
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    print_error "docker-compose.yml not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/db-docker-compose.yml" ]; then
    print_error "db-docker-compose.yml not found in $SCRIPT_DIR"
    exit 1
fi

# Ensure Docker service is enabled
echo "Enabling Docker service to start on boot..."
systemctl enable docker
print_success "Docker service enabled"

# Prompt for passphrase handling
echo ""
print_header "Password Handling for Auto-Restart"
echo ""
echo "For automatic restart after system reboot, one of these is needed:"
echo ""
echo -e "  ${BOLD}1. Store passphrase in protected file (Recommended)${NC}"
echo "     - Passphrase stored in $PASSPHRASE_FILE (root-only access)"
echo "     - Fully automated restart, no manual intervention needed"
echo ""
echo -e "  ${BOLD}2. Keep .env file unencrypted${NC}"
echo "     - Simpler but less secure"
echo "     - Environment variables visible in plaintext"
echo ""
echo -e "  ${BOLD}3. Manual start after reboot${NC}"
echo "     - Most secure option"
echo "     - You must run 'make updb && make up' after each reboot"
echo ""

read -p "Choose option (1/2/3) [1]: " choice
choice=${choice:-1}

case $choice in
    1)
        echo ""
        echo "Setting up passphrase file for auto-restart..."
        echo -e "${YELLOW}Enter your GPG passphrase (same as used to encrypt .env):${NC}"
        read -s passphrase
        echo ""

        # Verify passphrase works (use --passphrase-fd to avoid exposing in process list)
        echo "Verifying passphrase..."
        test_file=$(mktemp)
        chmod 600 "$test_file"
        trap "rm -f $test_file" EXIT
        if echo "$passphrase" | gpg --batch --passphrase-fd 0 -o "$test_file" -d "$SCRIPT_DIR/.env.gpg" 2>/dev/null; then
            rm -f "$test_file"
            print_success "Passphrase verified successfully"

            # Store passphrase securely
            echo "$passphrase" > "$PASSPHRASE_FILE"
            chmod 600 "$PASSPHRASE_FILE"
            chown root:root "$PASSPHRASE_FILE"
            print_success "Passphrase stored in $PASSPHRASE_FILE (root-only access)"
        else
            rm -f "$test_file"
            print_error "Passphrase verification failed. Please check your passphrase."
            exit 1
        fi
        ;;
    2)
        echo ""
        echo "Decrypting .env file permanently..."
        echo -e "${YELLOW}Enter your GPG passphrase:${NC}"
        read -s passphrase
        echo ""

        # Use --passphrase-fd to avoid exposing passphrase in process list
        if echo "$passphrase" | gpg --batch --passphrase-fd 0 -o "$SCRIPT_DIR/.env" -d "$SCRIPT_DIR/.env.gpg" 2>/dev/null; then
            chmod 600 "$SCRIPT_DIR/.env"
            print_success ".env file decrypted"
            print_warning "WARNING: .env file is now unencrypted. Ensure proper file permissions."
        else
            print_error "Decryption failed. Please check your passphrase."
            exit 1
        fi
        ;;
    3)
        echo ""
        echo "Manual mode selected. Systemd services will not be installed."
        echo "You will need to run 'make updb && make up' after each reboot."
        exit 0
        ;;
    *)
        print_error "Invalid option"
        exit 1
        ;;
esac

# Copy and configure startup script
echo ""
echo "Installing startup script..."
chmod +x "$SCRIPT_DIR/dkapp-startup.sh"

# Update paths in startup script
sed -i "s|DKAPP_DIR=\"\${DKAPP_DIR:-/opt/dkapp}\"|DKAPP_DIR=\"\${DKAPP_DIR:-$INSTALL_DIR}\"|g" "$SCRIPT_DIR/dkapp-startup.sh"

# Install systemd service files
echo "Installing systemd service files..."

for service in dkapp-db.service dkapp.service; do
    # Copy service file
    cp "$SCRIPT_DIR/$service" /etc/systemd/system/

    # Update paths in service file
    sed -i "s|/opt/dkapp|$INSTALL_DIR|g" "/etc/systemd/system/$service"
done

# Reload systemd and enable services
systemctl daemon-reload
systemctl enable dkapp-db.service
systemctl enable dkapp.service

print_success "Systemd services installed and enabled"

echo ""
print_header "Auto-Restart Setup Complete"
echo ""
echo "Services installed:"
echo "  - dkapp-db.service  (PostgreSQL + Elasticsearch)"
echo "  - dkapp.service     (Application services)"
echo ""
echo "To start services now:"
echo "  sudo systemctl start dkapp-db.service"
echo "  sudo systemctl start dkapp.service"
echo ""
echo "To check status:"
echo "  sudo systemctl status dkapp-db.service"
echo "  sudo systemctl status dkapp.service"
echo ""
echo "To view logs:"
echo "  sudo journalctl -u dkapp-db.service"
echo "  sudo journalctl -u dkapp.service"
echo "  cat /var/log/dkapp-startup.log"
echo ""
echo "To disable auto-restart:"
echo "  make disable-autorestart"
echo ""
