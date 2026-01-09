#!/usr/bin/env python3
"""
DagKnows Migration Script
Converts existing dkapp deployments to use version tracking.

This interactive wizard will:
1. Detect currently running container versions
2. Create a version-manifest.yaml from current state
3. Generate versions.env for docker-compose
4. Verify the configuration works

Usage:
    python3 migrate-to-versioned.py
"""

import json
import os
import re
import shutil
import subprocess
import sys
import yaml
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Tuple


# ============================================
# CONSTANTS
# ============================================

SERVICES = [
    'req_router',
    'taskservice',
    'settings',
    'conv_mgr',
    'wsfe',
    'jobsched',
    'apigateway',
    'ansi_processing',
    'dagknows_nuxt'
]

# Map docker-compose service names to manifest service names
COMPOSE_TO_SERVICE = {
    'req-router': 'req_router',
    'taskservice': 'taskservice',
    'settings': 'settings',
    'conv-mgr': 'conv_mgr',
    'wsfe': 'wsfe',
    'jobsched': 'jobsched',
    'apigateway': 'apigateway',
    'ansi-processing': 'ansi_processing',
    'dagknows-nuxt': 'dagknows_nuxt'
}

DEFAULT_REGISTRY = 'public.ecr.aws/n5k3t9x2'


# ============================================
# COLORS AND OUTPUT
# ============================================

class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'


def print_header(text: str):
    """Print a formatted header"""
    print(f"\n{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{text:^60}{Colors.ENDC}")
    print(f"{Colors.HEADER}{Colors.BOLD}{'='*60}{Colors.ENDC}\n")


def print_step(text: str):
    """Print a step indicator"""
    print(f"\n{Colors.OKBLUE}{Colors.BOLD}>>> {text}{Colors.ENDC}")


def print_success(text: str):
    """Print success message"""
    print(f"{Colors.OKGREEN}\u2713 {text}{Colors.ENDC}")


def print_error(text: str):
    """Print error message"""
    print(f"{Colors.FAIL}\u2717 {text}{Colors.ENDC}")


def print_warning(text: str):
    """Print warning message"""
    print(f"{Colors.WARNING}\u26a0 {text}{Colors.ENDC}")


def print_info(text: str):
    """Print info message"""
    print(f"{Colors.OKBLUE}\u2139 {text}{Colors.ENDC}")


# ============================================
# UTILITIES
# ============================================

def run_command(cmd: str, capture: bool = True, timeout: int = 60) -> Tuple[bool, str]:
    """Run a shell command and return success status and output"""
    try:
        if capture:
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=timeout
            )
            return result.returncode == 0, result.stdout.strip()
        else:
            result = subprocess.run(cmd, shell=True, timeout=timeout)
            return result.returncode == 0, ""
    except subprocess.TimeoutExpired:
        return False, "Command timed out"
    except Exception as e:
        return False, str(e)


def confirm(prompt: str, default: bool = False) -> bool:
    """Ask for user confirmation"""
    suffix = " (yes/no) [no]: " if not default else " (yes/no) [yes]: "
    try:
        response = input(prompt + suffix).strip().lower()
        if not response:
            return default
        return response in ('yes', 'y')
    except (EOFError, KeyboardInterrupt):
        print()
        return False


def backup_file(filepath: str) -> Optional[str]:
    """Create a timestamped backup of a file"""
    if os.path.exists(filepath):
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        backup_path = f"{filepath}.backup.{timestamp}"
        shutil.copy(filepath, backup_path)
        return backup_path
    return None


def restore_backup(filepath: str, backup_path: str):
    """Restore a file from backup"""
    if os.path.exists(backup_path):
        shutil.copy(backup_path, filepath)


# ============================================
# MIGRATION FUNCTIONS
# ============================================

def get_running_images() -> Dict:
    """Get currently running container images and their versions"""
    images = {}

    # Try docker compose ps with JSON format
    success, output = run_command("docker compose ps --format json")
    if not success or not output.strip():
        return images

    try:
        for line in output.strip().split('\n'):
            if not line.strip():
                continue
            container = json.loads(line)
            compose_service = container.get('Service', '')

            if compose_service not in COMPOSE_TO_SERVICE:
                continue

            service_name = COMPOSE_TO_SERVICE[compose_service]
            container_id = container.get('ID', '')

            if not container_id:
                continue

            # Get image info from docker inspect
            success, inspect_output = run_command(f"docker inspect {container_id}")
            if success:
                inspect_data = json.loads(inspect_output)
                if inspect_data:
                    image = inspect_data[0].get('Config', {}).get('Image', '')
                    digest = inspect_data[0].get('Image', '')

                    # Parse image:tag
                    tag = 'latest'
                    image_name = image
                    if ':' in image:
                        parts = image.rsplit(':', 1)
                        image_name = parts[0]
                        tag = parts[1]

                    images[service_name] = {
                        'image': image_name,
                        'tag': tag,
                        'digest': digest,
                        'container_id': container_id
                    }
    except json.JSONDecodeError:
        pass

    return images


def show_current_state(images: Dict):
    """Display detected images"""
    print("\nDetected running containers:\n")

    for service in SERVICES:
        info = images.get(service, {})
        if info:
            tag = info.get('tag', 'unknown')
            print(f"  {Colors.OKGREEN}\u2713{Colors.ENDC} {service:.<40} {tag}")
        else:
            print(f"  {Colors.WARNING}?{Colors.ENDC} {service:.<40} (not running)")


