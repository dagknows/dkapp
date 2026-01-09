#!/usr/bin/env python3
"""
DagKnows Status Checker
Verifies that the installation is working correctly
"""

import os
import sys
import subprocess
import json
from pathlib import Path

try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False

# ANSI color codes
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text:^60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}\n")

def print_check(name, status, message=""):
    """Print a check result"""
    if status:
        symbol = f"{Colors.OKGREEN}✓{Colors.ENDC}"
        status_text = f"{Colors.OKGREEN}OK{Colors.ENDC}"
    else:
        symbol = f"{Colors.FAIL}✗{Colors.ENDC}"
        status_text = f"{Colors.FAIL}FAILED{Colors.ENDC}"
    
    print(f"{symbol} {name:.<50} {status_text}")
    if message:
        print(f"  {Colors.WARNING}→ {message}{Colors.ENDC}")

def run_command(cmd, capture_output=True):
    """Run a command and return output"""
    try:
        if capture_output:
            result = subprocess.run(cmd, shell=True, capture_output=True, 
                                    text=True, timeout=10)
            return result.returncode == 0, result.stdout.strip()
        else:
            result = subprocess.run(cmd, shell=True, timeout=10)
            return result.returncode == 0, ""
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except Exception as e:
        return False, str(e)

def check_required_files():
    """Check if required files exist"""
    print_header("Required Files Check")
    
    files = {
        'Makefile': 'Makefile for running commands',
        'docker-compose.yml': 'Main application compose file',
        'db-docker-compose.yml': 'Database compose file',
        'nginx.conf': 'Nginx configuration',
        '.env.gpg': 'Encrypted environment file'
    }
    
    all_present = True
    for filename, description in files.items():
        exists = os.path.exists(filename)
        print_check(f"{filename} ({description})", exists, 
                   "" if exists else "File not found")
        if not exists:
            all_present = False
    
    return all_present

def check_docker():
    """Check Docker installation and status"""
    print_header("Docker Check")
    
    # Check if docker is installed
    success, _ = run_command("docker --version")
    print_check("Docker installed", success, 
               "Run: sudo apt-get install docker.io" if not success else "")
    
    if not success:
        return False
    
    # Check if docker is running
    success, _ = run_command("docker ps")
    print_check("Docker running", success,
               "Run: sudo systemctl start docker" if not success else "")
    
    if not success:
        return False
    
    # Check docker-compose
    success, _ = run_command("docker compose version")
    print_check("Docker Compose installed", success,
               "Run: sudo apt-get install docker-compose-v2" if not success else "")
    
    return success

def check_docker_network():
    """Check if required Docker network exists"""
    print_header("Docker Network Check")
    
    success, output = run_command("docker network ls")
    if success:
        has_network = 'saaslocalnetwork' in output
        print_check("saaslocalnetwork exists", has_network,
                   "Run: docker network create saaslocalnetwork" if not has_network else "")
        return has_network
    return False

def check_containers():
    """Check if containers are running"""
    print_header("Container Status Check")
    
    success, output = run_command("docker compose ps --format json")
    if not success:
        print_check("Unable to check containers", False,
                   "Services may not be started. Run: make updb && make up")
        return False
    
    if not output.strip():
        print_check("No containers running", False,
                   "Services not started. Run: make updb && make up")
        return False
    
    # Parse JSON output
    try:
        # Docker compose ps can output multiple JSON objects
        containers = []
        for line in output.strip().split('\n'):
            if line.strip():
                containers.append(json.loads(line))
        
        expected_services = [
            'postgres', 'elasticsearch', 'nginx', 'req-router',
            'taskservice', 'wsfe', 'settings', 'dagknows-nuxt',
            'conv-mgr', 'apigateway', 'ansi-processing', 'jobsched'
        ]
        
        running_services = set()
        for container in containers:
            service = container.get('Service', '')
            state = container.get('State', '')
            running = state == 'running'
            running_services.add(service)
            
            # Check specific service
            if service in expected_services:
                health = container.get('Health', '')
                health_status = f" ({health})" if health else ""
                print_check(f"{service} container", running,
                           f"State: {state}{health_status}")
        
        # Check for missing services
        missing = set(expected_services) - running_services
        if missing:
            print(f"\n{Colors.WARNING}Missing services: {', '.join(missing)}{Colors.ENDC}")
            return False
        
        return True
    except json.JSONDecodeError:
        # Fallback to simple text parsing
        success, output = run_command("docker compose ps")
        print(output)
        return "postgres" in output and "elasticsearch" in output
    except Exception as e:
        print_check("Error parsing container status", False, str(e))
        return False

