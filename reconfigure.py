#!/usr/bin/env python3
"""
DagKnows Reconfiguration Tool
Allows updating configuration without full reinstall
"""

import os
import sys
import getpass
import re
from pathlib import Path

# ANSI color codes
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

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

def read_env_file():
    """Read and parse the .env.gpg file"""
    import subprocess
    
    if not os.path.exists('.env.gpg'):
        print_error(".env.gpg file not found. Have you run the installation?")
        return None
    
    print_info("Decrypting current configuration...")
    print_warning("You will need to enter your encryption password:")
    
    try:
        # Decrypt the .env.gpg file
        subprocess.run("gpg -o .env -d .env.gpg", shell=True, check=True)
        
        # Read the decrypted file
        config = {}
        with open('.env', 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key] = value
        
        print_success("Configuration loaded successfully")
        return config
    except subprocess.CalledProcessError:
        print_error("Failed to decrypt .env.gpg. Wrong password?")
        return None
    except Exception as e:
        print_error(f"Error reading configuration: {e}")
        return None
    finally:
        # Clean up decrypted file
        if os.path.exists('.env'):
            os.remove('.env')

def write_env_file(config):
    """Write configuration to .env file"""
    with open('.env', 'w') as f:
        f.write("# DagKnows Configuration File\n")
        f.write("# Updated by DagKnows Reconfiguration Tool\n\n")
        for key, value in config.items():
            f.write(f"{key}={value}\n")
    print_success("Configuration file updated")

def encrypt_env_file():
    """Encrypt the .env file"""
    import subprocess
    
    print_info("\nEncrypting configuration...")
    print_warning("Enter your encryption password (same as before or new):")
    
    try:
        subprocess.run("gpg -c .env", shell=True, check=True)
        os.remove('.env')
        print_success("Configuration encrypted successfully")
        return True
    except subprocess.CalledProcessError:
        print_error("Failed to encrypt configuration")
        return False

def prompt_for_value(prompt, current_value="", required=True, is_password=False):
    """Prompt user for a value with current value shown"""
    if is_password and current_value:
        display_current = "*" * len(current_value)
    else:
        display_current = current_value
    
    if display_current:
        display_prompt = f"{prompt}\n  Current: {display_current}\n  New (or press Enter to keep): "
    else:
        display_prompt = f"{prompt}\n  New value: "
    
    if is_password:
        value = getpass.getpass(display_prompt)
    else:
        value = input(display_prompt).strip()
    
    if not value:
        return current_value
    
    if required and not value and not current_value:
        print_error("This field is required!")
        return prompt_for_value(prompt, current_value, required, is_password)
    
    return value if value else current_value

def reconfigure_section(config, section_name, fields):
    """Reconfigure a section of the configuration"""
    print(f"\n{Colors.BOLD}{section_name}{Colors.ENDC}")
    response = input(f"Update this section? (yes/no) [no]: ").strip().lower()
    
    if response in ['yes', 'y']:
        for field_name, field_config in fields.items():
            is_password = field_config.get('password', False)
            required = field_config.get('required', False)
            description = field_config.get('description', field_name)
            
            current = config.get(field_name, '')
            new_value = prompt_for_value(description, current, required, is_password)
            config[field_name] = new_value
        
        print_success(f"{section_name} updated")
    else:
        print_info(f"{section_name} unchanged")
    
    return config

def main():
    """Main reconfiguration workflow"""
    print_header("DagKnows Reconfiguration Tool")
    
    # Change to script directory
    script_dir = Path(__file__).parent.absolute()
    os.chdir(script_dir)
    
    print_info("This tool allows you to update your DagKnows configuration")
    print_info("without going through the full installation process.\n")
    
    # Read current configuration
    config = read_env_file()
    if config is None:
        sys.exit(1)
    
    print_success(f"Loaded {len(config)} configuration parameters")
    
    # Define sections and fields
    sections = {
        "Application URL": {
            'DAGKNOWS_URL': {'description': 'DagKnows URL', 'required': True}
        },
        "Database Settings": {
            'POSTGRESQL_DB_PASSWORD': {'description': 'PostgreSQL Password', 'password': True, 'required': True}
        },
        "Super User Settings": {
            'SUPER_USER': {'description': 'Super User Email', 'required': True},
            'SUPER_USER_FIRSTNAME': {'description': 'First Name', 'required': True},
            'SUPER_USER_LASTNAME': {'description': 'Last Name', 'required': True},
            'SUPER_PASSWORD': {'description': 'Password', 'password': True, 'required': True},
            'SUPER_USER_ORG': {'description': 'Organization', 'required': True}
        },
        "Mail Configuration": {
            'MAIL_DEFAULT_SENDER': {'description': 'Default Sender'},
            'MAIL_USERNAME': {'description': 'Username'},
            'MAIL_SERVER': {'description': 'SMTP Server'},
            'MAIL_PASSWORD': {'description': 'Password', 'password': True}
        },
        "OpenAI Configuration": {
            'OPENAI_API_KEY': {'description': 'API Key', 'password': True},
            'OPENAI_ORG_ID': {'description': 'Organization ID'}
        }
    }
    
    # Update each section
    for section_name, fields in sections.items():
        config = reconfigure_section(config, section_name, fields)
    
    # Special handling for DEFAULT_ORG to match SUPER_USER_ORG
    if 'SUPER_USER_ORG' in config:
        config['DEFAULT_ORG'] = config['SUPER_USER_ORG']
    
    # Write and encrypt
    print_header("Saving Configuration")
    write_env_file(config)
    
    if not encrypt_env_file():
        print_error("Failed to encrypt configuration")
        sys.exit(1)
    
    print_header("Reconfiguration Complete")
    print_success("Your configuration has been updated!")
    print()
    print_info("To apply the changes, restart your services:")
    print(f"  {Colors.OKBLUE}make restart{Colors.ENDC}")
    print()

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print_error("\n\nReconfiguration cancelled by user")
        # Clean up any decrypted .env file
        if os.path.exists('.env'):
            os.remove('.env')
        sys.exit(1)
    except Exception as e:
        print_error(f"\n\nUnexpected error: {e}")
        # Clean up any decrypted .env file
        if os.path.exists('.env'):
            os.remove('.env')
        import traceback
        traceback.print_exc()
        sys.exit(1)

