#!/usr/bin/env python3
"""
Extract individual service configurations from docker-compose.yml for testing.
This script creates isolated compose files for individual services.
"""

import sys
import yaml
import argparse
from pathlib import Path

def extract_service(compose_file, service_name):
    """Extract a specific service and its dependencies from a compose file."""
    
    with open(compose_file, 'r') as f:
        compose_data = yaml.safe_load(f)
    
    if 'services' not in compose_data:
        raise ValueError("No services found in compose file")
    
    if service_name not in compose_data['services']:
        available_services = list(compose_data['services'].keys())
        raise ValueError(f"Service '{service_name}' not found. Available: {available_services}")
    
    # Create new compose structure with just the requested service
    new_compose = {
        'version': compose_data.get('version', '3.9'),
        'networks': compose_data.get('networks', {}),
        'volumes': {},
        'services': {}
    }
    
    # Get the main service
    service_config = compose_data['services'][service_name]
    new_compose['services'][service_name] = service_config
    
    # Check for dependencies and include them
    depends_on = service_config.get('depends_on', {})
    if isinstance(depends_on, list):
        # Old format: depends_on as list
        for dep in depends_on:
            if dep in compose_data['services']:
                new_compose['services'][dep] = compose_data['services'][dep]
    elif isinstance(depends_on, dict):
        # New format: depends_on as dict with conditions
        for dep in depends_on.keys():
            if dep in compose_data['services']:
                new_compose['services'][dep] = compose_data['services'][dep]
    
    # Collect all volumes used by included services
    for svc_name, svc_config in new_compose['services'].items():
        volumes = svc_config.get('volumes', [])
        for volume in volumes:
            if isinstance(volume, str):
                # Parse volume string (e.g., "volume_name:/path")
                if ':' in volume:
                    vol_name = volume.split(':')[0]
                    # Only add named volumes (not bind mounts)
                    if not vol_name.startswith('/') and not vol_name.startswith('./'):
                        if vol_name in compose_data.get('volumes', {}):
                            new_compose['volumes'][vol_name] = compose_data['volumes'][vol_name]
            elif isinstance(volume, dict):
                # Handle long-form volume syntax
                if 'source' in volume:
                    vol_name = volume['source']
                    if vol_name in compose_data.get('volumes', {}):
                        new_compose['volumes'][vol_name] = compose_data['volumes'][vol_name]
    
    # Remove empty sections
    if not new_compose['volumes']:
        del new_compose['volumes']
    
    return new_compose

def main():
    parser = argparse.ArgumentParser(description='Extract service from docker-compose.yml')
    parser.add_argument('service', help='Service name to extract')
    parser.add_argument('-f', '--file', default='docker-compose.yml', 
                       help='Docker compose file to read from')
    parser.add_argument('-o', '--output', help='Output file (default: stdout)')
    
    args = parser.parse_args()
    
    try:
        extracted = extract_service(args.file, args.service)
        output = yaml.dump(extracted, default_flow_style=False, sort_keys=False)
        
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output)
            print(f"Extracted {args.service} to {args.output}")
        else:
            print(output)
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
