# dkapp
On prem version of the SaaS DagKnows app

## Requirements

* 16 GB Memory
* 50 GB Storage
* Ubuntu/Debian Linux (recommended)

## Automated Installation (Recommended)

We provide an automated installation wizard that guides you through the entire setup process.

### Quick Start

1. Clone this repository:

```bash
git clone https://github.com/dagknows/dkapp.git
cd dkapp
```

2. Run the installation wizard:

```bash
./install.sh
```

Or directly with Python:

```bash
python3 install.py
```

The wizard will:
- Update your system packages
- Install required dependencies (make, docker, docker-compose, etc.)
- Prompt you for required configuration values
- Set up and encrypt your configuration
- Start all services

### What the Wizard Asks For

The installation wizard will prompt you for:

1. **DagKnows URL**: Your public IP or domain (e.g., `https://192.168.1.100` or `https://dagknows.example.com`)
2. **Database Password**: Password for PostgreSQL database
3. **Super User Details**:
   - Email address
   - First and Last name
   - Password (⚠️ **Use the same password for encryption - see below**)
   - Organization name
4. **Mail Configuration** (optional):
   - Mail server details
   - SMTP credentials
5. **OpenAI Configuration** (optional):
   - API key
   - Organization ID
6. **Encryption Password**: Password to encrypt your `.env` file

**⚠️ IMPORTANT PASSWORD RECOMMENDATION:**
The wizard will prompt you to use the **same password** for both:
- Super User password
- Encryption password (for GPG)

This simplifies password management and ensures you only need to remember one password. The wizard will remind you of this during installation.

### After Installation

Once installation is complete, you can access DagKnows at the URL you configured.

**Useful Commands:**
```bash
make start         # Start all services (health checks, versioning, log capture)
make stop          # Stop all services and log capture processes
make restart       # Restart all services
make update        # Pull latest images and restart
make pull-latest   # Pull latest images (ignores version manifest)
make logs          # View application logs
make dblogs        # View database logs (live)
make status        # Show service status
make help          # Show all available commands
```

**Note:** Commands that require access to the encrypted `.env` file will prompt for your encryption password (which should be the same as your Super User password if you followed the wizard's recommendation).

### Auto-Restart on System Reboot (Recommended)

To ensure DagKnows automatically restarts after system reboots:

```bash
make setup-autorestart
```

This one-time setup:
- Stores your passphrase securely for automatic decryption
- Installs systemd services for reliable startup ordering
- Enables automatic recovery from system restarts

After setup, all services will automatically start when your system boots - no manual intervention needed.

**Additional commands:**
```bash
make autorestart-status    # Check configuration
make disable-autorestart   # Remove auto-restart
```

## Manual Installation

If you prefer to install manually or the automated wizard doesn't work for your setup:

1. Checkout this repo

```bash
git clone https://github.com/dagknows/dkapp.git
cd dkapp
```

2. Prepare Instance (Ubuntu):

```bash
sudo apt update && sudo apt upgrade -y
sudo apt-get install -y make
make prepare
```

3. Ensure Docker is Started (Ubuntu):

```bash
sudo systemctl restart docker
```

4. Configure Environment

Edit the `.env` file and set values for:

**Required Configuration:**
- `DAGKNOWS_URL` - Your public IP or domain
- `POSTGRESQL_DB_PASSWORD` - Database password
- `SUPER_USER` - Admin email
- `SUPER_USER_FIRSTNAME` - Admin first name
- `SUPER_USER_LASTNAME` - Admin last name
- `SUPER_PASSWORD` - Admin password
- `SUPER_USER_ORG` - Organization name
- `DEFAULT_ORG` - Should match SUPER_USER_ORG

**Optional Configuration:**
- `MAIL_DEFAULT_SENDER` - Email sender
- `MAIL_USERNAME` - Mail username
- `MAIL_SERVER` - SMTP server
- `MAIL_PASSWORD` - SMTP password
- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_ORG_ID` - OpenAI Organization ID

5. Encrypt configuration

```bash
make encrypt
```

This will prompt for a password and encrypt your `.env` file. Remember this password!

6. Start services

```bash
newgrp docker
make updb      # Waits for databases to be healthy + auto-starts DB log capture
make up logs
```

## Troubleshooting

### Docker Permission Denied

If you get "permission denied" errors with Docker:

**During Installation:**
The wizard automatically:
1. Adds your user to the docker group
2. Detects that the group isn't active in the current session
3. Uses `sg docker -c "command"` to run Docker commands with proper group permissions
4. **Does NOT use sudo** - relies on proper docker group membership

**After Installation:**
For manual commands, the docker group still won't be active in your current session. You have two options:

```bash
# Option 1: Activate docker group in current shell
newgrp docker
# Now you can run: make logs, make restart, etc.

# Option 2: Log out and log back in
# The docker group will be active automatically in new sessions
```

**For individual commands without newgrp:**
```bash
sg docker -c "make logs"
sg docker -c "make restart"
```

**Why this happens:**
When you're added to a group, the change doesn't take effect in the current shell session. The installation wizard handles this by using `sg docker` during installation, but for your manual commands afterward, you need to either:
- Run `newgrp docker` once per session
- Log out and back in (permanent solution)
- Prefix commands with `sg docker -c`

### Services Not Starting

Check logs for errors:

```bash
make dblogs  # For database services
make logs    # For application services
```

### Reset Installation

To start fresh:

```bash
make down
rm -rf postgres-data esdata1 elastic_backup
# Then run installation again
```

## Security Notes

- Always use strong passwords for database and admin accounts
- The `.env` file is encrypted using GPG for security
- Keep your encryption password safe - you'll need it for management commands
- Use HTTPS in production (configure SSL certificates)

## Support

For issues and support, please visit: https://github.com/dagknows/dkapp/issues