def check_database_containers():
    """Check database containers specifically"""
    print_header("Database Container Check")
    
    success, output = run_command("docker compose -f db-docker-compose.yml ps --format json")
    if not success or not output.strip():
        print_check("Database containers", False,
                   "Run: make updb")
        return False
    
    try:
        containers = []
        for line in output.strip().split('\n'):
            if line.strip():
                containers.append(json.loads(line))
        
        postgres_ok = False
        elastic_ok = False
        
        for container in containers:
            service = container.get('Service', '')
            state = container.get('State', '')
            running = state == 'running'
            
            if service == 'postgres':
                postgres_ok = running
                health = container.get('Health', '')
                print_check(f"PostgreSQL ({health})", running)
            elif service == 'elasticsearch':
                elastic_ok = running
                print_check("Elasticsearch", running)
        
        return postgres_ok and elastic_ok
    except:
        # Fallback
        return "postgres" in output and "elasticsearch" in output

def check_ports():
    """Check if required ports are accessible"""
    print_header("Port Accessibility Check")
    
    ports = {
        80: "HTTP",
        443: "HTTPS",
    }
    
    all_ok = True
    for port, description in ports.items():
        success, _ = run_command(f"nc -z localhost {port}")
        print_check(f"Port {port} ({description})", success,
                   "Port not accessible" if not success else "")
        if not success:
            all_ok = False
    
    return all_ok

def check_data_directories():
    """Check if data directories exist and have correct permissions"""
    print_header("Data Directories Check")

    dirs = ['postgres-data', 'esdata1', 'elastic_backup']
    all_ok = True

    for dirname in dirs:
        exists = os.path.exists(dirname) and os.path.isdir(dirname)
        print_check(f"{dirname}", exists,
                   "Run: make dbdirs" if not exists else "")
        if not exists:
            all_ok = False

    return all_ok


def check_versions():
    """Check and display installed component versions"""
    print_header("Installed Versions")

    manifest_file = 'version-manifest.yaml'

    # Check if version tracking is enabled
    if not os.path.exists(manifest_file):
        print(f"  {Colors.WARNING}Version tracking not enabled{Colors.ENDC}")
        print(f"  Run: make migrate-versions")
        print()

        # Try to detect versions from running containers
        print("  Detecting from running containers...")
        success, output = run_command("docker compose ps --format json")
        if success and output.strip():
            try:
                for line in output.strip().split('\n'):
                    if not line.strip():
                        continue
                    container = json.loads(line)
                    service = container.get('Service', '')
                    container_id = container.get('ID', '')

                    if container_id:
                        # Get image from docker inspect
                        img_success, img_output = run_command(f"docker inspect --format='{{{{.Config.Image}}}}' {container_id}")
                        if img_success:
                            image = img_output.strip()
                            # Extract tag
                            tag = 'latest'
                            if ':' in image:
                                tag = image.rsplit(':', 1)[1]
                            print(f"  {service:.<40} {tag}")
            except json.JSONDecodeError:
                print(f"  {Colors.WARNING}Could not detect versions{Colors.ENDC}")
        return False

    # Read manifest
    if YAML_AVAILABLE:
        try:
            with open(manifest_file, 'r') as f:
                manifest = yaml.safe_load(f)

            services = manifest.get('services', {})
            overrides = manifest.get('custom_overrides', {})

            for name, info in services.items():
                tag = info.get('current_tag', 'unknown')
                deployed = info.get('deployed_at', '')[:10] if info.get('deployed_at') else ''

                # Check for override
                override = overrides.get(name, {})
                if override.get('tag'):
                    tag = override['tag']
                    print(f"  {Colors.OKGREEN}\u2713{Colors.ENDC} {name:.<40} {tag:<15} {Colors.WARNING}[custom]{Colors.ENDC}")
                else:
                    print(f"  {Colors.OKGREEN}\u2713{Colors.ENDC} {name:.<40} {tag:<15} ({deployed})")

            print()
            return True
        except Exception as e:
            print(f"  {Colors.FAIL}Error reading manifest: {e}{Colors.ENDC}")
            return False
    else:
        # Fallback: just check manifest exists
        print(f"  {Colors.WARNING}YAML module not available - install with: pip install pyyaml{Colors.ENDC}")
        print(f"  Run 'make version' for detailed version information")
        return True

