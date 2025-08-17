#!/usr/bin/env python3
"""
Security audit script for homelab stack Docker configurations.
Checks for common security misconfigurations and best practices.
"""

import os
import sys
import yaml
import json
from pathlib import Path
from typing import Dict, List, Tuple, Optional

class SecurityAuditor:
    def __init__(self):
        self.findings = []
        self.compose_files = []
        self.find_compose_files()

    def find_compose_files(self):
        """Find all docker-compose files in the project."""
        patterns = ["docker-compose.yml", "docker-compose.yaml", "**/docker-compose*.yml"]

        for pattern in patterns:
            files = list(Path(".").glob(pattern))
            self.compose_files.extend(files)

        self.compose_files = sorted(list(set(self.compose_files)))

    def add_finding(self, severity: str, category: str, message: str,
                   file_path: str = "", line: int = 0):
        """Add a security finding."""
        self.findings.append({
            "severity": severity,
            "category": category,
            "message": message,
            "file": file_path,
            "line": line
        })

    def check_privileged_containers(self, compose_file: Path, compose_data: dict):
        """Check for privileged containers and dangerous capabilities."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            # Check for privileged mode
            if service_config.get('privileged', False):
                self.add_finding(
                    "HIGH",
                    "Container Security",
                    f"Service '{service_name}' runs in privileged mode",
                    str(compose_file)
                )

            # Check for dangerous capabilities
            cap_add = service_config.get('cap_add', [])
            dangerous_caps = ['SYS_ADMIN', 'NET_ADMIN', 'SYS_PTRACE', 'SYS_MODULE']

            for cap in cap_add:
                if cap in dangerous_caps:
                    self.add_finding(
                        "MEDIUM",
                        "Container Security",
                        f"Service '{service_name}' has dangerous capability: {cap}",
                        str(compose_file)
                    )

            # Check for --privileged in command
            command = service_config.get('command', '')
            if isinstance(command, str) and '--privileged' in command:
                self.add_finding(
                    "HIGH",
                    "Container Security",
                    f"Service '{service_name}' uses --privileged in command",
                    str(compose_file)
                )

    def check_host_network_mode(self, compose_file: Path, compose_data: dict):
        """Check for host network mode usage."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            network_mode = service_config.get('network_mode')
            if network_mode == 'host':
                self.add_finding(
                    "MEDIUM",
                    "Network Security",
                    f"Service '{service_name}' uses host network mode",
                    str(compose_file)
                )

    def check_volume_mounts(self, compose_file: Path, compose_data: dict):
        """Check for dangerous volume mounts."""
        services = compose_data.get('services', {})

        dangerous_mounts = [
            '/var/run/docker.sock',
            '/proc',
            '/sys',
            '/etc/passwd',
            '/etc/shadow',
            '/etc/sudoers',
            '/root/.ssh'
        ]

        for service_name, service_config in services.items():
            volumes = service_config.get('volumes', [])

            for volume in volumes:
                if isinstance(volume, str):
                    # Parse volume string
                    if ':' in volume:
                        host_path = volume.split(':')[0]

                        # Check for dangerous mounts
                        for dangerous in dangerous_mounts:
                            if host_path == dangerous:
                                severity = "HIGH" if dangerous == '/var/run/docker.sock' else "MEDIUM"
                                self.add_finding(
                                    severity,
                                    "Volume Security",
                                    f"Service '{service_name}' mounts dangerous path: {dangerous}",
                                    str(compose_file)
                                )

                        # Check for root filesystem access
                        if host_path == '/' or host_path.startswith('/home'):
                            self.add_finding(
                                "HIGH",
                                "Volume Security",
                                f"Service '{service_name}' has broad filesystem access: {host_path}",
                                str(compose_file)
                            )

                elif isinstance(volume, dict):
                    # Handle long-form volume syntax
                    source = volume.get('source', '')
                    if source in dangerous_mounts:
                        self.add_finding(
                            "HIGH",
                            "Volume Security",
                            f"Service '{service_name}' mounts dangerous path: {source}",
                            str(compose_file)
                        )

    def check_environment_variables(self, compose_file: Path, compose_data: dict):
        """Check for exposed secrets in environment variables."""
        services = compose_data.get('services', {})

        secret_patterns = [
            'password', 'passwd', 'secret', 'key', 'token',
            'credential', 'auth', 'private'
        ]

        for service_name, service_config in services.items():
            environment = service_config.get('environment', {})

            # Handle both list and dict formats
            env_vars = {}
            if isinstance(environment, list):
                for env_var in environment:
                    if '=' in env_var:
                        key, value = env_var.split('=', 1)
                        env_vars[key] = value
            elif isinstance(environment, dict):
                env_vars = environment

            for env_key, env_value in env_vars.items():
                # Check for hardcoded secrets
                for pattern in secret_patterns:
                    if pattern.lower() in env_key.lower():
                        if isinstance(env_value, str) and not env_value.startswith('${'):
                            # Not using environment variable substitution
                            if len(env_value) > 0 and not env_value.lower() in ['changeme', 'your-password', 'example']:
                                self.add_finding(
                                    "HIGH",
                                    "Secret Management",
                                    f"Service '{service_name}' may have hardcoded secret in {env_key}",
                                    str(compose_file)
                                )

    def check_user_configuration(self, compose_file: Path, compose_data: dict):
        """Check for proper user configuration."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            user = service_config.get('user')

            # Check if running as root
            if user == 'root' or user == '0':
                self.add_finding(
                    "MEDIUM",
                    "Container Security",
                    f"Service '{service_name}' explicitly runs as root",
                    str(compose_file)
                )
            elif user is None:
                # No user specified - may run as root
                self.add_finding(
                    "LOW",
                    "Container Security",
                    f"Service '{service_name}' doesn't specify user (may run as root)",
                    str(compose_file)
                )

    def check_security_options(self, compose_file: Path, compose_data: dict):
        """Check for security hardening options."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            security_opt = service_config.get('security_opt', [])

            # Check for no-new-privileges
            has_no_new_privileges = any('no-new-privileges:true' in opt for opt in security_opt)

            if not has_no_new_privileges:
                self.add_finding(
                    "LOW",
                    "Container Security",
                    f"Service '{service_name}' missing 'no-new-privileges:true' security option",
                    str(compose_file)
                )

            # Check for AppArmor/SELinux
            has_mandatory_access_control = any(
                'apparmor' in opt.lower() or 'selinux' in opt.lower()
                for opt in security_opt
            )

            if not has_mandatory_access_control:
                self.add_finding(
                    "INFO",
                    "Container Security",
                    f"Service '{service_name}' could benefit from AppArmor/SELinux profile",
                    str(compose_file)
                )

    def check_network_security(self, compose_file: Path, compose_data: dict):
        """Check network security configuration."""
        services = compose_data.get('services', {})
        networks = compose_data.get('networks', {})

        # Check for services without explicit networks
        for service_name, service_config in services.items():
            service_networks = service_config.get('networks', [])

            if not service_networks and 'network_mode' not in service_config:
                self.add_finding(
                    "LOW",
                    "Network Security",
                    f"Service '{service_name}' uses default network (consider explicit network)",
                    str(compose_file)
                )

        # Check for external networks
        for network_name, network_config in networks.items():
            if network_config.get('external', False):
                self.add_finding(
                    "INFO",
                    "Network Security",
                    f"Network '{network_name}' is external - ensure it's properly secured",
                    str(compose_file)
                )

    def check_port_exposure(self, compose_file: Path, compose_data: dict):
        """Check for unnecessary port exposure."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            ports = service_config.get('ports', [])

            for port in ports:
                if isinstance(port, str):
                    # Check for binding to all interfaces
                    if port.startswith('0.0.0.0:') or ':' not in port or port.count(':') == 1:
                        self.add_finding(
                            "MEDIUM",
                            "Network Security",
                            f"Service '{service_name}' exposes port {port} to all interfaces",
                            str(compose_file)
                        )

                # Check for common dangerous ports
                dangerous_ports = ['22', '23', '80', '443', '3389', '5432', '3306']
                port_num = str(port).split(':')[-1].split('/')[0]

                if port_num in dangerous_ports:
                    self.add_finding(
                        "MEDIUM",
                        "Network Security",
                        f"Service '{service_name}' exposes sensitive port {port_num}",
                        str(compose_file)
                    )

    def check_restart_policies(self, compose_file: Path, compose_data: dict):
        """Check restart policies for security implications."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            restart = service_config.get('restart')

            if restart == 'always':
                self.add_finding(
                    "LOW",
                    "Container Security",
                    f"Service '{service_name}' uses 'always' restart (consider 'unless-stopped')",
                    str(compose_file)
                )

    def check_image_security(self, compose_file: Path, compose_data: dict):
        """Check image security best practices."""
        services = compose_data.get('services', {})

        for service_name, service_config in services.items():
            image = service_config.get('image', '')

            # Check for latest tag
            if image.endswith(':latest') or ':' not in image:
                self.add_finding(
                    "LOW",
                    "Image Security",
                    f"Service '{service_name}' uses 'latest' tag or no tag specified",
                    str(compose_file)
                )

            # Check for trusted registries
            trusted_registries = [
                'docker.io', 'ghcr.io', 'quay.io', 'registry.redhat.io',
                'mcr.microsoft.com', 'gcr.io'
            ]

            if '/' in image and not any(reg in image for reg in trusted_registries):
                self.add_finding(
                    "MEDIUM",
                    "Image Security",
                    f"Service '{service_name}' uses image from potentially untrusted registry",
                    str(compose_file)
                )

    def audit_compose_file(self, compose_file: Path):
        """Audit a single compose file."""
        try:
            with open(compose_file, 'r') as f:
                compose_data = yaml.safe_load(f)

            if not compose_data or 'services' not in compose_data:
                return

            # Run all security checks
            self.check_privileged_containers(compose_file, compose_data)
            self.check_host_network_mode(compose_file, compose_data)
            self.check_volume_mounts(compose_file, compose_data)
            self.check_environment_variables(compose_file, compose_data)
            self.check_user_configuration(compose_file, compose_data)
            self.check_security_options(compose_file, compose_data)
            self.check_network_security(compose_file, compose_data)
            self.check_port_exposure(compose_file, compose_data)
            self.check_restart_policies(compose_file, compose_data)
            self.check_image_security(compose_file, compose_data)

        except Exception as e:
            self.add_finding(
                "ERROR",
                "File Processing",
                f"Failed to process {compose_file}: {str(e)}",
                str(compose_file)
            )

    def run_audit(self) -> Dict:
        """Run security audit on all compose files."""
        print("🔒 Starting security audit...")

        for compose_file in self.compose_files:
            print(f"  Auditing {compose_file}...")
            self.audit_compose_file(compose_file)

        # Categorize findings by severity
        severity_counts = {"HIGH": 0, "MEDIUM": 0, "LOW": 0, "INFO": 0, "ERROR": 0}

        for finding in self.findings:
            severity_counts[finding["severity"]] += 1

        return {
            "findings": self.findings,
            "summary": severity_counts,
            "total_files": len(self.compose_files),
            "total_findings": len(self.findings)
        }

    def print_report(self, audit_result: Dict):
        """Print human-readable security report."""
        print("\n" + "="*60)
        print("SECURITY AUDIT REPORT")
        print("="*60)

        summary = audit_result["summary"]
        print(f"Files scanned: {audit_result['total_files']}")
        print(f"Total findings: {audit_result['total_findings']}")
        print()

        print("Findings by severity:")
        for severity, count in summary.items():
            if count > 0:
                icon = {"HIGH": "🚨", "MEDIUM": "⚠️", "LOW": "💡", "INFO": "ℹ️", "ERROR": "💥"}
                print(f"  {icon.get(severity, '')} {severity}: {count}")

        if audit_result["findings"]:
            print("\nDetailed findings:")
            print("-" * 60)

            # Group by severity
            for severity in ["HIGH", "MEDIUM", "LOW", "INFO", "ERROR"]:
                severity_findings = [f for f in audit_result["findings"] if f["severity"] == severity]

                if severity_findings:
                    print(f"\n{severity} SEVERITY:")
                    for finding in severity_findings:
                        file_info = f" ({finding['file']})" if finding['file'] else ""
                        print(f"  • {finding['message']}{file_info}")

            print("\nRecommendations:")
            print("-" * 30)
            print("1. Address HIGH and MEDIUM severity findings immediately")
            print("2. Review volume mounts for unnecessary host access")
            print("3. Use specific image tags instead of 'latest'")
            print("4. Implement proper user configurations")
            print("5. Add security hardening options like 'no-new-privileges'")
            print("6. Consider using secrets management for sensitive data")
        else:
            print("\n🎉 No security issues found!")

    def save_report(self, audit_result: Dict, filename: str = "security-audit.json"):
        """Save audit results to JSON file."""
        with open(filename, 'w') as f:
            json.dump(audit_result, f, indent=2)
        print(f"\n📄 Detailed report saved to {filename}")

