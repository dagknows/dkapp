#!/bin/bash
# DagKnows Application Log Rotation Setup Script
# Installs cron jobs for automatic log rotation
#
# Usage:
#   make setup-log-rotation
#
# This script sets up log rotation for BOTH:
#   - Application logs (logs/)
#   - Database logs (dblogs/)
#
# Log rotation policy:
#   - 0-3 days: uncompressed (.log)
#   - 3-7 days: compressed (.log.gz)
#   - 7+ days: deleted
#
# The cron jobs run daily at midnight.

set -e

# Handle interruptions gracefully
trap 'echo ""; echo -e "\033[0;31m✗ ERROR: Setup interrupted by user\033[0m"; exit 1' INT TERM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

print_header "DagKnows Application Log Rotation Setup"

cd "$SCRIPT_DIR"
print_info "Working directory: $SCRIPT_DIR"
echo ""

# Check if cron is available
if ! command -v crontab &> /dev/null; then
    print_error "crontab command not found"
    echo ""
    echo "cron is required for automatic log rotation."
    echo "Please install cron first:"
    echo "  Ubuntu/Debian: sudo apt install cron"
    echo "  Amazon Linux:  sudo yum install cronie"
    echo "  RHEL:          sudo yum install cronie"
    exit 1
fi

# Check existing cron jobs for both app and db
APP_CRON_EXISTS=false
DB_CRON_EXISTS=false

if crontab -l 2>/dev/null | grep -q "dkapp.*logs-rotate"; then
    APP_CRON_EXISTS=true
fi

if crontab -l 2>/dev/null | grep -q "dkapp.*dblogs-rotate"; then
    DB_CRON_EXISTS=true
fi

# If both already exist, show status and offer reinstall
if [ "$APP_CRON_EXISTS" = true ] && [ "$DB_CRON_EXISTS" = true ]; then
    print_header "Log Rotation Already Configured"

    print_success "Both log rotation cron jobs are already installed!"
    echo ""

    print_info "Current cron entries:"
    crontab -l 2>/dev/null | grep "dkapp.*logs-rotate" || true
    crontab -l 2>/dev/null | grep "dkapp.*dblogs-rotate" || true
    echo ""

    print_info "Log rotation policy:"
    echo "  - Logs 0-3 days old: kept as .log files"
    echo "  - Logs 3-7 days old: compressed to .log.gz"
    echo "  - Logs 7+ days old:  automatically deleted"
    echo ""

    echo -e "${BOLD}Log Management Commands:${NC}"
    echo -e "  ${BLUE}make logs-status${NC}       - Show app log disk usage"
    echo -e "  ${BLUE}make dblogs-status${NC}     - Show DB log disk usage"
    echo -e "  ${BLUE}make logs-rotate${NC}       - Run app log rotation now"
    echo -e "  ${BLUE}make dblogs-rotate${NC}     - Run DB log rotation now"
    echo ""

    read -r -p "Remove and reinstall cron jobs? [y/N]: " reinstall
    if [[ ! "$reinstall" =~ ^[Yy] ]]; then
        exit 0
    fi

    # Remove existing cron jobs
    print_info "Removing existing cron jobs..."
    crontab -l 2>/dev/null | grep -v "dkapp.*logs-rotate" | grep -v "dkapp.*dblogs-rotate" | crontab - 2>/dev/null || true
    print_success "Existing cron jobs removed"
    echo ""
    APP_CRON_EXISTS=false
    DB_CRON_EXISTS=false
fi

# Show status of individual cron jobs if only one exists
if [ "$APP_CRON_EXISTS" = true ] && [ "$DB_CRON_EXISTS" = false ]; then
    print_warning "App log rotation is configured, but DB log rotation is missing"
    echo ""
fi

if [ "$APP_CRON_EXISTS" = false ] && [ "$DB_CRON_EXISTS" = true ]; then
    print_warning "DB log rotation is configured, but app log rotation is missing"
    echo ""
fi

# Display log rotation policy
print_header "Log Rotation Policy"

