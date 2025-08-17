#!/bin/bash
# Check that services have proper documentation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Extract service names from docker-compose files
extract_services() {
    local compose_file=$1

    # Use yq if available, otherwise fall back to grep
    if command -v yq &> /dev/null; then
        yq eval '.services | keys | .[]' "$compose_file" 2>/dev/null || true
    else
        # Fallback: extract service names with grep
        grep -A 1000 "^services:" "$compose_file" | \
        grep -E "^  [a-zA-Z]" | \
        cut -d':' -f1 | \
        sed 's/^  //' | \
        grep -v "^$" || true
    fi
}

# Check if service is documented in README files
check_service_documentation() {
    local service_name=$1
    local documented=false

    # Check main README
    if [ -f "README.md" ]; then
        if grep -qi "$service_name" README.md; then
            documented=true
        fi
    fi

    # Check docs directory
    if [ -d "docs" ]; then
        if find docs -name "*.md" -exec grep -l -i "$service_name" {} \; | grep -q .; then
            documented=true
        fi
    fi

    # Check for service-specific documentation
    if [ -f "docs/${service_name}.md" ] || [ -f "docs/${service_name^^}.md" ]; then
        documented=true
    fi

    echo "$documented"
}

# Check if service has proper labels and configuration
check_service_configuration() {
    local compose_file=$1
    local service_name=$2
    local issues=()

    # Extract service configuration
    local service_config
    service_config=$(grep -A 50 "^  $service_name:" "$compose_file" | \
                     sed '/^  [a-zA-Z]/,$d' | \
                     tail -n +2)

    # Check for restart policy
    if ! echo "$service_config" | grep -q "restart:"; then
        issues+=("Missing restart policy")
    fi

    # Check for container name
    if ! echo "$service_config" | grep -q "container_name:"; then
        issues+=("Missing container_name")
    fi

    # Check for health check (recommended)
    if ! echo "$service_config" | grep -q "healthcheck:"; then
        issues+=("Missing health check (recommended)")
    fi

    # Check for Traefik labels if it's a web service
    if echo "$service_config" | grep -q "ports:" && \
       ! echo "$service_config" | grep -q "traefik.enable"; then
        # Only warn for services that expose ports but don't use Traefik
        if ! echo "$service_name" | grep -q "traefik"; then
            issues+=("Exposes ports but no Traefik labels found")
        fi
    fi

    # Check for security options
    if ! echo "$service_config" | grep -q "security_opt:"; then
        issues+=("Missing security options (recommended)")
    fi

    echo "${issues[@]}"
}

# Check access URL documentation
check_access_urls() {
    local service_name=$1
    local has_access_info=false

    # Check if access information is documented
    local readme_files=("README.md" "docs/README.md" "docs/${service_name}.md")

    for readme in "${readme_files[@]}"; do
        if [ -f "$readme" ]; then
            # Look for URLs, access patterns, or port information
            if grep -qi -E "(https?://.*$service_name|$service_name.*\..*\.|port.*$service_name|access.*$service_name)" "$readme"; then
                has_access_info=true
                break
            fi
        fi
    done

    echo "$has_access_info"
}

