#!/bin/bash
# Validate Docker Compose files for syntax and best practices

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if docker compose is available
if ! command -v docker &> /dev/null; then
    print_status "$RED" "❌ Docker is not installed or not in PATH"
    exit 1
fi

# Create temporary .env file for validation if it doesn't exist
create_temp_env() {
    if [ ! -f ".env" ] && [ ! -f ".env.test" ]; then
        print_status "$YELLOW" "⚠️  Creating temporary .env file for validation"
        cat > .env.temp << EOF
DOMAIN=test.example.com
TZ=UTC
CF_EMAIL=test@example.com
CF_API_TOKEN=dummy-token
PIHOLE_PASSWORD=test123
KEYCLOAK_DB_USER=testuser
KEYCLOAK_DB_PASSWORD=testpass123
KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=admin123
WATCHTOWER_NOTIFICATIONS=none
EOF
        export USE_TEMP_ENV=true
    fi
}

# Clean up temporary files
cleanup() {
    if [ "${USE_TEMP_ENV:-}" = "true" ]; then
        rm -f .env.temp
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Main validation function
validate_compose_file() {
    local compose_file=$1
    local env_file=${2:-".env"}

    if [ "${USE_TEMP_ENV:-}" = "true" ]; then
        env_file=".env.temp"
    fi

    print_status "$YELLOW" "🔍 Validating ${compose_file}..."

    # Check if file exists
    if [ ! -f "$compose_file" ]; then
        print_status "$RED" "❌ File not found: $compose_file"
        return 1
    fi

    # Validate YAML syntax
    if ! docker compose -f "$compose_file" config >/dev/null 2>&1; then
        print_status "$RED" "❌ Invalid YAML syntax in $compose_file"
        docker compose -f "$compose_file" config 2>&1 | head -10
        return 1
    fi

    # Validate with environment file if available
    if [ -f "$env_file" ]; then
        if ! docker compose -f "$compose_file" --env-file "$env_file" config >/dev/null 2>&1; then
            print_status "$RED" "❌ Validation failed with environment file: $compose_file"
            docker compose -f "$compose_file" --env-file "$env_file" config 2>&1 | head -10
            return 1
        fi
    fi

    # Check for common issues
    check_compose_best_practices "$compose_file"

    print_status "$GREEN" "✅ $compose_file is valid"
    return 0
}

# Check Docker Compose best practices
check_compose_best_practices() {
    local compose_file=$1
    local warnings=0

    # Check for latest tags
    if grep -q ":latest" "$compose_file"; then
        print_status "$YELLOW" "⚠️  Warning: Found 'latest' tags in $compose_file (consider pinning versions)"
        grep -n ":latest" "$compose_file" | head -3
        ((warnings++))
    fi

    # Check for missing restart policies
    if ! grep -q "restart:" "$compose_file"; then
        print_status "$YELLOW" "⚠️  Warning: No restart policies found in $compose_file"
        ((warnings++))
    fi

    # Check for security options
    if ! grep -q "security_opt:" "$compose_file"; then
        print_status "$YELLOW" "⚠️  Info: Consider adding security options to $compose_file"
    fi

    # Check for health checks
    if ! grep -q "healthcheck:" "$compose_file"; then
        print_status "$YELLOW" "⚠️  Info: Consider adding health checks to $compose_file"
    fi

    # Check for Traefik labels in services that should have them
    if grep -q "traefik" "$compose_file" && ! grep -q "traefik.enable" "$compose_file"; then
        print_status "$YELLOW" "⚠️  Warning: Traefik service without proper labels in $compose_file"
        ((warnings++))
    fi

    if [ $warnings -gt 0 ]; then
        print_status "$YELLOW" "⚠️  Found $warnings warnings in $compose_file"
    fi
}

# Main execution
main() {
    print_status "$GREEN" "🚀 Starting Docker Compose validation..."

    create_temp_env

    local failed=0
    local total=0

    # Find all docker-compose files
    compose_files=(
        "docker-compose.yml"
        "docker-compose.yaml"
        "templates/docker-compose.template.yml"
    )

    # Add any other compose files found
    while IFS= read -r -d '' file; do
        compose_files+=("$file")
    done < <(find . -name "docker-compose*.yml" -o -name "docker-compose*.yaml" -print0 2>/dev/null)

    # Remove duplicates and non-existent files
    declare -A seen
    for file in "${compose_files[@]}"; do
        if [ -f "$file" ] && [ -z "${seen[$file]:-}" ]; then
            seen[$file]=1

            ((total++))
            if ! validate_compose_file "$file"; then
                ((failed++))
            fi
            echo
        fi
    done

    # Summary
    print_status "$GREEN" "📊 Validation Summary:"
    print_status "$GREEN" "   Total files: $total"
    print_status "$GREEN" "   Passed: $((total - failed))"

    if [ $failed -gt 0 ]; then
        print_status "$RED" "   Failed: $failed"
        print_status "$RED" "❌ Validation completed with errors"
        exit 1
    else
        print_status "$GREEN" "✅ All Docker Compose files are valid!"
    fi
}

# Run main function
main "$@"
