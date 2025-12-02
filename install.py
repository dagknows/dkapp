#!/usr/bin/env python3
"""
DagKnows Installation Wizard
Automates the installation process for DagKnows on docker-compose setups
"""

import os
import sys
import subprocess
import shutil
import getpass
import re
import time
from pathlib import Path

# ANSI color codes for better UX
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text:^60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}\n")

def print_success(text):
    print(f"{Colors.OKGREEN}✓ {text}{Colors.ENDC}")

def print_error(text):
    print(f"{Colors.FAIL}✗ {text}{Colors.ENDC}")

def print_warning(text):
    print(f"{Colors.WARNING}⚠ {text}{Colors.ENDC}")

def print_info(text):
    print(f"{Colors.OKBLUE}ℹ {text}{Colors.ENDC}")

def run_command(cmd, shell=True, check=True, capture_output=False):
    """Run a shell command and return the result"""
    try:
        if capture_output:
            result = subprocess.run(cmd, shell=shell, check=check, 
                                    capture_output=True, text=True)
            return result.stdout.strip()
        else:
            result = subprocess.run(cmd, shell=shell, check=check)
            return result.returncode == 0
    except subprocess.CalledProcessError:
        if check:
            raise
        return False

def check_root():
    """Check if script is running with appropriate privileges"""
    if os.geteuid() == 0:
        print_warning("Running as root. Some commands will be run without sudo.")
        return True
    return False

def check_installation_state():
    """Check the current state of installation to allow resuming"""
    state = {
        'env_configured': os.path.exists('.env.gpg'),
        'env_unencrypted': os.path.exists('.env'),
        'docker_installed': shutil.which('docker') is not None,
        'make_installed': shutil.which('make') is not None,
        'db_running': False,
        'app_running': False
    }
    
    # Check if docker services are running
    if state['docker_installed']:
        # Check database containers
        result = run_command("docker ps --filter name=postgres --filter name=elasticsearch --format '{{.Names}}'", 
                           capture_output=True)
        if result and ('postgres' in result or 'elasticsearch' in result):
            state['db_running'] = True
        
        # Check application containers
        result = run_command("docker ps --filter name=nginx --filter name=req-router --format '{{.Names}}'", 
                           capture_output=True)
        if result and ('nginx' in result or 'req-router' in result):
            state['app_running'] = True
    
    return state

def check_os():
    """Check if the OS is supported"""
    print_info("Checking operating system...")
    
    try:
        with open('/etc/os-release', 'r') as f:
            os_info = f.read().lower()
            if 'ubuntu' in os_info or 'debian' in os_info:
                print_success("Supported Linux distribution detected")
                return True
    except FileNotFoundError:
        pass
    
    print_warning("This script is optimized for Ubuntu/Debian. Proceeding anyway...")
    return True

def check_internet():
    """Check internet connectivity"""
    print_info("Checking internet connectivity...")
    if run_command("ping -c 1 google.com > /dev/null 2>&1", check=False):
        print_success("Internet connection verified")
        return True
    else:
        print_error("No internet connection detected")
        return False

def update_system(skip_if_recent=True):
    """Update system packages"""
    print_header("Updating System Packages")
    
    # Check if we updated recently (within last hour)
    if skip_if_recent and os.path.exists('/var/lib/apt/periodic/update-success-stamp'):
        try:
            stamp_time = os.path.getmtime('/var/lib/apt/periodic/update-success-stamp')
            if time.time() - stamp_time < 3600:  # Less than 1 hour ago
                print_success("System packages recently updated (skipping)")
                return True
        except (OSError, IOError):
            pass
    
    print_info("Running apt update...")
    if not run_command("sudo apt update", check=False):
        print_error("Failed to run apt update")
        return False
    
    print_info("Running apt upgrade... (This may take a while)")
    if not run_command("sudo apt upgrade -y", check=False):
        print_warning("apt upgrade had issues, but continuing...")
    
    print_success("System packages updated")
    return True

def install_make():
    """Install make if not present"""
    print_header("Checking Make Installation")
    
    if shutil.which('make'):
        print_success("make is already installed")
        return True
    
    print_info("Installing make...")
    if run_command("sudo apt-get install -y make", check=False):
        print_success("make installed successfully")
        return True
    else:
        print_error("Failed to install make")
        return False

