# Adding New Services to Homelab

This guide explains how to add new services to your homelab stack using the modular architecture.

## Quick Start Template

```yaml
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  service_data:
    name: service_data

services:
  myservice:
    image: myimage:latest
    container_name: myservice
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - service_data:/data
    networks:
      homelab_net:
        ipv4_address: 10.0.0.XX  # Choose unused IP
    labels:
      # Basic Traefik configuration
      - "traefik.enable=true"
      - "traefik.http.routers.myservice.rule=Host(`myservice.${DOMAIN}`)"
      - "traefik.http.routers.myservice.entrypoints=websecure"
      - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
      - "traefik.http.services.myservice.loadbalancer.server.port=80"
      
      # Optional: Add authentication
      - "traefik.http.routers.myservice.middlewares=auth@file"
      
      # Optional: Add security headers
      - "traefik.http.routers.myservice.middlewares=security-headers@file"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

## Step-by-Step Guide

### 1. Choose Service Category

Determine where your service belongs:
- `services/` - Main applications (databases, apps)
- `monitoring/` - Monitoring and alerting tools
- `management/` - Admin and management interfaces
- `media/` - Media servers (create if needed)

### 2. Create Service Directory

```bash
mkdir -p /opt/homelab/services/myservice
cd /opt/homelab/services/myservice
```

### 3. Create docker-compose.yml

Use the template above and modify:
- Container name and image
- Network IP address (check used IPs with `docker network inspect homelab_net`)
- Environment variables
- Volumes for persistent data
- Port configuration
- Health check endpoint

### 4. Configure Traefik Labels

#### Basic Setup
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myservice.rule=Host(`myservice.${DOMAIN}`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
  - "traefik.http.services.myservice.loadbalancer.server.port=80"
```

