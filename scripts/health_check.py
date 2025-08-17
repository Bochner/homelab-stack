#!/usr/bin/env python3
"""
Advanced health checking for homelab services.
Performs comprehensive health checks beyond basic container status.
"""

import json
import os
import sys
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple

import docker
import requests


class HealthChecker:
    def __init__(self):
        self.client = docker.from_env()
        self.results = {}

    def check_container_health(self, service_name: str) -> Tuple[bool, str]:
        """Check container health status."""
        try:
            container = self.client.containers.get(service_name)

            # Check if container is running
            if container.status != "running":
                return False, f"Container is {container.status}"

            # Check health status if available
            health = container.attrs.get("State", {}).get("Health", {})
            if health:
                status = health.get("Status", "unknown")
                if status == "healthy":
                    return True, "Container is healthy"
                elif status == "unhealthy":
                    return (
                        False,
                        f"Container is unhealthy: {health.get('Log', [])[-1] if health.get('Log') else 'No log'}",
                    )
                else:
                    return False, f"Container health status: {status}"

            # If no health check, assume healthy if running
            return True, "Container is running (no health check defined)"

        except docker.errors.NotFound:
            return False, "Container not found"
        except Exception as e:
            return False, f"Error checking container: {str(e)}"

    def check_traefik_health(self) -> Tuple[bool, str]:
        """Check Traefik reverse proxy health."""
        try:
            # First check container health
            container_healthy, container_msg = self.check_container_health("traefik")
            if not container_healthy:
                return False, f"Container check failed: {container_msg}"

            # Check Traefik API
            container = self.client.containers.get("traefik")
            networks = container.attrs["NetworkSettings"]["Networks"]

            # Try to get IP from homelab_net first, fallback to other networks
            ip = None
            for net_name, net_info in networks.items():
                if "homelab" in net_name or ip is None:
                    ip = net_info.get("IPAddress")
                    if ip:
                        break

            if not ip:
                return False, "Could not determine Traefik IP address"

            # Test Traefik API
            response = requests.get(f"http://{ip}:8080/api/rawdata", timeout=5)
            if response.status_code == 200:
                data = response.json()
                # Check if there are any services registered
                services = data.get("http", {}).get("services", {})
                routers = data.get("http", {}).get("routers", {})

                return (
                    True,
                    f"API accessible, {len(services)} services, {len(routers)} routers",
                )
            else:
                return False, f"API returned status {response.status_code}"

        except requests.exceptions.RequestException as e:
            return False, f"API request failed: {str(e)}"
        except Exception as e:
            return False, f"Unexpected error: {str(e)}"

    def check_pihole_health(self) -> Tuple[bool, str]:
        """Check Pi-hole DNS server health."""
        try:
            # Check container health
            container_healthy, container_msg = self.check_container_health("pihole")
            if not container_healthy:
                return False, f"Container check failed: {container_msg}"

            # Check if DNS is responding
            container = self.client.containers.get("pihole")
            networks = container.attrs["NetworkSettings"]["Networks"]

            ip = None
            for net_name, net_info in networks.items():
                if "homelab" in net_name or ip is None:
                    ip = net_info.get("IPAddress")
                    if ip:
                        break

            if not ip:
                return False, "Could not determine Pi-hole IP address"

            # Test DNS resolution
            result = container.exec_run(
                "dig +short +norecurse +retry=0 @127.0.0.1 pi.hole"
            )
            if result.exit_code == 0:
                return True, f"DNS server responding at {ip}"
            else:
                return False, f"DNS test failed: {result.output.decode()}"

        except Exception as e:
            return False, f"Error checking Pi-hole: {str(e)}"

    def check_keycloak_health(self) -> Tuple[bool, str]:
        """Check Keycloak authentication server health."""
        try:
            # Check container health
            container_healthy, container_msg = self.check_container_health("keycloak")
            if not container_healthy:
                return False, f"Container check failed: {container_msg}"

            # Check database dependency
            db_healthy, db_msg = self.check_container_health("keycloak-db")
            if not db_healthy:
                return False, f"Database dependency failed: {db_msg}"

            # Check Keycloak health endpoint
            container = self.client.containers.get("keycloak")
            result = container.exec_run("curl -f http://localhost:8080/health")

            if result.exit_code == 0:
                return True, "Health endpoint accessible"
            else:
                return False, f"Health endpoint failed: {result.output.decode()}"

        except Exception as e:
            return False, f"Error checking Keycloak: {str(e)}"

    def check_uptime_kuma_health(self) -> Tuple[bool, str]:
        """Check Uptime Kuma monitoring service health."""
        try:
            # Check container health
            container_healthy, container_msg = self.check_container_health(
                "uptime-kuma"
            )
            if not container_healthy:
                return False, f"Container check failed: {container_msg}"

            # Check web interface
            container = self.client.containers.get("uptime-kuma")
            result = container.exec_run("curl -f http://localhost:3001")

            if result.exit_code == 0:
                return True, "Web interface accessible"
            else:
                return False, f"Web interface failed: {result.output.decode()}"

        except Exception as e:
            return False, f"Error checking Uptime Kuma: {str(e)}"

    def check_homepage_health(self) -> Tuple[bool, str]:
        """Check Homepage dashboard health."""
        try:
            # Check container health
            container_healthy, container_msg = self.check_container_health("homepage")
            if not container_healthy:
                return False, f"Container check failed: {container_msg}"

            # Check web interface
            container = self.client.containers.get("homepage")
            result = container.exec_run(
                "wget --no-verbose --tries=1 --spider http://localhost:3000"
            )

            if result.exit_code == 0:
                return True, "Web interface accessible"
            else:
                return False, f"Web interface failed: {result.output.decode()}"

        except Exception as e:
            return False, f"Error checking Homepage: {str(e)}"

    def check_dockge_health(self) -> Tuple[bool, str]:
        """Check Dockge management interface health."""
        try:
            # Check container health
            container_healthy, container_msg = self.check_container_health("dockge")
            if not container_healthy:
                return False, f"Container check failed: {container_msg}"

            # Check web interface
            container = self.client.containers.get("dockge")
            result = container.exec_run("curl -f http://localhost:5001")

            if result.exit_code == 0:
                return True, "Web interface accessible"
            else:
                return False, f"Web interface failed: {result.output.decode()}"

        except Exception as e:
            return False, f"Error checking Dockge: {str(e)}"

    def check_network_connectivity(self) -> Tuple[bool, str]:
        """Check network connectivity between services."""
        try:
            # Check if homelab network exists
            try:
                network = self.client.networks.get("homelab_net")
            except docker.errors.NotFound:
                return False, "Homelab network not found"

            # Get containers in the network
            containers_in_network = []
            for container in self.client.containers.list():
                networks = container.attrs["NetworkSettings"]["Networks"]
                if "homelab_net" in networks:
                    containers_in_network.append(container.name)

            if len(containers_in_network) == 0:
                return False, "No containers found in homelab network"

            return (
                True,
                f"Network active with {len(containers_in_network)} containers: {', '.join(containers_in_network)}",
            )

        except Exception as e:
            return False, f"Error checking network: {str(e)}"

    def check_volumes(self) -> Tuple[bool, str]:
        """Check that required volumes exist and are accessible."""
        try:
            required_volumes = [
                "traefik_data",
                "pihole_data",
                "pihole_dnsmasq",
                "keycloak_data",
                "uptime_kuma_data",
                "dockge_data",
            ]

            existing_volumes = [vol.name for vol in self.client.volumes.list()]
            missing_volumes = []

            for vol in required_volumes:
                # Check for exact match or with project prefix
                found = any(vol in existing_vol for existing_vol in existing_volumes)
                if not found:
                    missing_volumes.append(vol)

            if missing_volumes:
                return False, f"Missing volumes: {', '.join(missing_volumes)}"

            return (
                True,
                f"All required volumes present ({len(required_volumes)} volumes)",
            )

        except Exception as e:
            return False, f"Error checking volumes: {str(e)}"

    def run_all_checks(self) -> Dict[str, Tuple[bool, str]]:
        """Run all health checks and return results."""
        checks = {
            "Network Connectivity": self.check_network_connectivity,
            "Volumes": self.check_volumes,
            "Traefik": self.check_traefik_health,
            "Pi-hole": self.check_pihole_health,
            "Keycloak Database": lambda: self.check_container_health("keycloak-db"),
            "Keycloak": self.check_keycloak_health,
            "Uptime Kuma": self.check_uptime_kuma_health,
            "Dockge": self.check_dockge_health,
            "Homepage": self.check_homepage_health,
            "Watchtower": lambda: self.check_container_health("watchtower"),
        }

        results = {}

        print("🏥 Running homelab health checks...")
        print("=" * 50)

        for check_name, check_func in checks.items():
            print(f"Checking {check_name}...", end=" ")
            try:
                healthy, message = check_func()
                results[check_name] = (healthy, message)

                if healthy:
                    print(f"✅ {message}")
                else:
                    print(f"❌ {message}")

            except Exception as e:
                results[check_name] = (False, f"Check failed: {str(e)}")
                print(f"💥 Check failed: {str(e)}")

        return results

    def generate_report(self, results: Dict[str, Tuple[bool, str]]) -> str:
        """Generate a detailed health report."""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        healthy_count = sum(1 for healthy, _ in results.values() if healthy)
        total_count = len(results)

        report = [
            "HOMELAB HEALTH REPORT",
            "=" * 50,
            f"Timestamp: {timestamp}",
            f"Overall Status: {healthy_count}/{total_count} services healthy",
            "",
            "DETAILED RESULTS:",
            "-" * 30,
        ]

        for service, (healthy, message) in results.items():
            status = "✅ HEALTHY" if healthy else "❌ UNHEALTHY"
            report.append(f"{service:20} {status:12} {message}")

        report.extend(
            [
                "",
                "RECOMMENDATIONS:",
                "-" * 20,
            ]
        )

        unhealthy_services = [
            name for name, (healthy, _) in results.items() if not healthy
        ]

        if not unhealthy_services:
            report.append("🎉 All services are healthy! No action required.")
        else:
            report.append("⚠️  The following services need attention:")
            for service in unhealthy_services:
                _, message = results[service]
                report.append(f"   • {service}: {message}")

            report.extend(
                [
                    "",
                    "Suggested actions:",
                    "1. Check service logs: docker logs <service-name>",
                    "2. Restart problematic services: docker compose restart <service-name>",
                    "3. Verify environment configuration in .env file",
                    "4. Check available resources (CPU, memory, disk space)",
                ]
            )

        return "\n".join(report)


def main():
    checker = HealthChecker()

    # Run all health checks
    results = checker.run_all_checks()

    # Generate and print report
    print("\n")
    report = checker.generate_report(results)
    print(report)

    # Save report to file if running in CI
    if os.environ.get("CI"):
        with open("health-report.txt", "w") as f:
            f.write(report)
        print("\n📄 Health report saved to health-report.txt")

    # Exit with error code if any service is unhealthy
    unhealthy_count = sum(1 for healthy, _ in results.values() if not healthy)
    if unhealthy_count > 0:
        print(f"\n💥 {unhealthy_count} service(s) are unhealthy")
        sys.exit(1)
    else:
        print("\n🎉 All services are healthy!")


if __name__ == "__main__":
    main()