def run_make_prepare():
    """Run make prepare to install Docker and dependencies"""
    print_header("Preparing Docker Environment")
    
    # Check if Docker is already installed
    if shutil.which('docker') and shutil.which('docker-compose'):
        print_success("Docker and docker-compose already installed")
        
        # Still need to ensure user is in docker group
        username = os.environ.get('USER', run_command("whoami", capture_output=True))
        groups_output = run_command("groups", capture_output=True)
        if 'docker' not in groups_output:
            print_info("Adding user to docker group...")
            run_command(f"sudo usermod -aG docker {username}", check=False)
            print_success("User added to docker group")
        
        return True
    
    print_info("Running 'make prepare'... (This may take several minutes)")
    
    # Check if .env.default exists, if not create it
    if not os.path.exists('.env.default'):
        print_info("Creating .env.default file...")
        create_env_default()
    
    if run_command("make prepare", check=False):
        print_success("Docker environment prepared successfully")
        return True
    else:
        print_error("Failed to prepare Docker environment")
        return False

def restart_docker():
    """Restart Docker service"""
    print_header("Ensuring Docker Service is Running")
    
    # Check if Docker is already running
    if run_command("docker ps > /dev/null 2>&1", check=False):
        print_success("Docker is already running")
        return True
    
    print_info("Starting Docker service...")
    if run_command("sudo systemctl start docker", check=False):
        time.sleep(3)  # Give Docker a moment to fully start
        print_success("Docker started successfully")
        return True
    else:
        print_error("Failed to start Docker")
        return False

def create_env_default():
    """Create a default .env.default file with placeholders"""
    default_env = """# DagKnows Configuration File
# Please fill in all required values

# Application Configuration
APP_SECRET_KEY=your_secret_key_here_change_this
DAGKNOWS_URL=https://YOUR_PUBLIC_IP_OR_DOMAIN
DAGKNOWS_WSFE_URL=http://wsfe:4446
DAGKNOWS_ELASTIC_URL=http://elasticsearch:9200
DAGKNOWS_FORCE_TOKEN=

# Database Configuration
POSTGRESQL_DB_HOST=postgres
POSTGRESQL_DB_PORT=5432
POSTGRESQL_DB_NAME=postgres
POSTGRESQL_DB_USER=postgres
POSTGRESQL_DB_PASSWORD=CHANGEME

# Super User Configuration
SUPER_USER=admin@example.com
SUPER_USER_FIRSTNAME=Admin
SUPER_USER_LASTNAME=User
SUPER_PASSWORD=CHANGEME
SUPER_USER_ORG=default_org
DEFAULT_ORG=default_org

# Mail Configuration
MAIL_DEFAULT_SENDER=info@dagknows.com
MAIL_USERNAME=
MAIL_SERVER=
MAIL_PASSWORD=

# OpenAI Configuration
OPENAI_API_KEY=
OPENAI_ORG_ID=

# Optional Configuration
COMMUNITY_URL=
COMMUNITY=
NO_SSL=false
ENFORCE_LOGIN=true
ENFORCE_SECURE_COOKIE=true
SUPPORT_AD_AUTHENTICATION=false
VERBOSE=false
CUSTOMER_AD_EMAIL_ATTR=
CUSTOMER_AD_SEARCH_BASE_OU=
CUSTOMER_AD_SERVER_URI=
CUSTOMER_AD_SERVICE_PASSWORD=
CUSTOMER_AD_SERVICE_USERNAME=
CUSTOMER_AD_USERNAME_ATTR=
CUSTOMER_AD_USE_TLS=
DEFAULT_PAGE_SIZE=20
ENABLE_WEBSOCKETS=true
DOWNLOAD_TASK_ID=
NITRO_PRESET=node-server
NUXT_PUBLIC_GTAG_ID=
api_key=
"""
    with open('.env.default', 'w') as f:
        f.write(default_env)

def prompt_for_value(prompt, default="", required=True, is_password=False):
    """Prompt user for a value with optional default"""
    if default:
        display_prompt = f"{prompt} [{default}]: "
    else:
        display_prompt = f"{prompt}: "
    
    if is_password:
        value = getpass.getpass(display_prompt)
    else:
        value = input(display_prompt).strip()
    
    if not value and default:
        return default
    
    if required and not value:
        print_error("This field is required!")
        return prompt_for_value(prompt, default, required, is_password)
    
    return value if value else default