def create_manifest_from_current(images: Dict, customer_id: str = '', deployment_id: str = '') -> Dict:
    """Create a version manifest from current running images"""
    now = datetime.now().isoformat()

    manifest = {
        'schema_version': '1.0',
        'deployment_id': deployment_id or f'dkapp-{datetime.now().strftime("%Y%m%d")}',
        'customer_id': customer_id,
        'ecr': {
            'registry': 'public.ecr.aws',
            'repository_alias': 'n5k3t9x2',
            'use_private': False,
            'private_registry': '',
            'private_region': 'us-east-1'
        },
        'services': {},
        'history': {},
        'custom_overrides': {}
    }

    for service in SERVICES:
        info = images.get(service, {})
        tag = info.get('tag', 'latest')
        digest = info.get('digest', '')

        manifest['services'][service] = {
            'image': f"{DEFAULT_REGISTRY}/{service}",
            'current_tag': tag,
            'deployed_at': now,
            'deployed_by': 'migration',
            'image_digest': digest
        }

        manifest['history'][service] = [{
            'tag': tag,
            'deployed_at': now,
            'status': 'current'
        }]

    return manifest


def generate_versions_env(manifest: Dict) -> str:
    """Generate versions.env content from manifest"""
    ecr = manifest.get('ecr', {})
    registry = ecr.get('registry', 'public.ecr.aws')
    alias = ecr.get('repository_alias', 'n5k3t9x2')
    full_registry = f"{registry}/{alias}"

    lines = [
        "# DagKnows Service Versions",
        "# Auto-generated from version-manifest.yaml - DO NOT EDIT MANUALLY",
        f"# Generated: {datetime.now().isoformat()}",
        "",
        f"DK_ECR_REGISTRY={full_registry}",
        ""
    ]

    services = manifest.get('services', {})
    for name in SERVICES:
        info = services.get(name, {})
        var_name = name.upper()
        image = f"{full_registry}/{name}"
        tag = info.get('current_tag', 'latest')

        lines.append(f"DK_{var_name}_IMAGE={image}")
        lines.append(f"DK_{var_name}_TAG={tag}")
        lines.append("")

    return '\n'.join(lines)


def verify_config() -> bool:
    """Verify the configuration is valid"""
    # Check manifest exists and is valid YAML
    if not os.path.exists('version-manifest.yaml'):
        print_error("version-manifest.yaml not found")
        return False

    try:
        with open('version-manifest.yaml', 'r') as f:
            manifest = yaml.safe_load(f)
        if not manifest or 'services' not in manifest:
            print_error("Invalid manifest structure")
            return False
        print_success("version-manifest.yaml is valid")
    except yaml.YAMLError as e:
        print_error(f"Invalid YAML: {e}")
        return False

    # Check versions.env exists
    if not os.path.exists('versions.env'):
        print_error("versions.env not found")
        return False
    print_success("versions.env exists")

    # Check docker-compose.yml has variable references
    if os.path.exists('docker-compose.yml'):
        with open('docker-compose.yml', 'r') as f:
            content = f.read()
        if 'DK_REQ_ROUTER_TAG' in content:
            print_success("docker-compose.yml uses version variables")
        else:
            print_warning("docker-compose.yml may need updating to use version variables")

    return True


# ============================================
# MAIN MIGRATION WORKFLOW
# ============================================

def migrate():
    """Main migration workflow"""
    print_header("DagKnows Version Migration Wizard")

    print("This wizard will enable version tracking for your DagKnows deployment.")
    print("It will create a version manifest based on your currently running containers.")
    print()

    # Step 1: Confirm
    if not confirm("This will enable version tracking. Continue?"):
        print("Migration cancelled.")
        return False

    # Step 2: Check if already migrated
    if os.path.exists('version-manifest.yaml'):
        print_warning("version-manifest.yaml already exists!")
        if not confirm("Overwrite existing manifest?"):
            print("Migration cancelled.")
            return False

    # Step 3: Detect current state
    print_step("Detecting current deployment state...")

    images = get_running_images()

    if not images:
        print_warning("No running containers detected.")
        print_info("Make sure services are running with 'make up' before migration.")
        if not confirm("Continue anyway (will use 'latest' for all services)?"):
            print("Migration cancelled.")
            return False
    else:
        show_current_state(images)

    if not confirm("\nCreate manifest from detected images?"):
        print("Migration cancelled.")
        return False

    # Step 4: Get optional deployment info
    print_step("Deployment Information (optional)")

    customer_id = input("Customer ID (press Enter to skip): ").strip()
    deployment_id = input("Deployment ID (press Enter for auto-generated): ").strip()

    # Step 5: Create manifest
    print_step("Creating version-manifest.yaml...")

    manifest = create_manifest_from_current(images, customer_id, deployment_id)

    with open('version-manifest.yaml', 'w') as f:
        yaml.dump(manifest, f, default_flow_style=False, sort_keys=False)

    print_success("Created version-manifest.yaml")

    # Step 6: Generate versions.env
    print_step("Generating versions.env...")

    env_content = generate_versions_env(manifest)
    with open('versions.env', 'w') as f:
        f.write(env_content)

    print_success("Created versions.env")

    # Step 7: Verify
    print_step("Verifying configuration...")

    if verify_config():
        print_success("Migration completed successfully!")
        print()
        print(f"{Colors.BOLD}Next steps:{Colors.ENDC}")
        print("  1. Run 'make version' to see current versions")
        print("  2. Run 'make up' to restart with version tracking")
        print("  3. Run 'make help-version' for all version commands")
        print()
        return True
    else:
        print_error("Migration verification failed!")
        return False


def main():
    """Entry point"""
    # Change to script directory
    script_dir = Path(__file__).parent.absolute()
    os.chdir(script_dir)

    try:
        success = migrate()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print(f"\n{Colors.WARNING}Migration cancelled{Colors.ENDC}")
        sys.exit(1)
    except Exception as e:
        print(f"\n{Colors.FAIL}Error during migration: {e}{Colors.ENDC}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