echo "This will install cron jobs that run daily at midnight."
echo ""
echo -e "${BOLD}Log Retention Policy (applies to both app and DB logs):${NC}"
echo ""
echo "  ┌─────────────────┬──────────────────────────────┐"
echo "  │  Age            │  Action                      │"
echo "  ├─────────────────┼──────────────────────────────┤"
echo "  │  0-3 days       │  Keep as .log (uncompressed) │"
echo "  │  3-7 days       │  Compress to .log.gz         │"
echo "  │  7+ days        │  Delete automatically        │"
echo "  └─────────────────┴──────────────────────────────┘"
echo ""
echo -e "${BOLD}Log Directories:${NC}"
echo "  Application logs: $SCRIPT_DIR/logs/"
echo "  Database logs:    $SCRIPT_DIR/dblogs/"
echo ""

# Check current log disk usage for both directories
print_info "Current log disk usage:"
echo ""
echo "  Application logs:"
if [ -d "$SCRIPT_DIR/logs" ]; then
    du -sh "$SCRIPT_DIR/logs" 2>/dev/null | sed 's/^/    /' || echo "    (empty)"
else
    echo "    (directory not created yet)"
fi
echo ""
echo "  Database logs:"
if [ -d "$SCRIPT_DIR/dblogs" ]; then
    du -sh "$SCRIPT_DIR/dblogs" 2>/dev/null | sed 's/^/    /' || echo "    (empty)"
else
    echo "    (directory not created yet)"
fi
echo ""

# Auto-proceed for fresh installs (no confirmation needed)
print_info "Installing log rotation cron jobs..."
echo ""

# Install app log cron job
if [ "$APP_CRON_EXISTS" = false ]; then
    print_info "Installing app log rotation cron job..."
    if make logs-cron-install 2>/dev/null; then
        print_success "App log rotation cron job installed"
    else
        print_error "Failed to install app log rotation cron job"
        echo ""
        echo "You can try manually:"
        echo "  cd $SCRIPT_DIR && make logs-cron-install"
        exit 1
    fi
fi

# Install DB log cron job
if [ "$DB_CRON_EXISTS" = false ]; then
    print_info "Installing DB log rotation cron job..."
    if make dblogs-cron-install 2>/dev/null; then
        print_success "DB log rotation cron job installed"
    else
        print_error "Failed to install DB log rotation cron job"
        echo ""
        echo "You can try manually:"
        echo "  cd $SCRIPT_DIR && make dblogs-cron-install"
        exit 1
    fi
fi

echo ""
print_header "Log Rotation Setup Complete"

print_success "Both cron jobs installed successfully!"
echo ""

print_info "Cron job details:"
echo "  Schedule:     Daily at midnight (0 0 * * *)"
echo "  App command:  make logs-rotate"
echo "  DB command:   make dblogs-rotate"
echo "  App log file: $SCRIPT_DIR/logs/cron.log"
echo "  DB log file:  $SCRIPT_DIR/dblogs/cron.log"
echo ""

echo -e "${BOLD}Useful Commands:${NC}"
echo -e "  ${BLUE}crontab -l${NC}             - View all cron jobs"
echo -e "  ${BLUE}make logs-rotate${NC}       - Run app log rotation manually"
echo -e "  ${BLUE}make dblogs-rotate${NC}     - Run DB log rotation manually"
echo -e "  ${BLUE}make logs-status${NC}       - Check app log disk usage"
echo -e "  ${BLUE}make dblogs-status${NC}     - Check DB log disk usage"
echo -e "  ${BLUE}make logs-cron-remove${NC}  - Remove app log cron job"
echo -e "  ${BLUE}make dblogs-cron-remove${NC}- Remove DB log cron job"
echo ""

echo -e "${BOLD}Other Log Commands:${NC}"
echo -e "  ${BLUE}make logs${NC}              - View live app logs"
echo -e "  ${BLUE}make dblogs${NC}            - View live DB logs"
echo -e "  ${BLUE}make logs-today${NC}        - View today's captured app logs"
echo -e "  ${BLUE}make dblogs-today${NC}      - View today's captured DB logs"
echo -e "  ${BLUE}make logs-errors${NC}       - View errors from app logs"
echo -e "  ${BLUE}make dblogs-errors${NC}     - View errors from DB logs"
echo ""
