# Homelab Stack Documentation

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Configuration](#configuration)
6. [Service Documentation](#service-documentation)
7. [Management](#management)
8. [Troubleshooting](#troubleshooting)
9. [Security](#security)
10. [Backup and Recovery](#backup-and-recovery)
11. [Contributing](#contributing)

## Overview

This homelab stack provides a production-ready, self-hosted infrastructure with:

- **Reverse Proxy**: Traefik with automatic SSL certificates
- **DNS Management**: Pi-hole for network-wide ad blocking
- **Authentication**: Keycloak for Single Sign-On (SSO)
- **Monitoring**: Uptime Kuma for service monitoring
- **Management**: Dockge for Docker Compose management
- **Dashboard**: Homepage for centralized access

### Key Features

- 🔒 **Secure by Default**: SSL everywhere, proper authentication
- 📦 **Modular Architecture**: Each service in its own directory
- 🔄 **Easy Updates**: Individual service updates without downtime
- 📊 **Comprehensive Monitoring**: Health checks and uptime tracking
- 🚀 **Simple Deployment**: Interactive setup wizard
- 📱 **Mobile Friendly**: All services work on mobile devices

## Architecture

### Directory Structure

```
/opt/homelab/
├── core/                    # Core infrastructure
│   ├── traefik/            # Reverse proxy
│   └── network/            # Docker network configuration
├── services/               # Application services
│   ├── pihole/            # DNS and ad-blocking
│   ├── keycloak/          # Authentication
│   └── keycloak-db/       # Keycloak database
├── monitoring/             # Monitoring services
│   ├── uptime-kuma/       # Uptime monitoring
│   └── watchtower/        # Automatic updates
├── management/             # Management tools
│   ├── dockge/            # Docker Compose UI
│   └── homepage/          # Dashboard
├── backups/               # Backup storage
├── logs/                  # Centralized logs
└── docs/                  # Documentation

/opt/stacks/               # Additional service stacks (managed by Dockge)
```

### Network Architecture

```
Docker Network: homelab_net (10.0.0.0/24)

┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
             ┌──────────────┐
             │  Cloudflare  │ (DNS & SSL)
             └──────┬───────┘
                    │
                    ▼
            ┌───────────────┐
            │    Traefik    │ 10.0.0.2
            │ (Reverse Proxy)│
            └───────┬───────┘
                    │
    ┌───────────────┼───────────────┬──────────────┐
    │               │               │              │
    ▼               ▼               ▼              ▼
┌─────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ Pi-hole │   │ Keycloak │   │  Uptime  │   │ Homepage │
│10.0.0.3 │   │ 10.0.0.5 │   │  Kuma    │   │ 10.0.0.9 │
└─────────┘   └──────────┘   │ 10.0.0.7 │   └──────────┘
                              └──────────┘
```

## Prerequisites

### System Requirements

- **OS**: Ubuntu 20.04+ or Debian 11+
- **CPU**: 2+ cores recommended
- **RAM**: 4GB minimum, 8GB recommended
- **Storage**: 20GB minimum, 50GB recommended
- **Network**: Static IP recommended

### Software Requirements

- Docker 20.10+
- Docker Compose
- Git
- sudo privileges

### Domain Requirements

- Domain registered with Cloudflare
- Cloudflare API token with DNS edit permissions

## Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/homelab-stack.git
cd homelab-stack

# Run the setup wizard
chmod +x setup.sh
./setup.sh --wizard
```

### Manual Installation

1. **Prepare Environment**
   ```bash
   # Copy and edit environment file
   cp .env.example /opt/homelab/.env
   nano /opt/homelab/.env
   ```

2. **Run Setup**
   ```bash
   # Run setup without wizard
./setup.sh
   ```

3. **Verify Installation**
   ```bash
   # Check service health
   /opt/homelab/health-check.sh
   ```

## Configuration

### Environment Variables

Key variables in `/opt/homelab/.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Your domain name | `example.com` |
| `TZ` | Timezone | `America/New_York` |
| `CF_EMAIL` | Cloudflare email | `admin@example.com` |
| `CF_API_TOKEN` | Cloudflare API token | `your-api-token` |
| `PIHOLE_PASSWORD` | Pi-hole admin password | `secure-password` |
| `KEYCLOAK_DB_USER` | Keycloak database user | `keycloak` |
| `KEYCLOAK_DB_PASSWORD` | Keycloak database password | `secure-db-password` |
| `KEYCLOAK_ADMIN_USER` | Keycloak admin username | `admin` |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password | `secure-password` |
| `WATCHTOWER_NOTIFICATIONS` | Email notifications (optional) | `none` or `email` |

### Service Ports

| Service | Internal Port | External Port | Protocol |
|---------|--------------|---------------|----------|
| Traefik | 80, 443 | 80, 443 | TCP |
| Pi-hole | 53, 8080 | 53 | TCP/UDP |
| Keycloak | 8080 | - | TCP |
| Uptime Kuma | 3001 | - | TCP |
| Dockge | 5001 | - | TCP |
| Homepage | 3000 | - | TCP |

## Service Documentation

### Traefik

**Purpose**: Reverse proxy with automatic SSL certificates

**Access**: https://traefik.yourdomain.com

**Features**:
- Automatic SSL via Cloudflare DNS challenge
- Wildcard certificate support
- Built-in security headers
- Rate limiting

**Configuration**:
- Main config: `/opt/homelab/core/traefik/config/traefik.yml`
- Dynamic config: `/opt/homelab/core/traefik/config/dynamic.yml`

### Pi-hole

**Purpose**: Network-wide ad blocking and DNS management

**Access**: https://pihole.yourdomain.com

**Features**:
- DNS-level ad blocking
- Custom blocklists
- DHCP server (optional)
- Query logging and statistics

**Initial Setup**:
1. Access Pi-hole admin panel
2. Configure upstream DNS servers
3. Add custom blocklists
4. Configure client devices to use Pi-hole DNS

### Keycloak

**Purpose**: Identity and Access Management (IAM)

**Access**: https://keycloak.yourdomain.com

**Features**:
- Single Sign-On (SSO)
- Multi-factor authentication
- User federation
- Social login integration

**Initial Setup**:
1. Login with admin credentials
2. Create a new realm
3. Configure identity providers
4. Set up clients for your applications

### Uptime Kuma

**Purpose**: Service monitoring and alerting

**Access**: https://uptime.yourdomain.com

**Features**:
- HTTP(S) monitoring
- TCP port monitoring
- Docker container monitoring
- Multiple notification channels

**Initial Setup**:
1. Create admin account on first access
2. Add monitors for each service
3. Configure notification channels
4. Set up status pages

### Dockge

**Purpose**: Docker Compose stack management

**Access**: https://dockge.yourdomain.com

**Features**:
- Web-based Docker Compose editor
- Real-time logs
- Container management
- Stack templates

**Usage**:
1. Create new stacks in `/opt/stacks/`
2. Use the web UI to manage containers
3. Import existing docker-compose files

### Homepage

**Purpose**: Centralized dashboard

**Access**: https://yourdomain.com or https://home.yourdomain.com

**Features**:
- Service bookmarks
- Docker integration
- Weather widget
- Search providers

**Configuration**:
- Services: `/opt/homelab/management/homepage/config/services.yaml`
- Settings: `/opt/homelab/management/homepage/config/settings.yaml`
- Docker: `/opt/homelab/management/homepage/config/docker.yaml`

## Management

### Starting Services

```bash
# Start all services
/opt/homelab/start-all.sh

# Start individual service
cd /opt/homelab/services/pihole
docker compose up -d
```

### Stopping Services

```bash
# Stop all services
/opt/homelab/stop-all.sh

# Stop individual service
cd /opt/homelab/services/pihole
docker compose down
```

### Updating Services

```bash
# Update individual service
/opt/homelab/update-service.sh pihole

# Update all services manually
cd /opt/homelab/services/pihole
docker compose pull
docker compose up -d
```

### Viewing Logs

```bash
# View all logs
cd /opt/homelab/services/pihole
docker compose logs -f

# View specific container logs
docker logs -f pihole
```

### Health Checks

```bash
# Run health check script
/opt/homelab/health-check.sh

# Check individual service
docker ps | grep pihole
docker inspect pihole | grep Health
```

## Troubleshooting

### Common Issues

#### 1. Services Not Accessible

**Symptoms**: Can't access services via domain

**Solutions**:
- Check DNS propagation: `dig yourdomain.com`
- Verify Traefik is running: `docker ps | grep traefik`
- Check Traefik logs: `docker logs traefik`
- Ensure ports 80/443 are open in firewall

#### 2. SSL Certificate Issues

**Symptoms**: SSL errors or warnings

**Solutions**:
- Check Cloudflare API token permissions
- Verify domain is proxied through Cloudflare
- Check acme.json permissions: `ls -la /opt/homelab/core/traefik/acme.json`
- Review Traefik logs for ACME errors

#### 3. Container Startup Failures

**Symptoms**: Containers constantly restarting

**Solutions**:
- Check container logs: `docker logs <container-name>`
- Verify environment variables in `.env`
- Check disk space: `df -h`
- Ensure no port conflicts: `sudo netstat -tulpn`

#### 4. Network Connectivity Issues

**Symptoms**: Containers can't communicate

**Solutions**:
- Verify Docker network exists: `docker network ls`
- Check container network assignment: `docker inspect <container>`
- Restart Docker daemon: `sudo systemctl restart docker`

### Debug Mode

Enable debug logging in Traefik:
```yaml
# /opt/homelab/core/traefik/config/traefik.yml
log:
  level: DEBUG
```

### Recovery Procedures

#### Restore from Backup

```bash
# Stop all services
/opt/homelab/stop-all.sh

# Restore backup
sudo cp -r /opt/homelab-backup-* /opt/homelab

# Start services
/opt/homelab/start-all.sh
```

#### Reset Individual Service

```bash
# Stop service
cd /opt/homelab/services/pihole
docker compose down

# Remove volumes (data loss!)
docker volume rm pihole_data pihole_dnsmasq

# Recreate service
docker compose up -d
```

## Security

### Best Practices

1. **Regular Updates**
   - Enable Watchtower for automatic updates
   - Review update logs regularly
   - Test updates in staging first

2. **Strong Passwords**
   - Use generated passwords from setup wizard
   - Store passwords in password manager
   - Enable 2FA where possible

3. **Network Security**
   - Use firewall (ufw/iptables)
   - Limit SSH access
   - Regular security audits

4. **SSL/TLS**
   - Always use HTTPS
   - Keep certificates updated
   - Use strong cipher suites

### Firewall Configuration

```bash
# Basic UFW setup
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw allow 53        # DNS
sudo ufw enable
```

### Security Headers

Configured in `/opt/homelab/core/traefik/config/dynamic.yml`:
- Strict-Transport-Security
- X-Content-Type-Options
- X-Frame-Options
- Content-Security-Policy

## Backup and Recovery

### Automated Backups

Create a backup script:

```bash
#!/bin/bash
# /opt/homelab/backup.sh

BACKUP_DIR="/opt/homelab/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup configurations
cp -r /opt/homelab/*.env "$BACKUP_DIR/"
cp -r /opt/homelab/*/config "$BACKUP_DIR/"

# Backup Docker volumes
for volume in $(docker volume ls -q | grep -E "pihole|keycloak|uptime"); do
    docker run --rm -v "$volume":/source -v "$BACKUP_DIR":/backup alpine \
        tar -czf "/backup/${volume}.tar.gz" -C /source .
done

# Cleanup old backups (keep last 7 days)
find /opt/homelab/backups -type d -mtime +7 -exec rm -rf {} +
```

### Schedule Backups

```bash
# Add to crontab
0 2 * * * /opt/homelab/backup.sh
```

### Restore Procedures

1. **Configuration Restore**
   ```bash
   cp /opt/homelab/backups/20240101-020000/.env /opt/homelab/
   ```

2. **Volume Restore**
   ```bash
   docker run --rm -v pihole_data:/target -v /opt/homelab/backups/20240101-020000:/backup alpine \
       tar -xzf /backup/pihole_data.tar.gz -C /target
   ```

## Contributing

### Adding New Services

1. **Create Service Directory**
   ```bash
   mkdir -p /opt/homelab/services/newservice
   ```

2. **Create docker-compose.yml**
   ```yaml
   version: '3.9'
   
   networks:
     homelab_net:
       external: true
   
   services:
     newservice:
       image: yourimage:latest
       container_name: newservice
       restart: unless-stopped
       networks:
         - homelab_net
       labels:
         - "traefik.enable=true"
         - "traefik.http.routers.newservice.rule=Host(`newservice.${DOMAIN}`)"
         - "traefik.http.routers.newservice.entrypoints=websecure"
         - "traefik.http.routers.newservice.tls.certresolver=cloudflare"
   ```

3. **Update Documentation**
   - Add service to this README
   - Create service-specific documentation
   - Update network diagram if needed

### Development Workflow

1. **Test Locally**
   ```bash
   docker compose -f docker-compose.dev.yml up
   ```

2. **Validate Configuration**
   ```bash
   docker compose config
   ```

3. **Deploy to Production**
   ```bash
   docker compose up -d
   ```

## Support

### Resources

- [Docker Documentation](https://docs.docker.com/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)

### Community

- GitHub Issues: Report bugs and request features
- Discord: Join our community server
- Wiki: Contribute to documentation

### Professional Support

For enterprise deployments or custom configurations, contact: support@example.com

---

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Traefik team for the amazing reverse proxy
- Pi-hole community for ad-blocking excellence
- All open-source contributors

---

Last Updated: January 2024