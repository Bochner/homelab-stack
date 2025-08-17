#!/usr/bin/env python3
"""
Check for container image updates and generate update report.
This script helps track which images have newer versions available.
"""

import os
import sys
import json
import yaml
import requests
import subprocess
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from pathlib import Path

class ImageUpdateChecker:
    def __init__(self):
        self.compose_files = []
        self.find_compose_files()

    def find_compose_files(self):
        """Find all docker-compose files in the project."""
        compose_patterns = [
            "docker-compose.yml",
            "docker-compose.yaml",
            "**/docker-compose.yml",
            "**/docker-compose.yaml"
        ]

        for pattern in compose_patterns:
            files = list(Path(".").glob(pattern))
            self.compose_files.extend(files)

        # Remove duplicates and sort
        self.compose_files = sorted(list(set(self.compose_files)))
        print(f"Found {len(self.compose_files)} compose files")

    def extract_images_from_compose(self, compose_file: Path) -> List[str]:
        """Extract all image references from a compose file."""
        try:
            with open(compose_file, 'r') as f:
                compose_data = yaml.safe_load(f)

            images = []
            services = compose_data.get('services', {})

            for service_name, service_config in services.items():
                image = service_config.get('image')
                if image:
                    images.append(image)

            return images

        except Exception as e:
            print(f"Error parsing {compose_file}: {e}")
            return []

    def parse_image_reference(self, image_ref: str) -> Tuple[str, str, str]:
        """Parse image reference into registry, name, and tag."""
        # Handle different image reference formats:
        # - nginx:latest
        # - docker.io/nginx:latest
        # - ghcr.io/user/repo:tag
        # - quay.io/keycloak/keycloak:23.0

        registry = "docker.io"  # Default registry

        parts = image_ref.split('/')

        if '.' in parts[0] or ':' in parts[0]:
            # First part contains registry
            registry = parts[0]
            image_parts = '/'.join(parts[1:])
        else:
            image_parts = image_ref

        # Split name and tag
        if ':' in image_parts:
            name, tag = image_parts.rsplit(':', 1)
        else:
            name = image_parts
            tag = "latest"

        return registry, name, tag

    def get_dockerhub_tags(self, image_name: str) -> List[str]:
        """Get available tags from Docker Hub."""
        try:
            # Handle library images (no user prefix)
            if '/' not in image_name:
                url = f"https://registry.hub.docker.com/v2/repositories/library/{image_name}/tags"
            else:
                url = f"https://registry.hub.docker.com/v2/repositories/{image_name}/tags"

            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                tags = [tag['name'] for tag in data.get('results', [])]
                return tags[:10]  # Return first 10 tags
            else:
                print(f"Failed to fetch tags for {image_name}: {response.status_code}")
                return []
        except Exception as e:
            print(f"Error fetching tags for {image_name}: {e}")
            return []

    def get_ghcr_tags(self, image_name: str) -> List[str]:
        """Get available tags from GitHub Container Registry."""
        try:
            # GHCR uses GitHub API
            parts = image_name.split('/')
            if len(parts) >= 2:
                owner = parts[0]
                package = parts[1]

                url = f"https://api.github.com/users/{owner}/packages/container/{package}/versions"
                headers = {'Accept': 'application/vnd.github.v3+json'}

                response = requests.get(url, headers=headers, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    tags = []
                    for version in data[:10]:  # First 10 versions
                        tags.extend(version.get('metadata', {}).get('container', {}).get('tags', []))
                    return list(set(tags))[:10]  # Remove duplicates, return first 10
            return []
        except Exception as e:
            print(f"Error fetching GHCR tags for {image_name}: {e}")
            return []

    def get_quay_tags(self, image_name: str) -> List[str]:
        """Get available tags from Quay.io."""
        try:
            url = f"https://quay.io/api/v1/repository/{image_name}/tag/"
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                data = response.json()
                tags = [tag['name'] for tag in data.get('tags', [])]
                return tags[:10]  # Return first 10 tags
            return []
        except Exception as e:
            print(f"Error fetching Quay tags for {image_name}: {e}")
            return []

    def get_available_tags(self, registry: str, image_name: str) -> List[str]:
        """Get available tags for an image from its registry."""
        if registry == "docker.io":
            return self.get_dockerhub_tags(image_name)
        elif registry == "ghcr.io":
            return self.get_ghcr_tags(image_name)
        elif registry == "quay.io":
            return self.get_quay_tags(image_name)
        else:
            print(f"Unsupported registry: {registry}")
            return []

    def check_local_image_age(self, image_ref: str) -> Optional[str]:
        """Check when the local image was created."""
        try:
            result = subprocess.run(
                ["docker", "image", "inspect", image_ref, "--format", "{{.Created}}"],
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None

    def generate_update_report(self) -> Dict:
        """Generate a comprehensive update report."""
        report = {
            "timestamp": datetime.now().isoformat(),
            "images": {},
            "summary": {
                "total_images": 0,
                "images_with_updates": 0,
                "unreachable_registries": 0
            }
        }

        all_images = set()

        # Collect all images from compose files
        for compose_file in self.compose_files:
            images = self.extract_images_from_compose(compose_file)
            for image in images:
                all_images.add(image)

        report["summary"]["total_images"] = len(all_images)

        # Check each unique image
        for image_ref in sorted(all_images):
            print(f"Checking {image_ref}...")

            registry, name, current_tag = self.parse_image_reference(image_ref)

            # Get available tags
            available_tags = self.get_available_tags(registry, name)

            # Get local image info
            local_created = self.check_local_image_age(image_ref)

            image_info = {
                "registry": registry,
                "name": name,
                "current_tag": current_tag,
                "available_tags": available_tags,
                "local_created": local_created,
                "has_updates": len(available_tags) > 0 and current_tag not in available_tags[:5],
                "registry_accessible": len(available_tags) > 0
            }

            report["images"][image_ref] = image_info

            if image_info["has_updates"]:
                report["summary"]["images_with_updates"] += 1

            if not image_info["registry_accessible"]:
                report["summary"]["unreachable_registries"] += 1

        return report

    def print_report(self, report: Dict):
        """Print a human-readable update report."""
        print("\n" + "="*60)
        print("HOMELAB IMAGE UPDATE REPORT")
        print("="*60)
        print(f"Generated: {report['timestamp']}")
        print(f"Total images: {report['summary']['total_images']}")
        print(f"Images with potential updates: {report['summary']['images_with_updates']}")
        print(f"Unreachable registries: {report['summary']['unreachable_registries']}")

        print("\nDETAILED RESULTS:")
        print("-" * 60)

        for image_ref, info in report["images"].items():
            status = "🔄" if info["has_updates"] else "✅"
            registry_status = "🌐" if info["registry_accessible"] else "❌"

            print(f"{status} {registry_status} {image_ref}")
            print(f"    Registry: {info['registry']}")
            print(f"    Current tag: {info['current_tag']}")

            if info["available_tags"]:
                latest_tags = info["available_tags"][:3]
                print(f"    Latest tags: {', '.join(latest_tags)}")
            else:
                print("    Available tags: Unable to fetch")

            if info["local_created"]:
                print(f"    Local image created: {info['local_created']}")

            print()

        if report["summary"]["images_with_updates"] > 0:
            print("RECOMMENDED ACTIONS:")
            print("-" * 30)
            print("1. Review the available tags for images marked with 🔄")
            print("2. Update docker-compose.yml with newer tags if appropriate")
            print("3. Test updated images in a development environment first")
            print("4. Consider pinning to specific versions instead of 'latest'")
        else:
            print("🎉 All images appear to be using recent tags!")

    def save_report(self, report: Dict, filename: str = "update-report.json"):
        """Save the report to a JSON file."""
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"📄 Report saved to {filename}")

def main():
    print("🔍 Checking for container image updates...")

    checker = ImageUpdateChecker()
    report = checker.generate_update_report()

    # Print human-readable report
    checker.print_report(report)

    # Save detailed report
    checker.save_report(report)

    # Exit with appropriate code for CI
    if report["summary"]["images_with_updates"] > 0:
        print(f"\n⚠️  {report['summary']['images_with_updates']} image(s) may have updates available")
        sys.exit(1)
    else:
        print("\n✅ All images are up to date")

if __name__ == "__main__":
    main()