# Main validation function
validate_service_documentation() {
    print_status "$GREEN" "📚 Checking service documentation..."

    local compose_files=(
        "docker-compose.yml"
        "docker-compose.yaml"
    )

    local total_services=0
    local documented_services=0
    local services_with_issues=0
    local all_issues=()

    for compose_file in "${compose_files[@]}"; do
        if [ ! -f "$compose_file" ]; then
            continue
        fi

        print_status "$YELLOW" "📄 Analyzing $compose_file..."

        # Get all services
        local services
        if command -v mapfile >/dev/null 2>&1; then
            mapfile -t services < <(extract_services "$compose_file")
        else
            # Fallback for systems without mapfile
            IFS=$'\n' read -d '' -r -a services < <(extract_services "$compose_file" && printf '\0')
        fi

        for service in "${services[@]}"; do
            if [ -z "$service" ]; then
                continue
            fi

            ((total_services++))

            print_status "$YELLOW" "  🔍 Checking service: $service"

            # Check documentation
            local is_documented
            is_documented=$(check_service_documentation "$service")

            if [ "$is_documented" = "true" ]; then
                ((documented_services++))
                print_status "$GREEN" "    ✅ Documented"
            else
                print_status "$RED" "    ❌ Not documented"
                all_issues+=("Service '$service' is not documented")
            fi

            # Check access URL documentation
            local has_access_info
            has_access_info=$(check_access_urls "$service")

            if [ "$has_access_info" = "true" ]; then
                print_status "$GREEN" "    ✅ Access information available"
            else
                print_status "$YELLOW" "    ⚠️  No access information found"
            fi

            # Check service configuration
            local config_issues
            if command -v mapfile >/dev/null 2>&1; then
                mapfile -t config_issues < <(check_service_configuration "$compose_file" "$service")
            else
                # Fallback for systems without mapfile
                IFS=$'\n' read -d '' -r -a config_issues < <(check_service_configuration "$compose_file" "$service" && printf '\0')
            fi

            if [ ${#config_issues[@]} -gt 0 ]; then
                ((services_with_issues++))
                print_status "$YELLOW" "    ⚠️  Configuration issues:"
                for issue in "${config_issues[@]}"; do
                    print_status "$YELLOW" "       - $issue"
                done
            else
                print_status "$GREEN" "    ✅ Configuration looks good"
            fi

            echo
        done
    done

    # Summary
    print_status "$GREEN" "📊 Documentation Summary:"
    print_status "$GREEN" "   Total services: $total_services"
    print_status "$GREEN" "   Documented services: $documented_services"
    print_status "$GREEN" "   Services with config issues: $services_with_issues"

    local exit_code=0

    if [ $documented_services -lt $total_services ]; then
        local undocumented=$((total_services - documented_services))
        print_status "$RED" "❌ $undocumented service(s) lack documentation"
        exit_code=1
    fi

    if [ ${#all_issues[@]} -gt 0 ]; then
        print_status "$RED" "❌ Issues found:"
        for issue in "${all_issues[@]}"; do
            print_status "$RED" "   - $issue"
        done
        exit_code=1
    fi

    if [ $exit_code -eq 0 ]; then
        print_status "$GREEN" "✅ All services are properly documented!"
    else
        print_status "$YELLOW" "💡 Recommendations:"
        print_status "$YELLOW" "   - Add service descriptions to README.md"
        print_status "$YELLOW" "   - Document access URLs and default credentials"
        print_status "$YELLOW" "   - Include configuration examples"
        print_status "$YELLOW" "   - Add troubleshooting information"
    fi

    return $exit_code
}

# Check for required documentation files
check_required_docs() {
    print_status "$GREEN" "📋 Checking for required documentation files..."

    local required_files=(
        "README.md"
        ".env.example"
        "docs/README.md"
        "docs/ADDING_SERVICES.md"
    )

    local missing_files=()

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        else
            print_status "$GREEN" "  ✅ $file exists"
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        print_status "$RED" "❌ Missing required documentation files:"
        for file in "${missing_files[@]}"; do
            print_status "$RED" "   - $file"
        done
        return 1
    else
        print_status "$GREEN" "✅ All required documentation files present"
        return 0
    fi
}

# Main function
main() {
    print_status "$GREEN" "🚀 Starting service documentation check..."

    local docs_ok=true
    local services_ok=true

    if ! check_required_docs; then
        docs_ok=false
    fi

    echo

    if ! validate_service_documentation; then
        services_ok=false
    fi

    echo
    print_status "$GREEN" "📊 Overall Summary:"

    if [ "$docs_ok" = true ] && [ "$services_ok" = true ]; then
        print_status "$GREEN" "✅ All documentation checks passed!"
        exit 0
    else
        print_status "$RED" "❌ Documentation check failed"
        if [ "$docs_ok" = false ]; then
            print_status "$RED" "   - Required documentation files missing"
        fi
        if [ "$services_ok" = false ]; then
            print_status "$RED" "   - Service documentation incomplete"
        fi
        exit 1
    fi
}

# Run main function
main "$@"
