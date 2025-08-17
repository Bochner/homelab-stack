# Homelab Stack Makefile
# Provides convenient commands for development and deployment

.PHONY: help setup start stop restart status logs health update clean test lint security install-deps

# Default target
help: ## Show this help message
	@echo "Homelab Stack - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Environment Commands:"
	@echo "  setup                 Initial setup and configuration"
	@echo "  start                 Start all services"
	@echo "  stop                  Stop all services"
	@echo "  restart               Restart all services"
	@echo ""
	@echo "Monitoring Commands:"
	@echo "  status                Show service status"
	@echo "  logs                  Show logs for all services"
	@echo "  health                Run health checks"
	@echo ""
	@echo "Maintenance Commands:"
	@echo "  update                Update all services"
	@echo "  clean                 Clean up unused resources"
	@echo ""
	@echo "Development Commands:"
	@echo "  test                  Run all tests"
	@echo "  lint                  Run linting checks"
	@echo "  security              Run security audit"

# Environment setup
setup: ## Run initial setup
	@echo "🚀 Setting up homelab stack..."
	@chmod +x setup.sh scripts/*.sh
	@./setup.sh --wizard

install-deps: ## Install development dependencies
	@echo "📦 Installing development dependencies..."
	@pip3 install -r scripts/requirements.txt
	@pip3 install pre-commit
	@pre-commit install

# Service management
start: ## Start all services
	@echo "▶️  Starting all services..."
	@docker compose up -d
	@sleep 5
	@$(MAKE) status

stop: ## Stop all services
	@echo "⏹️  Stopping all services..."
	@docker compose down

restart: ## Restart all services
	@echo "🔄 Restarting all services..."
	@docker compose restart
	@sleep 5
	@$(MAKE) status

# Monitoring
status: ## Show service status
	@echo "📊 Service Status:"
	@docker compose ps

logs: ## Show logs for all services
	@echo "📋 Service Logs:"
	@docker compose logs --tail=50

logs-follow: ## Follow logs for all services
	@echo "📋 Following Service Logs (Ctrl+C to stop):"
	@docker compose logs -f

health: ## Run comprehensive health checks
	@echo "🏥 Running health checks..."
	@python3 scripts/health_check.py

# Maintenance
update: ## Update all services
	@echo "⬆️  Updating all services..."
	@docker compose pull
	@docker compose up -d
	@$(MAKE) health

clean: ## Clean up unused Docker resources
	@echo "🧹 Cleaning up unused resources..."
	@docker system prune -f
	@docker volume prune -f
	@docker network prune -f

backup: ## Create backup of configuration
	@echo "💾 Creating backup..."
	@mkdir -p backups
	@tar -czf backups/homelab-backup-$(shell date +%Y%m%d-%H%M%S).tar.gz \
		--exclude=volumes --exclude=data --exclude=.git \
		.env traefik/ homepage/ docs/ scripts/ docker-compose.yml
	@echo "✅ Backup created in backups/ directory"

# Development and testing
test: ## Run all tests
	@echo "🧪 Running tests..."
	@python3 scripts/test_integration.py

test-compose: ## Validate Docker Compose files
	@echo "🔍 Validating Docker Compose files..."
	@./scripts/validate_compose.sh

test-env: ## Validate environment configuration
	@echo "🔍 Validating environment configuration..."
	@./scripts/validate_env_example.sh

lint: ## Run linting checks
	@echo "🔍 Running linting checks..."
	@if command -v yamllint >/dev/null 2>&1; then \
		yamllint .; \
	else \
		echo "⚠️  yamllint not installed, skipping YAML linting"; \
	fi
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -name "*.sh" -exec shellcheck {} \; ; \
	else \
		echo "⚠️  shellcheck not installed, skipping shell script linting"; \
	fi
	@if python3 -c "import flake8" 2>/dev/null; then \
		python3 -m flake8 scripts/; \
	else \
		echo "⚠️  flake8 not installed, skipping Python linting"; \
	fi
	@if python3 -c "import black" 2>/dev/null; then \
		python3 -m black --check scripts/; \
	else \
		echo "⚠️  black not installed, skipping Python formatting checks"; \
	fi

lint-fix: ## Fix linting issues automatically
	@echo "🔧 Fixing linting issues..."
	@python3 -m black scripts/
	@python3 -m isort scripts/

security: ## Run security audit
	@echo "🔒 Running security audit..."
	@HOMELAB_MODE=true python3 scripts/security_audit.py

security-scan: ## Run vulnerability scans
	@echo "🔍 Running vulnerability scans..."
	@docker run --rm -v "$(PWD):/src" aquasec/trivy fs /src

# Service-specific commands
traefik-logs: ## Show Traefik logs
	@docker compose logs -f traefik

pihole-logs: ## Show Pi-hole logs
	@docker compose logs -f pihole

keycloak-logs: ## Show Keycloak logs
	@docker compose logs -f keycloak

homepage-logs: ## Show Homepage logs
	@docker compose logs -f homepage

# Network and debugging
network-info: ## Show network information
	@echo "🌐 Network Information:"
	@docker network inspect homelab_net 2>/dev/null || echo "Network not found"

container-info: ## Show detailed container information
	@echo "📦 Container Information:"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

debug: ## Run debugging checks
	@echo "🐛 Debug Information:"
	@echo "Docker version:"
	@docker --version
	@echo ""
	@echo "Docker Compose version:"
	@docker compose version
	@echo ""
	@echo "Available disk space:"
	@df -h . | tail -1
	@echo ""
	@echo "Memory usage:"
	@free -h 2>/dev/null || vm_stat
	@echo ""
	@$(MAKE) network-info
	@$(MAKE) container-info

# Advanced operations
migrate: ## Run database migrations (if needed)
	@echo "🔄 Running migrations..."
	@docker compose exec -T keycloak-db pg_isready || echo "Database not ready"

shell-traefik: ## Open shell in Traefik container
	@docker compose exec traefik sh

shell-pihole: ## Open shell in Pi-hole container
	@docker compose exec pihole bash

shell-keycloak: ## Open shell in Keycloak container
	@docker compose exec keycloak bash

# Quick service management
traefik: ## Start only Traefik
	@docker compose up -d traefik

pihole: ## Start only Pi-hole
	@docker compose up -d pihole

keycloak: ## Start only Keycloak
	@docker compose up -d keycloak-db keycloak

homepage: ## Start only Homepage
	@docker compose up -d homepage

# Configuration helpers
env-check: ## Check environment configuration
	@echo "🔍 Checking environment configuration..."
	@if [ ! -f .env.example ]; then \
		echo "❌ .env.example file not found."; \
		exit 1; \
	fi
	@echo "✅ Environment example file exists"
	@if [ -f .env ]; then \
		echo "✅ Environment file exists"; \
		grep -q "DOMAIN=" .env && echo "✅ Domain configured" || echo "❌ Domain not configured"; \
		grep -q "CF_API_TOKEN=" .env && echo "✅ Cloudflare token configured" || echo "❌ Cloudflare token not configured"; \
	else \
		echo "ℹ️  .env file not found (copy from .env.example and configure)"; \
	fi

generate-passwords: ## Generate secure passwords for services
	@echo "🔐 Generating secure passwords..."
	@echo "PIHOLE_PASSWORD=$$(openssl rand -base64 32)"
	@echo "KEYCLOAK_DB_PASSWORD=$$(openssl rand -base64 32)"
	@echo "KEYCLOAK_ADMIN_PASSWORD=$$(openssl rand -base64 32)"
	@echo ""
	@echo "Copy these to your .env file"

# Documentation
docs: ## Open documentation
	@echo "📚 Opening documentation..."
	@open README.md || xdg-open README.md || echo "Please open README.md manually"

docs-serve: ## Serve documentation locally (if MkDocs is installed)
	@if command -v mkdocs >/dev/null 2>&1; then \
		mkdocs serve; \
	else \
		echo "MkDocs not installed. Install with: pip install mkdocs"; \
	fi

# Git hooks and pre-commit
pre-commit: ## Run pre-commit hooks
	@pre-commit run --all-files

pre-commit-update: ## Update pre-commit hooks
	@pre-commit autoupdate

# CI/CD helpers
ci-test: ## Run CI tests locally
	@echo "🚀 Running CI tests locally..."
	@$(MAKE) test-compose
	@$(MAKE) test-env
	@$(MAKE) security
	@$(MAKE) lint

validate: ## Validate entire stack
	@echo "✅ Validating homelab stack..."
	@$(MAKE) test-compose
	@$(MAKE) test-env
	@$(MAKE) env-check
	@echo "✅ All validations passed!"

# Default environment variables for make
export COMPOSE_PROJECT_NAME ?= homelab
export DOCKER_BUILDKIT ?= 1
export COMPOSE_DOCKER_CLI_BUILD ?= 1
