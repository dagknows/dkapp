# DagKnows Quick Start Guide

Get DagKnows up and running in minutes!

## Prerequisites

- Ubuntu/Debian Linux (16.04 or later recommended)
- 16 GB RAM minimum
- 50 GB disk space
- Internet connection
- Root/sudo access

## Installation (5 Minutes)

### Step 1: Clone the Repository

```bash
git clone https://github.com/dagknows/dkapp.git
cd dkapp
```

### Step 2: Run the Installation Wizard

```bash
./install.sh
```

Or directly with Python:

```bash
python3 install.py
```

### Step 3: Follow the Prompts

The wizard will ask you for:

1. **Your server URL** - Your public IP or domain name
   - Example: `https://192.168.1.100` or `https://dagknows.example.com`

2. **Database password** - Choose a strong password for PostgreSQL

3. **Admin user details**:
   - Email address
   - First and last name  
   - Password
   - Organization name

4. **Mail settings** (optional) - For sending emails

5. **OpenAI API key** (optional) - For AI features

6. **Encryption password** - To secure your configuration file
   - ⚠️ **Remember this password!** You'll need it for management commands

### Step 4: Wait for Installation

The wizard will:
- Update your system packages
- Install Docker and dependencies
- Configure the application
- Start all services

This takes about 5-10 minutes depending on your internet speed.

### Step 5: Access DagKnows

Once complete, open your browser and navigate to the URL you configured:

```
https://YOUR_SERVER_IP
```

Login with your admin credentials!

## Common Management Tasks

### View Logs

```bash
make logs       # Application logs
make dblogs     # Database logs
```

Press `Ctrl+C` to stop viewing logs.

### Check Status

```bash
make status
```

This will verify:
- Required files are present
- Docker is running
- All containers are up
- Ports are accessible

### Stop Services

```bash
make down
```

### Start Services

```bash
make updb    # Start databases first
make up      # Then start application
```

You'll be prompted for your encryption password.

### Restart Everything

```bash
make restart
```

### Update Configuration

```bash
make reconfigure
```

This lets you change settings without reinstalling.

### View All Commands

```bash
make help
```

## Troubleshooting

### Docker Permission Denied

If you get "permission denied" errors:

**The installation wizard handles this automatically** by:
1. Adding your user to the docker group (if not already added)
2. Detecting the group isn't active in the current session
3. Using `sg docker -c "command"` to run Docker commands with proper group permissions
4. **Never using sudo** - only proper docker group membership

**After installation,** you'll need to activate the docker group for manual commands:

```bash
# Best solution: Activate docker group in your current shell
newgrp docker

# Now you can run commands normally:
make logs
make restart
make status
```

**Alternative: Log out and back in**
The docker group will be active automatically in all new sessions.

**For one-off commands without newgrp:**
```bash
sg docker -c "make logs"
sg docker -c "make status"
```

**Why this happens:**
Group membership changes don't take effect in the current shell session. The installer works around this with `sg docker`, but you need to run `newgrp docker` for your own commands or log out/in for permanent access.

### Services Won't Start

1. Check if Docker is running:
   ```bash
   sudo systemctl status docker
   ```

2. If not, start it:
   ```bash
   sudo systemctl start docker
   ```

3. Check status:
   ```bash
   make status
   ```

### Port Already in Use

If ports 80 or 443 are in use:

1. Find what's using them:
   ```bash
   sudo lsof -i :80
   sudo lsof -i :443
   ```

2. Stop the conflicting service
3. Restart DagKnows

### Containers Keep Restarting

Check the logs for errors:

```bash
make logs
```

Common issues:
- Database not ready yet (wait 30 seconds)
- Wrong database password
- Not enough memory

### Can't Access the Web Interface

1. Check if nginx is running:
   ```bash
   docker ps | grep nginx
   ```

2. Check firewall:
   ```bash
   sudo ufw status
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```

3. Verify your URL in .env is correct:
   ```bash
   make reconfigure
   ```

### Forgot Encryption Password

Unfortunately, you'll need to reconfigure:

1. Stop services: `make down`
2. Remove encrypted file: `rm .env.gpg`
3. Run wizard again: `./install.sh`

## Advanced Topics

### Backup Your Data

```bash
make backups
```

This creates a timestamped backup in `.backups/` directory.

### Update to Latest Version

```bash
make update
```

This will:
1. Stop services
2. Pull latest Docker images
3. Rebuild

Then restart with: `make updb up logs`

### Manual Installation

See [README.md](README.md) for manual installation steps.

## Next Steps

Once you're up and running:

1. **Configure email** - So users can receive notifications
2. **Add OpenAI key** - To enable AI features
3. **Set up backups** - Run `make backups` regularly
4. **Set up monitoring** - Check logs regularly

## Getting Help

- **Documentation**: https://docs.dagknows.com
- **Issues**: https://github.com/dagknows/dkapp/issues
- **Community**: Join our Discord/Slack

## Security Notes

⚠️ **Important Security Practices**:

1. Use strong passwords for all accounts
2. Keep your encryption password safe
3. Regularly update with `make update`
4. Keep backups in a secure location
5. Limit access to port 22 (SSH)
6. Use a firewall

## File Structure

```
dkapp/
├── install.py              # Installation wizard
├── install.sh              # Shell wrapper
├── reconfigure.py          # Configuration updater
├── check-status.py         # Status checker
├── Makefile               # Management commands
├── docker-compose.yml     # App services
├── db-docker-compose.yml  # Database services
├── nginx.conf             # Web server config
├── .env.gpg              # Encrypted configuration
├── postgres-data/        # PostgreSQL data
├── esdata1/             # Elasticsearch data
└── elastic_backup/      # ES backups
```

## Support

If you run into issues:

1. Run `make status` to diagnose
2. Check `make logs` for errors
3. Review this guide
4. Search existing issues on GitHub
5. Open a new issue with logs

---

**Happy DagKnows-ing! 🚀**

