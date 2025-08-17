# Homelab Stack

A comprehensive Docker Compose homelab deployment featuring Traefik reverse proxy, Cloudflare SSL certificates, Pi-hole DNS filtering, Keycloak authentication, and essential monitoring tools.

## 🏗️ Architecture

### Core Services
- **Traefik** (10.0.0.2) - Reverse proxy with automatic SSL certificates
- **Pi-hole** (10.0.0.3) - Network-wide ad blocking and DNS
- **Keycloak** (10.0.0.5) - Identity and access management
- **Watchtower** (10.0.0.6) - Automatic container updates
- **Uptime Kuma** (10.0.0.7) - Uptime monitoring
- **Dockge** (10.0.0.8) - Docker Compose management
- **Homepage** (10.0.0.9) - Dashboard and service overview

### Network Configuration
- **Subnet**: 10.0.0.0/24
- **Domain**: Configured via environment variable
- **SSL**: Cloudflare DNS challenge with wildcard certificates

## 🚀 Quick Start

### Prerequisites
- Ubuntu Server 20.04+ or Debian 11+ with Docker and Docker Compose v2 installed
- Domain registered with Cloudflare
- Cloudflare API token with DNS edit permissions

### Installation

```bash
# Clone the repository
git clone <this-repo> homelab-stack
cd homelab-stack

# Copy and configure environment variables
cp .env.example .env
nano .env  # Edit with your values

# Run setup script
chmod +x setup.sh
./setup.sh
```

## 📁 Repository Structure

```
homelab-stack/
├── docker-compose.yml      # Main service configuration
├── setup.sh               # Setup script
├── setup-v2.sh            # Advanced modular setup (future use)
├── .env.example           # Environment variables template
├── traefik/               # Traefik configuration
│   ├── traefik.yml       # Static configuration
│   └── dynamic.yml       # Dynamic configuration
├── homepage/              # Homepage dashboard configuration
│   ├── services.yaml     # Service definitions
│   ├── settings.yaml     # Homepage settings
│   └── docker.yaml       # Docker integration
├── templates/             # Service templates
│   └── docker-compose.template.yml
└── docs/                  # Documentation
    ├── README.md          # Detailed documentation
    ├── ADDING_SERVICES.md # Guide for adding services
    └── MIGRATION_GUIDE.md # Future migration guide
```

## 🔧 Configuration

### Environment Variables

Key variables in `.env`:

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Your domain name | `example.com` |
| `TZ` | Timezone | `America/New_York` |
| `CF_EMAIL` | Cloudflare email | `admin@example.com` |
| `CF_API_TOKEN` | Cloudflare API token | `your-api-token` |
| `PIHOLE_PASSWORD` | Pi-hole admin password | `secure-password` |
| `KEYCLOAK_ADMIN_PASSWORD` | Keycloak admin password | `secure-password` |

### Security Notes

1. **Change default credentials**: The Traefik dashboard uses basic auth. Generate a new password hash:
   ```bash
   echo $(htpasswd -nB admin) | sed -e s/\\$/\\$\\$/g
   ```
   Then update `traefik/dynamic.yml` with your hash.

2. **Use strong passwords**: All passwords in `.env` should be unique and secure.

3. **Keep secrets safe**: Never commit `.env` files to version control.

## 🛠️ Management

### Common Commands

```bash
# View logs
docker compose logs -f [service-name]

# Restart services
docker compose restart [service-name]

# Update services
docker compose pull && docker compose up -d

# Stop all services
docker compose down

# Remove all data (careful!)
docker compose down -v
```

### Adding New Services

See [docs/ADDING_SERVICES.md](docs/ADDING_SERVICES.md) for detailed instructions on adding new services to your stack.

## 🌐 Accessing Services

After deployment, access your services at:
- Homepage: `https://yourdomain.com` or `https://home.yourdomain.com`
- Traefik: `https://traefik.yourdomain.com` (requires auth)
- Pi-hole: `https://pihole.yourdomain.com`
- Keycloak: `https://keycloak.yourdomain.com`
- Uptime Kuma: `https://uptime.yourdomain.com`
- Dockge: `https://dockge.yourdomain.com` (requires auth)

## 🔒 Security Features

- Automatic SSL certificates via Cloudflare
- Security headers on all services
- Service isolation with Docker networks
- Optional basic authentication
- Regular automated updates via Watchtower

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

MIT License - see LICENSE file for details

---

**Need Help?** Check the [documentation](docs/README.md) or open an issue!