def get_public_ip():
    """Try to get the public IP address"""
    try:
        ip = run_command("curl -s ifconfig.me", capture_output=True)
        return ip if ip else ""
    except (subprocess.CalledProcessError, Exception):
        return ""

def validate_email(email):
    """Basic email validation"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def configure_env(resume=False):
    """Interactive configuration of .env file"""
    print_header("Environment Configuration")
    
    if resume:
        print_warning("Existing configuration detected.")
        response = input(f"{Colors.BOLD}Do you want to reconfigure? (yes/no) [no]: {Colors.ENDC}").strip().lower()
        if response not in ['yes', 'y']:
            print_info("Keeping existing configuration")
            return True
        
        # Backup existing config
        if os.path.exists('.env.gpg'):
            backup_name = f'.env.gpg.backup.{int(time.time())}'
            shutil.copy('.env.gpg', backup_name)
            print_info(f"Backed up existing config to {backup_name}")
    
    print_info("Please provide the following configuration values.")
    print_info("Press Enter to keep default values (shown in brackets).\n")
    
    config = {}
    
    # Get public IP
    public_ip = get_public_ip()
    if public_ip:
        print_info(f"Detected public IP: {public_ip}")
    
    # Required Configuration
    print(f"\n{Colors.BOLD}1. Application URL Configuration{Colors.ENDC}")
    default_url = f"https://{public_ip}" if public_ip else "https://YOUR_IP_HERE"
    config['DAGKNOWS_URL'] = prompt_for_value("DagKnows URL (e.g., https://your-domain.com)", 
                                               default_url, required=True)
    
    print(f"\n{Colors.BOLD}2. Database Configuration{Colors.ENDC}")
    config['POSTGRESQL_DB_PASSWORD'] = prompt_for_value("PostgreSQL Database Password", 
                                                         required=True, is_password=True)
    
    print(f"\n{Colors.BOLD}3. Super User Configuration{Colors.ENDC}")
    while True:
        config['SUPER_USER'] = prompt_for_value("Super User Email", 
                                                 "admin@example.com", required=True)
        if validate_email(config['SUPER_USER']):
            break
        print_error("Please enter a valid email address")
    
    config['SUPER_USER_FIRSTNAME'] = prompt_for_value("Super User First Name", 
                                                       "Admin", required=True)
    config['SUPER_USER_LASTNAME'] = prompt_for_value("Super User Last Name", 
                                                      "User", required=True)
    
    print()
    print(f"{Colors.WARNING}{Colors.BOLD}⚠ IMPORTANT:{Colors.ENDC}")
    print(f"{Colors.WARNING}Use the SAME password for both Super User and encryption.{Colors.ENDC}")
    print(f"{Colors.WARNING}This simplifies password management.{Colors.ENDC}")
    print()
    
    config['SUPER_PASSWORD'] = prompt_for_value("Super User Password (will also be used for encryption)", 
                                                 required=True, is_password=True)
    
    # Confirm password
    password_confirm = getpass.getpass("Confirm Super User Password: ")
    if password_confirm != config['SUPER_PASSWORD']:
        print_error("Passwords do not match!")
        return configure_env()
    
    config['SUPER_USER_ORG'] = prompt_for_value("Super User Organization", 
                                                 "default_org", required=True)
    config['DEFAULT_ORG'] = config['SUPER_USER_ORG']  # Make it the same
    
    print(f"\n{Colors.BOLD}4. Mail Configuration{Colors.ENDC}")
    print_info("Leave blank if you don't want to configure email now")
    config['MAIL_DEFAULT_SENDER'] = prompt_for_value("Mail Default Sender", 
                                                       "info@dagknows.com", required=False)
    config['MAIL_USERNAME'] = prompt_for_value("Mail Username", required=False)
    config['MAIL_SERVER'] = prompt_for_value("Mail Server (e.g., smtp.gmail.com)", required=False)
    config['MAIL_PASSWORD'] = prompt_for_value("Mail Password", required=False, is_password=True)
    
    print(f"\n{Colors.BOLD}5. OpenAI Configuration{Colors.ENDC}")
    print_info("Leave blank if you don't want to configure OpenAI now")
    config['OPENAI_API_KEY'] = prompt_for_value("OpenAI API Key", required=False, is_password=True)
    config['OPENAI_ORG_ID'] = prompt_for_value("OpenAI Organization ID", required=False)
    
    # Create the .env file
    return create_env_file(config)

def create_env_file(config):
    """Create .env file from configuration"""
    print_info("\nCreating .env file...")
    
    # Base configuration that doesn't need user input
    base_config = {
        'APP_SECRET_KEY': 'your_secret_key_here_change_this',
        'DAGKNOWS_WSFE_URL': 'http://wsfe:4446',
        'DAGKNOWS_ELASTIC_URL': 'http://elasticsearch:9200',
        'DAGKNOWS_FORCE_TOKEN': '',
        'POSTGRESQL_DB_HOST': 'postgres',
        'POSTGRESQL_DB_PORT': '5432',
        'POSTGRESQL_DB_NAME': 'postgres',
        'POSTGRESQL_DB_USER': 'postgres',
        'COMMUNITY_URL': '',
        'COMMUNITY': '',
        'NO_SSL': 'false',
        'ENFORCE_LOGIN': 'true',
        'ENFORCE_SECURE_COOKIE': 'true',
        'SUPPORT_AD_AUTHENTICATION': 'false',
        'VERBOSE': 'false',
        'CUSTOMER_AD_EMAIL_ATTR': '',
        'CUSTOMER_AD_SEARCH_BASE_OU': '',
        'CUSTOMER_AD_SERVER_URI': '',
        'CUSTOMER_AD_SERVICE_PASSWORD': '',
        'CUSTOMER_AD_SERVICE_USERNAME': '',
        'CUSTOMER_AD_USERNAME_ATTR': '',
        'CUSTOMER_AD_USE_TLS': '',
        'DEFAULT_PAGE_SIZE': '20',
        'ENABLE_WEBSOCKETS': 'true',
        'DOWNLOAD_TASK_ID': '',
        'NITRO_PRESET': 'node-server',
        'NUXT_PUBLIC_GTAG_ID': '',
        'api_key': '',
    }
    
    # Merge with user config
    base_config.update(config)
    
    # Write to .env file
    env_content = "# DagKnows Configuration File\n"
    env_content += "# Generated by DagKnows Installation Wizard\n\n"
    
    for key, value in base_config.items():
        env_content += f"{key}={value}\n"
    
    with open('.env', 'w') as f:
        f.write(env_content)
    
    print_success(".env file created successfully")
    return True

def run_make_encrypt():
    """Run make encrypt with password prompt"""
    print_header("Encrypting Configuration")
    
    print_info("Your .env file will now be encrypted using GPG.")
    print()
    print(f"{Colors.WARNING}{Colors.BOLD}⚠ USE THE SAME PASSWORD as your Super User password{Colors.ENDC}")
    print(f"{Colors.WARNING}This keeps password management simple and consistent.{Colors.ENDC}")
    print()
    print_warning("Remember this password! You'll need it for 'make updb' and 'make up' commands.\n")
    
    # Run make encrypt (this will prompt for password interactively)
    if run_command("make encrypt", check=False):
        print_success("Configuration encrypted successfully")
        return True
    else:
        print_error("Failed to encrypt configuration")
        return False

def setup_docker_group():
    """Ensure user is in docker group and determine if sg docker is needed"""
    print_header("Docker Group Configuration")
    
    username = os.environ.get('USER', run_command("whoami", capture_output=True))
    print_info(f"Ensuring user '{username}' is in docker group...")
    
    # Check if user is in docker group
    groups_output = run_command("groups", capture_output=True)
    if 'docker' not in groups_output:
        print_info("Adding user to docker group...")
        if run_command(f"sudo usermod -aG docker {username}", check=False):
            print_success(f"User '{username}' added to docker group")
        else:
            print_error("Failed to add user to docker group")
            print_error("Please run: sudo usermod -aG docker $USER")
            sys.exit(1)
    else:
        print_success(f"User '{username}' is in docker group")
    
    # Check if we can run docker without sg (group active in current session)
    can_run_docker = run_command("docker ps > /dev/null 2>&1", check=False)
    
    if can_run_docker:
        print_success("Docker group is active in current session")
        return False  # No sg needed
    
    print_info("Docker group not active in current session")
    print_info("Will use 'sg docker' to run Docker commands with group permissions")
    print_warning("After installation, run 'newgrp docker' or logout/login for permanent access")
    
    return True  # sg docker needed

def run_make_updb(use_sg=False):
    """Run make updb to start database services"""
    print_header("Starting Database Services")
    
    print_info("Running 'make updb'...")
    print_info("This will start PostgreSQL and Elasticsearch containers.")
    print_warning("This command may prompt for your encryption password.")
    
    # Use sg docker if needed to run with docker group privileges
    if use_sg:
        cmd = "sg docker -c 'make updb'"
    else:
        cmd = "make updb"
    
    # Run in a way that allows interactive password input
    try:
        # Start updb
        subprocess.run(cmd, shell=True, check=True)
        print_success("Database services started")
        
        print_info("\nStarting database logs...")
        print_info("Press Ctrl+C to stop viewing logs and continue installation\n")
        time.sleep(2)
        
        # Show logs for a bit, then continue
        try:
            if use_sg:
                subprocess.run("timeout 10 sg docker -c 'make dblogs'", shell=True, check=False)
            else:
                subprocess.run("timeout 10 make dblogs", shell=True, check=False)
        except KeyboardInterrupt:
            print_info("\nLogs interrupted by user")
        
        return True
    except subprocess.CalledProcessError:
        print_error("Failed to start database services")
        print_error("Please ensure:")
        print_error("  1. Docker service is running: sudo systemctl status docker")
        print_error("  2. User is in docker group: groups | grep docker")
        print_error(f"  3. Try manually: {cmd}")
        return False
    except KeyboardInterrupt:
        print_info("\nCommand interrupted by user")
        return False

def run_make_pull(use_sg=False):
    """Pull Docker images from public ECR"""
    print_header("Pulling Docker Images")
    
    # Check if all required images are already present
    # These match the images in Makefile's pull target
    images_needed = [
        'public.ecr.aws/n5k3t9x2/wsfe:latest',
        'public.ecr.aws/n5k3t9x2/ansi_processing:latest',
        'public.ecr.aws/n5k3t9x2/jobsched:latest',
        'public.ecr.aws/n5k3t9x2/apigateway:latest',
        'public.ecr.aws/n5k3t9x2/conv_mgr:latest',
        'public.ecr.aws/n5k3t9x2/settings:latest',
        'public.ecr.aws/n5k3t9x2/taskservice:latest',
        'public.ecr.aws/n5k3t9x2/req_router:latest',
        'public.ecr.aws/n5k3t9x2/dagknows_nuxt:latest',
    ]
    
    images_present = 0
    for image in images_needed:
        if run_command(f"docker images -q {image} 2>/dev/null", capture_output=True, check=False):
            images_present += 1
    
    if images_present == len(images_needed):
        print_success(f"All {len(images_needed)} Docker images already present (skipping pull)")
        return True
    elif images_present > 0:
        print_info(f"Found {images_present}/{len(images_needed)} images, pulling remaining...")
    
    print_info("Pulling Docker images from public ECR...")
    print_info("This downloads images one by one to avoid concurrent request limits.")
    print_info("This may take several minutes depending on your internet speed...")
    
    # Use sg docker if needed
    if use_sg:
        cmd = "sg docker -c 'make pull'"
    else:
        cmd = "make pull"
    
    try:
        subprocess.run(cmd, shell=True, check=True)
        print_success("Docker images pulled successfully")
        return True
    except subprocess.CalledProcessError:
        print_error("Failed to pull Docker images")
        print_warning("Continuing anyway - images will be pulled during 'make up'")
        return True  # Don't fail installation, just warn
    except KeyboardInterrupt:
        print_info("\nImage pull interrupted by user")
        print_warning("Continuing anyway - images will be pulled during 'make up'")
        return True

def run_make_up(use_sg=False):
    """Run make up to start application services"""
    print_header("Starting Application Services")
    
    print_info("Running 'make up'...")
    print_info("This will start all DagKnows application containers.")
    print_warning("This command may prompt for your encryption password.")
    
    # Use sg docker if needed to run with docker group privileges
    if use_sg:
        cmd = "sg docker -c 'make up'"
    else:
        cmd = "make up"
    
    try:
        # Start services
        subprocess.run(cmd, shell=True, check=True)
        print_success("Application services started")
        
        print_info("\nStarting application logs...")
        print_info("Press Ctrl+C to stop viewing logs\n")
        time.sleep(2)
        
        # Show logs
        try:
            if use_sg:
                subprocess.run("sg docker -c 'make logs'", shell=True, check=False)
            else:
                subprocess.run("make logs", shell=True, check=False)
        except KeyboardInterrupt:
            print_info("\nLogs stopped by user")
        
        return True
    except subprocess.CalledProcessError:
        print_error("Failed to start application services")
        print_error("Please ensure:")
        print_error("  1. Database services are running: make dblogs")
        print_error("  2. Docker service is running: sudo systemctl status docker")
        print_error("  3. User is in docker group: groups | grep docker")
        print_error(f"  4. Try manually: {cmd}")
        return False
    except KeyboardInterrupt:
        print_info("\nCommand interrupted by user")
        return False

def print_final_message(dagknows_url, used_sg=False):
    """Print final success message with access instructions"""
    print_header("Installation Complete!")
    
    print_success("DagKnows has been successfully installed!")
    print()
    print(f"{Colors.BOLD}Access your DagKnows instance at:{Colors.ENDC}")
    print(f"{Colors.OKCYAN}{Colors.BOLD}  {dagknows_url}{Colors.ENDC}")
    print()
    
    if used_sg:
        print(f"{Colors.WARNING}{Colors.BOLD}⚠ IMPORTANT - Docker Group Activation:{Colors.ENDC}")
        print(f"{Colors.WARNING}The installation used 'sg docker' to run Docker commands.{Colors.ENDC}")
        print(f"{Colors.WARNING}To run commands manually, you need to activate the docker group:{Colors.ENDC}")
        print()
        print(f"{Colors.BOLD}Option 1 (Recommended): Activate for current session{Colors.ENDC}")
        print(f"  {Colors.OKCYAN}newgrp docker{Colors.ENDC}")
        print("  Then run commands normally: make logs, make restart, etc.")
        print()
        print(f"{Colors.BOLD}Option 2: Log out and back in{Colors.ENDC}")
        print("  The docker group will be active in all new sessions")
        print()
        print(f"{Colors.BOLD}Option 3: Prefix each command{Colors.ENDC}")
        print(f"  {Colors.OKCYAN}sg docker -c 'make logs'{Colors.ENDC}")
        print()
    
    print(f"{Colors.BOLD}Useful commands:{Colors.ENDC}")
    print(f"  {Colors.OKBLUE}make logs{Colors.ENDC}        - View application logs")
    print(f"  {Colors.OKBLUE}make dblogs{Colors.ENDC}      - View database logs")
    print(f"  {Colors.OKBLUE}make down{Colors.ENDC}        - Stop all services")
    print(f"  {Colors.OKBLUE}make up{Colors.ENDC}          - Start application services")
    print(f"  {Colors.OKBLUE}make updb{Colors.ENDC}        - Start database services")
    print(f"  {Colors.OKBLUE}make restart{Colors.ENDC}     - Restart all services")
    print(f"  {Colors.OKBLUE}make status{Colors.ENDC}      - Check system status")
    print()
    print(f"{Colors.WARNING}Note: Some commands will prompt for your encryption password{Colors.ENDC}")
    print()

def main():
    """Main installation workflow"""
    print_header("DagKnows Installation Wizard")
    print(f"{Colors.BOLD}This wizard will guide you through the installation of DagKnows{Colors.ENDC}\n")
    
    # Change to dkapp directory if not already there
    script_dir = Path(__file__).parent.absolute()
    os.chdir(script_dir)
    print_info(f"Working directory: {os.getcwd()}")
    
    # Check current installation state
    state = check_installation_state()
    
    # Handle resume scenarios
    if state['env_configured']:
        print_header("Existing Installation Detected")
        print_success("Found existing encrypted configuration (.env.gpg)")
        
        if state['app_running']:
            print_success("Application services are already running!")
            print()
            print(f"{Colors.BOLD}Your DagKnows installation appears to be complete.{Colors.ENDC}")
            print()
            print("Available actions:")
            print("  1. View logs: make logs")
            print("  2. Restart services: make restart")
            print("  3. Check status: make status")
            print("  4. Reconfigure: make reconfigure")
            print()
            response = input(f"{Colors.BOLD}Do you want to reinstall anyway? (yes/no) [no]: {Colors.ENDC}").strip().lower()
            if response not in ['yes', 'y']:
                print_info("Installation skipped. System is already running.")
                sys.exit(0)
        elif state['db_running']:
            print_success("Database services are running")
            print_info("Application services are not running yet")
            response = input(f"{Colors.BOLD}Resume from starting application services? (yes/no) [yes]: {Colors.ENDC}").strip().lower()
            if response not in ['no', 'n']:
                print_info("Resuming installation from application startup...")
                # Jump to app startup
                try:
                    use_sg = setup_docker_group()
                    if not run_make_pull(use_sg):
                        print_error("Image pull failed")
                        sys.exit(1)
                    if not run_make_up(use_sg):
                        print_error("Application startup failed")
                        sys.exit(1)
                    
                    dagknows_url = "https://your-server"
                    if os.path.exists('.env.gpg'):
                        print_info("To view your DagKnows URL, decrypt your config: gpg -o .env -d .env.gpg")
                    print_final_message(dagknows_url, use_sg)
                    sys.exit(0)
                except Exception as e:
                    print_error(f"Resume failed: {e}")
                    sys.exit(1)
        else:
            print_warning("Services are not running")
            response = input(f"{Colors.BOLD}Resume from starting services? (yes/no) [yes]: {Colors.ENDC}").strip().lower()
            if response not in ['no', 'n']:
                print_info("Resuming installation from service startup...")
                # Jump to service startup
                try:
                    use_sg = setup_docker_group()
                    if not run_make_updb(use_sg):
                        print_error("Database startup failed")
                        sys.exit(1)
                    
                    print_info("\nWaiting for database services to stabilize...")
                    time.sleep(10)
                    
                    if not run_make_pull(use_sg):
                        print_error("Image pull failed")
                        sys.exit(1)
                    
                    if not run_make_up(use_sg):
                        print_error("Application startup failed")
                        sys.exit(1)
                    
                    dagknows_url = "https://your-server"
                    print_final_message(dagknows_url, use_sg)
                    sys.exit(0)
                except Exception as e:
                    print_error(f"Resume failed: {e}")
                    sys.exit(1)
    
    # Check for unencrypted .env file (interrupted before encryption)
    if state['env_unencrypted']:
        print_warning("Found unencrypted .env file from previous run")
        response = input(f"{Colors.BOLD}Do you want to use it? (yes/no) [yes]: {Colors.ENDC}").strip().lower()
        if response in ['no', 'n']:
            os.remove('.env')
            print_info("Removed old .env file")
    
    # Confirmation for fresh install
    print_warning("This script will:")
    print("  1. Update your system packages")
    print("  2. Install required dependencies (make, docker, etc.)")
    print("  3. Configure your DagKnows installation")
    print("  4. Start the application services")
    print()
    
    response = input(f"{Colors.BOLD}Do you want to continue? (yes/no): {Colors.ENDC}").strip().lower()
    if response not in ['yes', 'y']:
        print_info("Installation cancelled by user")
        sys.exit(0)
    
    try:
        # Pre-flight checks
        check_os()
        if not check_internet():
            print_error("Internet connection required for installation")
            sys.exit(1)
        
        # System preparation
        if not update_system():
            print_error("System update failed")
            sys.exit(1)
        
        if not install_make():
            print_error("Make installation failed")
            sys.exit(1)
        
        if not run_make_prepare():
            print_error("Docker preparation failed")
            sys.exit(1)
        
        if not restart_docker():
            print_error("Docker restart failed")
            sys.exit(1)
        
        # Configuration
        if not configure_env(resume=state['env_configured']):
            print_error("Configuration failed")
            sys.exit(1)
        
        # Get DAGKNOWS_URL for final message
        dagknows_url = "https://your-server"
        if os.path.exists('.env'):
            with open('.env', 'r') as f:
                for line in f:
                    if line.startswith('DAGKNOWS_URL='):
                        dagknows_url = line.split('=', 1)[1].strip()
                        break
        
        if not run_make_encrypt():
            print_error("Encryption failed")
            sys.exit(1)
        
        # Check docker group and determine if we need sg/sudo
        use_sg = setup_docker_group()
        
        # Start services
        if not run_make_updb(use_sg):
            print_error("Database startup failed")
            sys.exit(1)
        
        print_info("\nWaiting for database services to stabilize...")
        time.sleep(10)
        
        # Pull images before starting application services
        # This avoids concurrent unauthenticated requests to public ECR
        if not run_make_pull(use_sg):
            print_error("Image pull failed")
            sys.exit(1)
        
        if not run_make_up(use_sg):
            print_error("Application startup failed")
            sys.exit(1)
        
        # Success!
        print_final_message(dagknows_url, use_sg)
        
    except KeyboardInterrupt:
        print_error("\n\nInstallation interrupted by user")
        sys.exit(1)
    except Exception as e:
        print_error(f"\n\nUnexpected error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()

