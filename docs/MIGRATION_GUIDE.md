# Migration Guide: Future Modular Architecture

> **Note**: This guide is for future reference when migrating to a modular architecture. The current implementation uses a single docker-compose.yml file for simplicity.

## Overview

This guide will help migrate from the current single docker-compose.yml setup to a future modular architecture where each service has its own directory and configuration.

## Future Benefits

1. **Independent Service Management**: Update/restart services without affecting others
2. **Better Organization**: Clear separation of concerns
3. **Easier Scaling**: Add new services without modifying core files
4. **Improved Security**: Isolated configurations and secrets
5. **Simpler Troubleshooting**: Service-specific logs and configs

## Current Architecture

The current setup uses a single `docker-compose.yml` file containing all services. This approach:
- ✅ Simple to understand and manage
- ✅ Easy to deploy with one command
- ✅ All configuration in one place
- ❌ Requires restarting all services for updates
- ❌ Can become complex with many services

## Future Modular Architecture

The future modular structure would organize services like:

```bash
# Create backup directory
sudo mkdir -p /opt/homelab-backup-$(date +%Y%m%d)

# Backup current setup
sudo cp -r /opt/homelab /opt/homelab-backup-$(date +%Y%m%d)/

# Backup Docker volumes
for volume in $(docker volume ls -q); do
    docker run --rm -v "$volume":/source -v /opt/homelab-backup-$(date +%Y%m%d):/backup alpine \
        tar -czf "/backup/${volume}.tar.gz" -C /source .
done

# Save running container list
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > /opt/homelab-backup-$(date +%Y%m%d)/containers.txt
```

### Step 2: Stop Current Services

```bash
cd /opt/homelab
docker compose down

# Verify all stopped
docker ps
```

### Step 3: Install New Setup

```bash
# Clone new setup
cd ~
git clone <repository> homelab-stack-new
cd homelab-stack-new

# Run setup script in skip-deploy mode
chmod +x setup-v2.sh
./setup-v2.sh --skip-deploy
```

### Step 4: Migrate Configuration

```bash
# Copy .env file
cp /opt/homelab-backup-*/homelab/.env /opt/homelab/.env

# Verify environment variables
grep -v '^#' /opt/homelab/.env | grep -v '^$'
```

### Step 5: Migrate Service Data

The new setup uses the same volume names, so data should persist. Verify volumes:

```bash
# List existing volumes
docker volume ls | grep -E "traefik|pihole|keycloak|uptime|dockge|homepage"

# Verify volume data
docker run --rm -v pihole_data:/data alpine ls -la /data
```

### Step 6: Migrate Custom Configurations

#### Traefik
```bash
# Copy custom certificates (if any)
cp /opt/homelab-backup-*/homelab/traefik/acme.json /opt/homelab/core/traefik/

# Copy custom dynamic configuration
cp /opt/homelab-backup-*/homelab/traefik/dynamic.yml /opt/homelab/core/traefik/config/

# Set permissions
chmod 600 /opt/homelab/core/traefik/acme.json
```

#### Homepage
```bash
# Copy homepage configuration
cp -r /opt/homelab-backup-*/homelab/homepage/* /opt/homelab/management/homepage/config/
```

### Step 7: Start Services Individually

Start services one by one to verify each works:

```bash
# Start network
cd /opt/homelab/core/network
docker compose up -d

# Start Traefik
cd /opt/homelab/core/traefik
docker compose up -d
docker logs -f traefik  # Check for errors

# Start Pi-hole
cd /opt/homelab/services/pihole
docker compose up -d
docker logs -f pihole

# Continue with other services...
```

### Step 8: Verify Services

```bash
# Run health check
/opt/homelab/health-check.sh

# Check web access
curl -I https://traefik.yourdomain.com
curl -I https://pihole.yourdomain.com

# Check DNS resolution
dig @localhost google.com
```

### Step 9: Update DNS and Documentation

1. Update any hardcoded IPs or DNS entries
2. Update documentation with new paths
3. Update backup scripts
4. Update monitoring configurations

## Rollback Procedure

If issues occur, rollback to the original setup:

```bash
# Stop new services
/opt/homelab/stop-all.sh

# Restore original setup
sudo mv /opt/homelab /opt/homelab-failed
sudo cp -r /opt/homelab-backup-*/homelab /opt/homelab

# Start original services
cd /opt/homelab
docker compose up -d
```

## Post-Migration Tasks

### 1. Update Backup Scripts

Replace old backup script with:

```bash
#!/bin/bash
# New modular backup script
BACKUP_DIR="/opt/homelab/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup all service configurations
for service_dir in /opt/homelab/{core,services,monitoring,management}/*; do
    if [ -d "$service_dir" ]; then
        service_name=$(basename "$service_dir")
        cp -r "$service_dir" "$BACKUP_DIR/"
    fi
done

# Backup volumes
for volume in $(docker volume ls -q | grep -E "pihole|keycloak|uptime|dockge|homepage|traefik"); do
    docker run --rm -v "$volume":/source -v "$BACKUP_DIR":/backup alpine \
        tar -czf "/backup/${volume}.tar.gz" -C /source .
done
```

### 2. Update Monitoring

Add new health checks in Uptime Kuma for modular setup:
- Individual service endpoints
- Docker container health
- Disk space monitoring

### 3. Document Custom Services

For any custom services in the old setup:

1. Create new directory: `/opt/homelab/services/custom-service/`
2. Create `docker-compose.yml` using the template
3. Add to start/stop scripts
4. Document in service README

## Troubleshooting Migration Issues

### Services Can't Communicate

**Issue**: Services can't find each other
**Solution**: Ensure all services are on `homelab_net` network

```bash
docker network inspect homelab_net
```

### Port Conflicts

**Issue**: Port already in use errors
**Solution**: Check for services still running from old setup

```bash
sudo netstat -tulpn | grep -E "80|443|53"
docker ps -a  # Show all containers including stopped
```

### Missing Data

**Issue**: Service data not showing up
**Solution**: Verify volume names match

```bash
# Old setup
docker volume inspect pihole_data

# New setup
cd /opt/homelab/services/pihole
docker compose config | grep -A5 volumes
```

### SSL Certificate Issues

**Issue**: Invalid certificates after migration
**Solution**: Force certificate renewal

```bash
# Remove old certificates
rm /opt/homelab/core/traefik/acme.json

# Restart Traefik
cd /opt/homelab/core/traefik
docker compose restart

# Monitor logs
docker logs -f traefik
```

## Advantages After Migration

1. **Selective Updates**: Update individual services without full stack restart
2. **Service Isolation**: Issues in one service don't affect others
3. **Easier Testing**: Test new services in isolation
4. **Better Resource Management**: Set limits per service
5. **Cleaner Logs**: Service-specific log viewing
6. **Simplified Scaling**: Add services without modifying core

## Next Steps

1. **Explore New Features**
   - Use `/opt/homelab/update-service.sh` for updates
   - Try adding new services with templates
   - Implement service-specific backups

2. **Optimize Configuration**
   - Add resource limits to services
   - Configure service-specific logging
   - Implement health checks

3. **Enhance Security**
   - Review and update passwords
   - Enable 2FA where possible
   - Audit network exposure

## Support

If you encounter issues during migration:

1. Check service logs: `docker logs <service-name>`
2. Review this guide's troubleshooting section
3. Consult the main documentation
4. Keep the backup until migration is verified stable