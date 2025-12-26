#!/usr/bin/env python3
"""
============================================================================
INSTITUTIONAL EDGE PRO - Instance Manager
============================================================================
Manages multiple trading bot instances dynamically.
Generates docker-compose files from templates and manages instance lifecycle.
"""

import os
import yaml
import json
from pathlib import Path
from typing import Dict, List, Optional


class InstanceConfig:
    """Configuration for a single instance"""

    def __init__(
        self,
        instance_number: int,
        instance_name: str,
        mt5_login: str,
        mt5_password: str,
        mt5_server: str,
        mt5_path: str = ""
    ):
        self.instance_number = instance_number
        self.instance_name = instance_name
        self.mt5_login = mt5_login
        self.mt5_password = mt5_password
        self.mt5_server = mt5_server
        self.mt5_path = mt5_path

        # Port allocation (based on instance number)
        # Instance 1: VNC=3000, RPYC=8001, API=8000, WEB=80
        # Instance 2: VNC=3001, RPYC=8003, API=8002, WEB=81
        # Instance N: VNC=3000+(N-1), RPYC=8001+2*(N-1), API=8000+2*(N-1), WEB=80+(N-1)
        self.vnc_port = 3000 + (instance_number - 1)
        self.rpyc_port = 8001 + 2 * (instance_number - 1)
        self.api_port = 8000 + 2 * (instance_number - 1)
        self.web_port = 80 + (instance_number - 1)

    def to_dict(self) -> Dict:
        """Convert to dictionary"""
        return {
            'instance_number': self.instance_number,
            'instance_name': self.instance_name,
            'mt5_login': self.mt5_login,
            'mt5_server': self.mt5_server,
            'vnc_port': self.vnc_port,
            'rpyc_port': self.rpyc_port,
            'api_port': self.api_port,
            'web_port': self.web_port,
        }


class InstanceManager:
    """Manages multiple trading bot instances"""

    def __init__(self, base_dir: str = "."):
        self.base_dir = Path(base_dir)
        self.instances_dir = self.base_dir / "instances"
        self.instances_dir.mkdir(exist_ok=True)

        self.template_path = self.base_dir / "instance-template.yml"
        self.registry_path = self.instances_dir / "registry.json"

        # Load existing registry
        self.registry = self._load_registry()

    def _load_registry(self) -> Dict:
        """Load instance registry from file"""
        if self.registry_path.exists():
            with open(self.registry_path, 'r') as f:
                return json.load(f)
        return {"instances": []}

    def _save_registry(self):
        """Save instance registry to file"""
        with open(self.registry_path, 'w') as f:
            json.dump(self.registry, f, indent=2)

    def _load_template(self) -> str:
        """Load docker-compose template"""
        with open(self.template_path, 'r') as f:
            return f.read()

    def create_instance(self, config: InstanceConfig) -> Path:
        """
        Create a new instance from template
        Returns the path to the generated docker-compose file
        """
        # Load template
        template = self._load_template()

        # Replace variables
        instance_config = template.format(
            INSTANCE_NUMBER=config.instance_number,
            INSTANCE_NAME=config.instance_name,
            VNC_PORT=config.vnc_port,
            RPYC_PORT=config.rpyc_port,
            API_PORT=config.api_port,
            WEB_PORT=config.web_port,
            MT5_LOGIN=config.mt5_login,
            MT5_PASSWORD=config.mt5_password,
            MT5_SERVER=config.mt5_server,
        )

        # Create instance directory
        instance_dir = self.instances_dir / f"instance-{config.instance_number}"
        instance_dir.mkdir(exist_ok=True)

        # Write docker-compose file
        compose_path = instance_dir / "docker-compose.yml"
        with open(compose_path, 'w') as f:
            f.write(instance_config)

        # Update registry
        instance_data = config.to_dict()
        instance_data['compose_path'] = str(compose_path)
        instance_data['status'] = 'created'

        # Check if instance already exists in registry
        existing_idx = next(
            (i for i, inst in enumerate(self.registry['instances'])
             if inst['instance_number'] == config.instance_number),
            None
        )

        if existing_idx is not None:
            self.registry['instances'][existing_idx] = instance_data
        else:
            self.registry['instances'].append(instance_data)

        self._save_registry()

        print(f"✅ Created instance {config.instance_number} ({config.instance_name})")
        print(f"   VNC: http://localhost:{config.vnc_port}")
        print(f"   Frontend: http://localhost/instance/{config.instance_number}")
        print(f"   Backend API: http://localhost/instance/{config.instance_number}/api")
        print(f"   Compose file: {compose_path}")

        return compose_path

    def list_instances(self) -> List[Dict]:
        """List all instances"""
        return self.registry['instances']

    def get_instance(self, instance_number: int) -> Optional[Dict]:
        """Get instance by number"""
        return next(
            (inst for inst in self.registry['instances']
             if inst['instance_number'] == instance_number),
            None
        )

    def delete_instance(self, instance_number: int) -> bool:
        """Delete an instance configuration"""
        instance = self.get_instance(instance_number)
        if not instance:
            print(f"❌ Instance {instance_number} not found")
            return False

        # Remove compose file
        compose_path = Path(instance['compose_path'])
        if compose_path.exists():
            compose_path.unlink()

        # Remove from registry
        self.registry['instances'] = [
            inst for inst in self.registry['instances']
            if inst['instance_number'] != instance_number
        ]
        self._save_registry()

        print(f"✅ Deleted instance {instance_number}")
        return True

    def update_nginx_config(self, max_instances: int = 10):
        """
        Generate nginx configuration for all instances
        This should be called after creating/deleting instances
        """
        nginx_template = """
        # Instance {instance_number} routes
        location /instance/{instance_number}/api/ {{
            proxy_pass http://instance_{instance_number}_backend/api/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_cache_bypass $http_upgrade;
        }}

        location /instance/{instance_number}/socket.io/ {{
            proxy_pass http://instance_{instance_number}_backend/socket.io/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_cache_bypass $http_upgrade;
        }}

        location /instance/{instance_number}/ {{
            proxy_pass http://instance_{instance_number}_frontend/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
        }}
        """

        print("ℹ️  Nginx config update would go here")
        print(f"   Active instances: {len(self.registry['instances'])}")


def main():
    """Example usage"""
    manager = InstanceManager(base_dir=".")

    # Example: Create instance 1
    config1 = InstanceConfig(
        instance_number=1,
        instance_name="main",
        mt5_login="49290627",
        mt5_password="Motivo@1",
        mt5_server="HFMarketsGlobal-Demo"
    )

    manager.create_instance(config1)

    # List instances
    print("\n📋 All instances:")
    for inst in manager.list_instances():
        print(f"   Instance {inst['instance_number']}: {inst['instance_name']} - Ports: {inst['web_port']}/{inst['api_port']}")


if __name__ == "__main__":
    main()