#### With Authentication
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myservice.rule=Host(`myservice.${DOMAIN}`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
  - "traefik.http.services.myservice.loadbalancer.server.port=80"
  - "traefik.http.routers.myservice.middlewares=auth@file,security-headers@file"
```

#### Path-Based Routing
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myservice.rule=Host(`${DOMAIN}`) && PathPrefix(`/myservice`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
  - "traefik.http.services.myservice.loadbalancer.server.port=80"
  - "traefik.http.middlewares.myservice-stripprefix.stripprefix.prefixes=/myservice"
  - "traefik.http.routers.myservice.middlewares=myservice-stripprefix"
```

### 5. Add to Homepage Dashboard

Edit `/opt/homelab/management/homepage/config/services.yaml`:

```yaml
- Developer Tools:
    - MyService:
        icon: myservice.svg
        href: https://myservice.{{HOMEPAGE_VAR_DOMAIN}}
        description: My awesome service
        widget:
          type: myservice
          url: https://myservice.{{HOMEPAGE_VAR_DOMAIN}}
          key: {{HOMEPAGE_VAR_MYSERVICE_KEY}}
```

### 6. Deploy the Service

```bash
# Deploy
cd /opt/homelab/services/myservice
docker compose up -d

# Check logs
docker compose logs -f

# Verify health
docker ps | grep myservice
```

## Common Service Patterns

### Database-Backed Service

```yaml
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  app_data:
    name: app_data
  db_data:
    name: app_db_data

services:
  app-db:
    image: postgres:15-alpine
    container_name: app-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: appdb
      POSTGRES_USER: ${APP_DB_USER}
      POSTGRES_PASSWORD: ${APP_DB_PASSWORD}
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      homelab_net:
        ipv4_address: 10.0.0.20
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${APP_DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: myapp:latest
    container_name: app
    restart: unless-stopped
    depends_on:
      app-db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgresql://${APP_DB_USER}:${APP_DB_PASSWORD}@app-db:5432/appdb
    volumes:
      - app_data:/data
    networks:
      homelab_net:
        ipv4_address: 10.0.0.21
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.${DOMAIN}`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls.certresolver=cloudflare"
      - "traefik.http.services.app.loadbalancer.server.port=3000"
```

### Media Server with Multiple Ports

```yaml
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  config:
    name: jellyfin_config
  media:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/media

services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - config:/config
      - media:/media:ro
    ports:
      - "8096:8096"  # HTTP
      - "8920:8920"  # HTTPS
      - "7359:7359/udp"  # Discovery
      - "1900:1900/udp"  # DLNA
    networks:
      homelab_net:
        ipv4_address: 10.0.0.30
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.jellyfin.rule=Host(`media.${DOMAIN}`)"
      - "traefik.http.routers.jellyfin.entrypoints=websecure"
      - "traefik.http.routers.jellyfin.tls.certresolver=cloudflare"
      - "traefik.http.services.jellyfin.loadbalancer.server.port=8096"
```

### Service with Custom Network Settings

```yaml
version: '3.9'

networks:
  homelab_net:
    external: true
  internal:
    internal: true

services:
  redis:
    image: redis:7-alpine
    container_name: app-redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    networks:
      - internal
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  app:
    image: myapp:latest
    container_name: app
    restart: unless-stopped
    depends_on:
      redis:
        condition: service_healthy
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
    networks:
      - homelab_net
      - internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`app.${DOMAIN}`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls.certresolver=cloudflare"
      - "traefik.http.services.app.loadbalancer.server.port=3000"
      - "traefik.docker.network=homelab_net"  # Specify network for Traefik
```

## Integration with Existing Services

### Keycloak SSO Integration

For services supporting OIDC/OAuth2:

```yaml
environment:
  - OAUTH2_CLIENT_ID=${SERVICE_OAUTH_CLIENT_ID}
  - OAUTH2_CLIENT_SECRET=${SERVICE_OAUTH_CLIENT_SECRET}
  - OAUTH2_ISSUER=https://keycloak.${DOMAIN}/realms/homelab
```

### Monitoring with Uptime Kuma

After deploying:
1. Access Uptime Kuma at https://uptime.yourdomain.com
2. Add new monitor
3. Set monitor type (HTTP/TCP/Docker)
4. Configure notifications

### Backup Integration

Add to backup script:
```bash
# Add to /opt/homelab/backup.sh
docker run --rm -v myservice_data:/source -v "$BACKUP_DIR":/backup alpine \
    tar -czf "/backup/myservice_data.tar.gz" -C /source .
```

## Troubleshooting

### Service Won't Start

1. Check logs: `docker compose logs -f`
2. Verify image exists: `docker pull myimage:latest`
3. Check port conflicts: `sudo netstat -tulpn | grep :80`
4. Verify environment variables in `.env`

### Traefik Not Routing

1. Check labels: `docker inspect myservice | grep -A 20 Labels`
2. Verify DNS: `dig myservice.yourdomain.com`
3. Check Traefik logs: `docker logs traefik`
4. Access Traefik dashboard

### Network Issues

1. Verify network: `docker network inspect homelab_net`
2. Check IP conflicts: Look for duplicate IPs
3. Test connectivity: `docker exec myservice ping google.com`

## Best Practices

1. **Always use volumes** for persistent data
2. **Set resource limits** for containers:
   ```yaml
   deploy:
     resources:
       limits:
         cpus: '0.5'
         memory: 512M
   ```

3. **Use health checks** for dependent services
4. **Document environment variables** in service README
5. **Test locally** before deploying to production
6. **Use specific image tags** instead of `latest`
7. **Implement logging** to centralized location

## Example Services

### Gitea (Git Server)
- Category: `services/`
- Port: 3000
- Features: Git hosting, CI/CD integration

### Nextcloud (File Storage)
- Category: `services/`
- Port: 80
- Features: File sync, calendar, contacts

### Grafana (Metrics Dashboard)
- Category: `monitoring/`
- Port: 3000
- Features: Data visualization, alerting

### Portainer (Docker Management)
- Category: `management/`
- Port: 9000
- Features: Container management, stack deployment

### Home Assistant (Home Automation)
- Category: `services/`
- Port: 8123
- Features: IoT device control, automations