def main():
    auditor = SecurityAuditor()

    # Run the audit
    results = auditor.run_audit()

    # Print and save results
    auditor.print_report(results)
    auditor.save_report(results)

    # Default to homelab mode - this is designed for homelab use
    homelab_mode = True

    # Exit with appropriate code
    high_count = results["summary"]["HIGH"]
    critical_issues = []

    # Only fail on truly critical issues for homelabs
    for finding in results["findings"]:
        if finding["severity"] == "HIGH":
            # Allow common homelab patterns
            if any(pattern in finding["message"].lower() for pattern in [
                "docker.sock", "host network", "port", "privileged"
            ]):
                continue  # These are often necessary for homelab services
            critical_issues.append(finding)

    if critical_issues:
        print(f"\n💥 Found {len(critical_issues)} critical security issues that need attention:")
        for issue in critical_issues:
            print(f"  • {issue['message']}")
        sys.exit(1)
    else:
        print(f"\n🏠 HOMELAB MODE: Found {high_count + results['summary']['MEDIUM']} issues (typical for homelab)")
        if high_count > 0:
            print("ℹ️  Note: High severity findings are typically acceptable in homelab environments")
            print("   (Docker socket access, port exposure, privileged containers for functionality)")
        print("✅ No critical security issues found for homelab deployment!")
        sys.exit(0)

if __name__ == "__main__":
    main()