def get_dagknows_url():
    """Try to get the DagKnows URL from config"""
    try:
        # Try to decrypt and read .env.gpg temporarily
        result = subprocess.run("gpg -o .env.tmp -d .env.gpg",
                              shell=True, capture_output=True,
                              stdin=subprocess.PIPE, timeout=1)
        
        if os.path.exists('.env.tmp'):
            with open('.env.tmp', 'r') as f:
                for line in f:
                    if line.startswith('DAGKNOWS_URL='):
                        url = line.split('=', 1)[1].strip()
                        os.remove('.env.tmp')
                        return url
            os.remove('.env.tmp')
    except:
        pass
    
    return None

def print_summary(checks_passed):
    """Print final summary"""
    print_header("Summary")
    
    total = len(checks_passed)
    passed = sum(checks_passed.values())
    
    if passed == total:
        print(f"{Colors.OKGREEN}{Colors.BOLD}All checks passed! ✓{Colors.ENDC}")
        print(f"\n{Colors.OKGREEN}Your DagKnows installation appears to be working correctly.{Colors.ENDC}\n")
        
        dagknows_url = get_dagknows_url()
        if dagknows_url:
            print(f"Access your instance at: {Colors.BOLD}{dagknows_url}{Colors.ENDC}")
    else:
        print(f"{Colors.WARNING}Checks: {passed}/{total} passed{Colors.ENDC}\n")
        print(f"{Colors.FAIL}Some issues were detected. Please review the output above.{Colors.ENDC}\n")
        
        print(f"{Colors.BOLD}Common fixes:{Colors.ENDC}")
        if not checks_passed.get('docker'):
            print("  - Install/start Docker: sudo systemctl start docker")
        if not checks_passed.get('files'):
            print("  - Run the installation wizard: ./install.sh")
        if not checks_passed.get('db_containers'):
            print("  - Start database services: make updb")
        if not checks_passed.get('containers'):
            print("  - Start application services: make up")
        print()

def main():
    """Main status check workflow"""
    print_header("DagKnows Status Check")
    print(f"{Colors.BOLD}Checking DagKnows installation status...{Colors.ENDC}\n")
    
    # Change to script directory
    script_dir = Path(__file__).parent.absolute()
    os.chdir(script_dir)
    
    # Run all checks
    checks = {}
    
    checks['files'] = check_required_files()
    checks['docker'] = check_docker()
    
    if checks['docker']:
        checks['network'] = check_docker_network()
        checks['data_dirs'] = check_data_directories()
        checks['db_containers'] = check_database_containers()
        checks['containers'] = check_containers()
        checks['ports'] = check_ports()
        checks['versions'] = check_versions()
    
    # Print summary
    print_summary(checks)
    
    # Return exit code based on results
    sys.exit(0 if all(checks.values()) else 1)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Status check interrupted{Colors.ENDC}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.FAIL}Error during status check: {e}{Colors.ENDC}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

