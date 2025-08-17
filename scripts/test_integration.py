#!/usr/bin/env python3
"""
Integration testing for homelab stack services.
Tests service dependencies, network connectivity, and basic functionality.
"""

import os
import sys
import time
import docker
import requests
import subprocess
from pathlib import Path

class HomelabTester:
    def __init__(self):
        self.client = docker.from_env()
        self.test_network = "homelab_test"
        self.test_env_file = ".env.test"
        
    def run_command(self, cmd, check=True):
        """Run a shell command and return the result."""
        try:
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, check=check)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Command failed: {cmd}")
            print(f"Error: {e.stderr}")
            if check:
                raise
            return None
    
    def wait_for_container_health(self, container_name, timeout=60):
        """Wait for a container to become healthy."""
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            try:
                container = self.client.containers.get(container_name)
                health = container.attrs.get('State', {}).get('Health', {})
                status = health.get('Status')
                
                if status == 'healthy':
                    print(f"✅ {container_name} is healthy")
                    return True
                elif status == 'unhealthy':
                    print(f"❌ {container_name} is unhealthy")
                    return False
                    
                # If no health check, check if container is running
                if container.status == 'running' and not health:
                    print(f"✅ {container_name} is running (no health check)")
                    return True
                    
            except docker.errors.NotFound:
                pass
                
            time.sleep(2)
        
        print(f"⏰ Timeout waiting for {container_name} to become healthy")
        return False
    
    def test_traefik_startup(self):
        """Test Traefik reverse proxy startup and basic configuration."""
        print("Testing Traefik startup...")
        
        # Start Traefik service
        cmd = f"docker compose -f docker-compose.yml --env-file {self.test_env_file} up -d traefik"
        self.run_command(cmd)
        
        # Wait for Traefik to be healthy
        if not self.wait_for_container_health("traefik", 30):
            return False
        
        # Test Traefik API (internal)
        try:
            # Get Traefik container IP
            container = self.client.containers.get("traefik")
            ip = container.attrs['NetworkSettings']['Networks'][self.test_network]['IPAddress']
            
            # Test API endpoint
            response = requests.get(f"http://{ip}:8080/api/rawdata", timeout=10)
            if response.status_code == 200:
                print("✅ Traefik API is accessible")
                return True
        except Exception as e:
            print(f"❌ Traefik API test failed: {e}")
        
        return False
    
    def test_service_networking(self):
        """Test that services can communicate over the homelab network."""
        print("Testing service networking...")
        
        # Create a test container to check networking
        test_container = self.client.containers.run(
            "alpine:latest",
            command="sleep 60",
            network=self.test_network,
            detach=True,
            remove=True,
            name="network-test"
        )
        
        try:
            # Test DNS resolution within network
            result = test_container.exec_run("nslookup traefik")
            if result.exit_code == 0:
                print("✅ Internal DNS resolution works")
                return True
            else:
                print(f"❌ DNS resolution failed: {result.output.decode()}")
                return False
        finally:
            test_container.stop()
    
    def test_compose_validation(self):
        """Test that docker-compose files are valid."""
        print("Testing compose file validation...")
        
        # Test main compose file
        cmd = f"docker compose -f docker-compose.yml --env-file {self.test_env_file} config"
        result = self.run_command(cmd, check=False)
        
        if result is not None:
            print("✅ Main docker-compose.yml is valid")
            return True
        else:
            print("❌ Main docker-compose.yml validation failed")
            return False
    
    def test_volume_permissions(self):
        """Test that volumes are created with correct permissions."""
        print("Testing volume permissions...")
        
        try:
            # Create a test volume
            volume = self.client.volumes.create("test_homelab_volume")
            
            # Test container can write to volume
            container = self.client.containers.run(
                "alpine:latest",
                command="sh -c 'echo test > /data/test.txt && ls -la /data/'",
                volumes={"test_homelab_volume": {"bind": "/data", "mode": "rw"}},
                remove=True
            )
            
            print("✅ Volume permissions are correct")
            return True
            
        except Exception as e:
            print(f"❌ Volume permission test failed: {e}")
            return False
        finally:
            try:
                self.client.volumes.get("test_homelab_volume").remove()
            except:
                pass
    
    def cleanup(self):
        """Clean up test resources."""
        print("Cleaning up test resources...")
        
        # Stop all test containers
        cmd = f"docker compose -f docker-compose.yml --env-file {self.test_env_file} down -v"
        self.run_command(cmd, check=False)
        
        # Remove test containers
        try:
            for container in self.client.containers.list(all=True):
                if "test" in container.name.lower():
                    container.remove(force=True)
        except:
            pass
    
    def run_all_tests(self):
        """Run all integration tests."""
        print("🧪 Starting homelab integration tests...")
        
        tests = [
            ("Compose Validation", self.test_compose_validation),
            ("Volume Permissions", self.test_volume_permissions),
            ("Traefik Startup", self.test_traefik_startup),
            ("Service Networking", self.test_service_networking),
        ]
        
        results = []
        
        try:
            for test_name, test_func in tests:
                print(f"\n--- {test_name} ---")
                result = test_func()
                results.append((test_name, result))
                
                if not result:
                    print(f"❌ {test_name} failed")
                else:
                    print(f"✅ {test_name} passed")
        
        finally:
            self.cleanup()
        
        # Print summary
        print("\n" + "="*50)
        print("TEST SUMMARY")
        print("="*50)
        
        passed = sum(1 for _, result in results if result)
        total = len(results)
        
        for test_name, result in results:
            status = "✅ PASS" if result else "❌ FAIL"
            print(f"{test_name}: {status}")
        
        print(f"\nResults: {passed}/{total} tests passed")
        
        if passed == total:
            print("🎉 All tests passed!")
            return True
        else:
            print("💥 Some tests failed!")
            return False

def main():
    # Check if we're in CI environment
    if os.environ.get('CI'):
        print("Running in CI environment")
    
    # Create test environment file if it doesn't exist
    if not Path(".env.test").exists():
        print("Creating test environment file...")
        with open(".env.test", "w") as f:
            f.write("""DOMAIN=test.local
TZ=UTC
CF_EMAIL=test@example.com
CF_API_TOKEN=dummy-token
PIHOLE_PASSWORD=test123
KEYCLOAK_DB_USER=testuser
KEYCLOAK_DB_PASSWORD=testpass123
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=admin123
WATCHTOWER_NOTIFICATIONS=none
""")
    
    tester = HomelabTester()
    success = tester.run_all_tests()
    
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()
