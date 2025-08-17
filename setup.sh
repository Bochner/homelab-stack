#!/bin/bash

# Homelab Setup Script
# This script sets up a comprehensive homelab stack with Docker Compose

set -euo pipefail

# Configuration
HOMELAB_ROOT="/opt/homelab"
STACKS_ROOT="/opt/stacks"
BACKUP_DIR="/opt/homelab-backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Print banner
print_banner() {
    cat << "EOF"
    __  __                     __      __       _____ __             __  
   / / / /___  ____ ___  ___  / /___ _/ /_    / ___// /_____ ______/ /__
  / /_/ / __ \/ __ `__ \/ _ \/ / __ `/ __ \   \__ \/ __/ __ `/ ___/ //_/
 / __  / /_/ / / / / / /  __/ / /_/ / /_/ /  ___/ / /_/ /_/ / /__/ ,<   
/_/ /_/\____/_/ /_/ /_/\___/_/\__,_/_.___/  /____/\__/\__,_/\___/_/|_|  
                                                          

EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root for security reasons"
        log_info "Please run as a regular user with sudo privileges"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        log_info "Visit: https://docs.docker.com/engine/install/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose v2 is not installed or not working properly"
        log_info "Visit: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running or you don't have permissions"
        log_info "Try: sudo systemctl start docker && sudo usermod -aG docker $USER"
        exit 1
    fi
    
    # Check minimum Docker version (20.10+)
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' | cut -d. -f1,2)
    MIN_VERSION="20.10"
    if [ "$(printf '%s\n' "$MIN_VERSION" "$DOCKER_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
        log_error "Docker version $DOCKER_VERSION is too old. Minimum required: $MIN_VERSION"
        exit 1
    fi
    
    log_info "All prerequisites met ✓"
}

# Backup existing configuration
backup_existing() {
    if [ -d "$HOMELAB_ROOT" ]; then
        log_warn "Existing homelab configuration found"
        read -p "Do you want to backup existing configuration? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating backup at $BACKUP_DIR..."
            sudo cp -r "$HOMELAB_ROOT" "$BACKUP_DIR"
            log_info "Backup created successfully"
        fi
    fi
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."
    
    # Core directories
    sudo mkdir -p "$HOMELAB_ROOT"/{core,services,monitoring,management,backups,logs}
    sudo mkdir -p "$HOMELAB_ROOT"/core/{traefik,network}
    sudo mkdir -p "$HOMELAB_ROOT"/services/{pihole,keycloak,keycloak-db}
    sudo mkdir -p "$HOMELAB_ROOT"/monitoring/{uptime-kuma,watchtower}
    sudo mkdir -p "$HOMELAB_ROOT"/management/{dockge,homepage}
    sudo mkdir -p "$STACKS_ROOT"
    
    # Set ownership
    sudo chown -R "$USER:$USER" "$HOMELAB_ROOT"
    sudo chown -R "$USER:$USER" "$STACKS_ROOT"
    
    log_info "Directory structure created ✓"
}

# Create modular docker-compose files
create_core_network() {
    log_info "Creating core network configuration..."
    
    cat > "$HOMELAB_ROOT/core/network/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    name: homelab_net
    driver: bridge
    ipam:
      config:
        - subnet: 10.0.0.0/24
          gateway: 10.0.0.1
EOF
}

create_traefik_config() {
    log_info "Creating Traefik configuration..."
    
    # Main docker-compose for Traefik
    cat > "$HOMELAB_ROOT/core/traefik/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  traefik_certs:
    name: traefik_certs

services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    environment:
      - CF_API_EMAIL=${CF_EMAIL}
      - CF_API_KEY=${CF_API_TOKEN}
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certs:/letsencrypt
      - ./config/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./config/dynamic.yml:/etc/traefik/dynamic.yml:ro
    networks:
      homelab_net:
        ipv4_address: 10.0.0.2
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik.rule=Host(`traefik.${DOMAIN}`)"
      - "traefik.http.routers.traefik.entrypoints=websecure"
      - "traefik.http.routers.traefik.tls.certresolver=cloudflare"
      - "traefik.http.routers.traefik.tls.domains[0].main=${DOMAIN}"
      - "traefik.http.routers.traefik.tls.domains[0].sans=*.${DOMAIN}"
      - "traefik.http.routers.traefik.service=api@internal"
      - "traefik.http.routers.traefik.middlewares=auth@file"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    # Create config directory
    mkdir -p "$HOMELAB_ROOT/core/traefik/config"
    
    # Copy traefik configs
    cp ./traefik/traefik.yml "$HOMELAB_ROOT/core/traefik/config/"
    cp ./traefik/dynamic.yml "$HOMELAB_ROOT/core/traefik/config/"
}

create_service_configs() {
    log_info "Creating service configurations..."
    
    # Pi-hole
    cat > "$HOMELAB_ROOT/services/pihole/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  pihole_data:
    name: pihole_data
  pihole_dnsmasq:
    name: pihole_dnsmasq

services:
  pihole:
    image: pihole/pihole:latest
    container_name: pihole
    restart: unless-stopped
    hostname: pihole
    environment:
      TZ: ${TZ}
      WEBPASSWORD: ${PIHOLE_PASSWORD}
      PIHOLE_DNS_: 1.1.1.1;1.0.0.1
      DNSMASQ_LISTENING: all
      WEB_PORT: 8080
      VIRTUAL_HOST: pihole.${DOMAIN}
    volumes:
      - pihole_data:/etc/pihole
      - pihole_dnsmasq:/etc/dnsmasq.d
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    networks:
      homelab_net:
        ipv4_address: 10.0.0.3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pihole.rule=Host(`pihole.${DOMAIN}`)"
      - "traefik.http.routers.pihole.entrypoints=websecure"
      - "traefik.http.routers.pihole.tls.certresolver=cloudflare"
      - "traefik.http.services.pihole.loadbalancer.server.port=8080"
      - "traefik.http.routers.pihole.middlewares=security-headers@file"
    healthcheck:
      test: ["CMD", "dig", "+short", "+norecurse", "+retry=0", "@127.0.0.1", "pi.hole"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    # Keycloak Database
    cat > "$HOMELAB_ROOT/services/keycloak-db/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  keycloak_db_data:
    name: keycloak_db_data

services:
  keycloak-db:
    image: postgres:15-alpine
    container_name: keycloak-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: ${KEYCLOAK_DB_USER}
      POSTGRES_PASSWORD: ${KEYCLOAK_DB_PASSWORD}
    volumes:
      - keycloak_db_data:/var/lib/postgresql/data
    networks:
      homelab_net:
        ipv4_address: 10.0.0.4
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${KEYCLOAK_DB_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
EOF

    # Keycloak
    cat > "$HOMELAB_ROOT/services/keycloak/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

services:
  keycloak:
    image: quay.io/keycloak/keycloak:23.0
    container_name: keycloak
    restart: unless-stopped
    command: start
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
      KC_DB_USERNAME: ${KEYCLOAK_DB_USER}
      KC_DB_PASSWORD: ${KEYCLOAK_DB_PASSWORD}
      KC_HOSTNAME: keycloak.${DOMAIN}
      KC_HOSTNAME_STRICT_HTTPS: true
      KC_PROXY: edge
      KC_HTTP_ENABLED: true
      KEYCLOAK_ADMIN: ${KEYCLOAK_ADMIN_USER}
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD}
    networks:
      homelab_net:
        ipv4_address: 10.0.0.5
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.keycloak.rule=Host(`keycloak.${DOMAIN}`)"
      - "traefik.http.routers.keycloak.entrypoints=websecure"
      - "traefik.http.routers.keycloak.tls.certresolver=cloudflare"
      - "traefik.http.services.keycloak.loadbalancer.server.port=8080"
      - "traefik.http.routers.keycloak.middlewares=security-headers@file"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    # Create monitoring service configs
    create_monitoring_configs
    
    # Create management service configs
    create_management_configs
}

create_monitoring_configs() {
    # Uptime Kuma
    cat > "$HOMELAB_ROOT/monitoring/uptime-kuma/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  uptime_kuma_data:
    name: uptime_kuma_data

services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    volumes:
      - uptime_kuma_data:/app/data
    networks:
      homelab_net:
        ipv4_address: 10.0.0.7
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.uptime-kuma.rule=Host(`uptime.${DOMAIN}`)"
      - "traefik.http.routers.uptime-kuma.entrypoints=websecure"
      - "traefik.http.routers.uptime-kuma.tls.certresolver=cloudflare"
      - "traefik.http.services.uptime-kuma.loadbalancer.server.port=3001"
      - "traefik.http.routers.uptime-kuma.middlewares=security-headers@file"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    # Watchtower
    cat > "$HOMELAB_ROOT/monitoring/watchtower/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    environment:
      TZ: ${TZ}
      WATCHTOWER_CLEANUP: true
      WATCHTOWER_SCHEDULE: "0 0 4 * * *"  # 4 AM daily
      WATCHTOWER_NOTIFICATIONS: ${WATCHTOWER_NOTIFICATIONS:-none}
      WATCHTOWER_NOTIFICATION_EMAIL_FROM: ${WATCHTOWER_EMAIL_FROM:-}
      WATCHTOWER_NOTIFICATION_EMAIL_TO: ${WATCHTOWER_EMAIL_TO:-}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER: ${WATCHTOWER_EMAIL_SERVER:-}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PORT: ${WATCHTOWER_EMAIL_PORT:-}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_USER: ${WATCHTOWER_EMAIL_USER:-}
      WATCHTOWER_NOTIFICATION_EMAIL_SERVER_PASSWORD: ${WATCHTOWER_EMAIL_PASSWORD:-}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      homelab_net:
        ipv4_address: 10.0.0.6
EOF
}

create_management_configs() {
    # Dockge
    cat > "$HOMELAB_ROOT/management/dockge/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

volumes:
  dockge_data:
    name: dockge_data

services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    environment:
      DOCKGE_STACKS_DIR: /opt/stacks
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - dockge_data:/app/data
      - /opt/stacks:/opt/stacks
    networks:
      homelab_net:
        ipv4_address: 10.0.0.8
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dockge.rule=Host(`dockge.${DOMAIN}`)"
      - "traefik.http.routers.dockge.entrypoints=websecure"
      - "traefik.http.routers.dockge.tls.certresolver=cloudflare"
      - "traefik.http.services.dockge.loadbalancer.server.port=5001"
      - "traefik.http.routers.dockge.middlewares=auth@file,security-headers@file"
EOF

    # Homepage
    cat > "$HOMELAB_ROOT/management/homepage/docker-compose.yml" << 'EOF'
version: '3.9'

networks:
  homelab_net:
    external: true

services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    environment:
      TZ: ${TZ}
      HOMEPAGE_VAR_DOMAIN: ${DOMAIN}
    volumes:
      - ./config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      homelab_net:
        ipv4_address: 10.0.0.9
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.homepage.rule=Host(`${DOMAIN}`) || Host(`home.${DOMAIN}`)"
      - "traefik.http.routers.homepage.entrypoints=websecure"
      - "traefik.http.routers.homepage.tls.certresolver=cloudflare"
      - "traefik.http.services.homepage.loadbalancer.server.port=3000"
      - "traefik.http.routers.homepage.middlewares=security-headers@file"
EOF

    # Copy homepage configs
    mkdir -p "$HOMELAB_ROOT/management/homepage/config"
    cp -r ./homepage/* "$HOMELAB_ROOT/management/homepage/config/" 2>/dev/null || true
}

# Create management scripts
create_management_scripts() {
    log_info "Creating management scripts..."
    
    # Start all services
    cat > "$HOMELAB_ROOT/start-all.sh" << 'EOF'
#!/bin/bash
set -e

echo "Starting Homelab Services..."

# Load environment
source /opt/homelab/.env

# Start core services
echo "Starting core services..."
(cd /opt/homelab/core/network && docker compose up -d)
sleep 2
(cd /opt/homelab/core/traefik && docker compose up -d)

# Start services
echo "Starting application services..."
(cd /opt/homelab/services/keycloak-db && docker compose up -d)
sleep 5
(cd /opt/homelab/services/keycloak && docker compose up -d)
(cd /opt/homelab/services/pihole && docker compose up -d)

# Start monitoring
echo "Starting monitoring services..."
(cd /opt/homelab/monitoring/uptime-kuma && docker compose up -d)
(cd /opt/homelab/monitoring/watchtower && docker compose up -d)

# Start management
echo "Starting management services..."
(cd /opt/homelab/management/dockge && docker compose up -d)
(cd /opt/homelab/management/homepage && docker compose up -d)

echo "All services started!"
EOF

    # Stop all services
    cat > "$HOMELAB_ROOT/stop-all.sh" << 'EOF'
#!/bin/bash
set -e

echo "Stopping Homelab Services..."

# Stop in reverse order
(cd /opt/homelab/management/homepage && docker compose down)
(cd /opt/homelab/management/dockge && docker compose down)
(cd /opt/homelab/monitoring/watchtower && docker compose down)
(cd /opt/homelab/monitoring/uptime-kuma && docker compose down)
(cd /opt/homelab/services/pihole && docker compose down)
(cd /opt/homelab/services/keycloak && docker compose down)
(cd /opt/homelab/services/keycloak-db && docker compose down)
(cd /opt/homelab/core/traefik && docker compose down)

echo "All services stopped!"
EOF

    # Update service script
    cat > "$HOMELAB_ROOT/update-service.sh" << 'EOF'
#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <service-name>"
    echo "Available services: traefik, pihole, keycloak, uptime-kuma, dockge, homepage"
    exit 1
fi

SERVICE=$1
SERVICE_PATH=""

case $SERVICE in
    traefik)
        SERVICE_PATH="/opt/homelab/core/traefik"
        ;;
    pihole|keycloak|keycloak-db)
        SERVICE_PATH="/opt/homelab/services/$SERVICE"
        ;;
    uptime-kuma|watchtower)
        SERVICE_PATH="/opt/homelab/monitoring/$SERVICE"
        ;;
    dockge|homepage)
        SERVICE_PATH="/opt/homelab/management/$SERVICE"
        ;;
    *)
        echo "Unknown service: $SERVICE"
        exit 1
        ;;
esac

echo "Updating $SERVICE..."
cd "$SERVICE_PATH"
docker compose pull
docker compose up -d
echo "$SERVICE updated successfully!"
EOF

    # Health check script
    cat > "$HOMELAB_ROOT/health-check.sh" << 'EOF'
#!/bin/bash

echo "Homelab Health Check"
echo "===================="

# Check core services
echo -e "\nCore Services:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "traefik|network" || echo "None running"

echo -e "\nApplication Services:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "pihole|keycloak" || echo "None running"

echo -e "\nMonitoring Services:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "uptime-kuma|watchtower" || echo "None running"

echo -e "\nManagement Services:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "dockge|homepage" || echo "None running"

echo -e "\nUnhealthy Containers:"
docker ps --filter "health=unhealthy" --format "table {{.Names}}\t{{.Status}}" || echo "All healthy!"
EOF

    # Make scripts executable
    chmod +x "$HOMELAB_ROOT"/*.sh
}

# Copy environment file
setup_environment() {
    log_info "Setting up environment configuration..."
    
    if [ -f "$HOMELAB_ROOT/.env" ]; then
        log_warn ".env file already exists"
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing .env file"
            return
        fi
    fi
    
    cp .env.example "$HOMELAB_ROOT/.env"
    chmod 600 "$HOMELAB_ROOT/.env"
    
    log_warn "Please edit $HOMELAB_ROOT/.env with your configuration"
}

# Interactive setup wizard
setup_wizard() {
    log_info "Starting interactive setup wizard..."
    
    # Domain configuration
    read -p "Enter your domain (e.g., example.com): " DOMAIN
    sed -i "s/DOMAIN=.*/DOMAIN=$DOMAIN/" "$HOMELAB_ROOT/.env"
    
    # Timezone
    read -p "Enter your timezone (default: America/New_York): " TZ
    TZ=${TZ:-America/New_York}
    sed -i "s|TZ=.*|TZ=$TZ|" "$HOMELAB_ROOT/.env"
    
    # Cloudflare
    read -p "Enter your Cloudflare email: " CF_EMAIL
    sed -i "s/CF_EMAIL=.*/CF_EMAIL=$CF_EMAIL/" "$HOMELAB_ROOT/.env"
    
    read -sp "Enter your Cloudflare API token: " CF_TOKEN
    echo
    sed -i "s/CF_API_TOKEN=.*/CF_API_TOKEN=$CF_TOKEN/" "$HOMELAB_ROOT/.env"
    
    # Generate secure passwords
    log_info "Generating secure passwords..."
    PIHOLE_PASS=$(openssl rand -base64 32)
    KEYCLOAK_DB_PASS=$(openssl rand -base64 32)
    KEYCLOAK_ADMIN_PASS=$(openssl rand -base64 32)
    
    sed -i "s/PIHOLE_PASSWORD=.*/PIHOLE_PASSWORD=$PIHOLE_PASS/" "$HOMELAB_ROOT/.env"
    sed -i "s/KEYCLOAK_DB_USER=.*/KEYCLOAK_DB_USER=keycloak/" "$HOMELAB_ROOT/.env"
    sed -i "s/KEYCLOAK_DB_PASSWORD=.*/KEYCLOAK_DB_PASSWORD=$KEYCLOAK_DB_PASS/" "$HOMELAB_ROOT/.env"
    sed -i "s/KEYCLOAK_ADMIN_USER=.*/KEYCLOAK_ADMIN_USER=admin/" "$HOMELAB_ROOT/.env"
    sed -i "s/KEYCLOAK_ADMIN_PASSWORD=.*/KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASS/" "$HOMELAB_ROOT/.env"
    
    log_info "Configuration saved to $HOMELAB_ROOT/.env"
    log_warn "Passwords have been generated. Save them securely!"
    echo "Pi-hole Admin Password: $PIHOLE_PASS"
    echo "Keycloak Admin Password: $KEYCLOAK_ADMIN_PASS"
}

# Deploy services
deploy_services() {
    log_info "Deploying services..."
    
    # Check if .env is configured
    if grep -q "your-email@example.com" "$HOMELAB_ROOT/.env"; then
        log_error ".env file not configured!"
        log_info "Please run with --wizard flag or edit $HOMELAB_ROOT/.env manually"
        exit 1
    fi
    
    # Create Docker network
    log_info "Creating Docker network..."
    docker network create homelab_net --subnet=10.0.0.0/24 2>/dev/null || log_info "Network already exists"
    
    # Load environment variables
    source "$HOMELAB_ROOT/.env"
    export $(grep -v '^#' "$HOMELAB_ROOT/.env" | xargs)
    
    # Deploy services using the start script
    log_info "Starting all services..."
    bash "$HOMELAB_ROOT/start-all.sh"
    
    # Wait for services to be healthy
    log_info "Waiting for services to be healthy..."
    sleep 30
    
    # Run health check
    bash "$HOMELAB_ROOT/health-check.sh"
}

# Print completion message
print_completion() {
    echo ""
    log_info "✅ Homelab deployment complete!"
    echo ""
    # Load domain from environment
    source "$HOMELAB_ROOT/.env" 2>/dev/null || true
    echo "🌐 Access your services at:"
    echo "   Homepage: https://$DOMAIN or https://home.$DOMAIN"
    echo "   Traefik: https://traefik.$DOMAIN"
    echo "   Pi-hole: https://pihole.$DOMAIN"
    echo "   Keycloak: https://keycloak.$DOMAIN"
    echo "   Uptime Kuma: https://uptime.$DOMAIN"
    echo "   Dockge: https://dockge.$DOMAIN"
    echo ""
    echo "📝 Management commands:"
    echo "   Start all: $HOMELAB_ROOT/start-all.sh"
    echo "   Stop all: $HOMELAB_ROOT/stop-all.sh"
    echo "   Update service: $HOMELAB_ROOT/update-service.sh <service-name>"
    echo "   Health check: $HOMELAB_ROOT/health-check.sh"
    echo ""
    echo "📁 Service locations:"
    echo "   Core: $HOMELAB_ROOT/core/"
    echo "   Services: $HOMELAB_ROOT/services/"
    echo "   Monitoring: $HOMELAB_ROOT/monitoring/"
    echo "   Management: $HOMELAB_ROOT/management/"
    echo ""
    echo "📚 Documentation: $HOMELAB_ROOT/docs/"
}

# Main execution
main() {
    print_banner
    
    # Parse command line arguments
    WIZARD=false
    SKIP_DEPLOY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wizard|-w)
                WIZARD=true
                shift
                ;;
            --skip-deploy|-s)
                SKIP_DEPLOY=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --wizard, -w     Run interactive setup wizard"
                echo "  --skip-deploy    Skip service deployment"
                echo "  --help, -h       Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute setup steps
    check_prerequisites
    backup_existing
    create_directory_structure
    create_core_network
    create_traefik_config
    create_service_configs
    create_management_scripts
    setup_environment
    
    if [ "$WIZARD" = true ]; then
        setup_wizard
    fi
    
    if [ "$SKIP_DEPLOY" = false ]; then
        deploy_services
        print_completion
    else
        log_info "Skipping deployment. Run $HOMELAB_ROOT/start-all.sh when ready."
    fi
}

# Run main function
main "$@"