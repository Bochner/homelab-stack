#!/bin/bash
# Validate that .env.example contains all required environment variables

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

# Extract environment variables from docker-compose files
extract_env_vars_from_compose() {
    local compose_file=$1

    # Find all ${VAR} and ${VAR:-default} patterns
    grep -o "\${[^}]*}" "$compose_file" 2>/dev/null | \
        sed 's/\${//g' | \
        sed 's/}//g' | \
        sed 's/:-.*//' | \
        sort -u
}

# Extract variables from .env.example
extract_vars_from_env_example() {
    if [ ! -f ".env.example" ]; then
        echo ""
        return
    fi

    # Extract variable names (before =)
    grep -v '^#' .env.example 2>/dev/null | \
        grep '=' | \
        cut -d'=' -f1 | \
        sort -u
}

# Main validation function
validate_env_completeness() {
    print_status "$GREEN" "🔍 Validating .env.example completeness..."

    if [ ! -f ".env.example" ]; then
        print_status "$RED" "❌ .env.example file not found"
        return 1
    fi

    # Collect all environment variables from compose files (exclude templates)

    local compose_files=(
        "docker-compose.yml"
        "docker-compose.yaml"
    )

    # Find additional compose files (exclude templates)
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"template"* ]]; then
            compose_files+=("$file")
        fi
    done < <(find . \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) -print0 2>/dev/null)

    print_status "$YELLOW" "📁 Scanning compose files for environment variables..."

    local temp_vars_file
    temp_vars_file=$(mktemp)
    for compose_file in "${compose_files[@]}"; do
        if [ -f "$compose_file" ]; then
            print_status "$YELLOW" "   Scanning $compose_file"
            extract_env_vars_from_compose "$compose_file" >> "$temp_vars_file"
        fi
    done

    # Get unique variables from all compose files
    local compose_vars
    if command -v mapfile >/dev/null 2>&1; then
        mapfile -t compose_vars < <(sort -u "$temp_vars_file")
    else
        # Fallback for systems without mapfile
        IFS=$'\n' read -d '' -r -a compose_vars < <(sort -u "$temp_vars_file" && printf '\0')
    fi
    rm -f "$temp_vars_file"

    # Get variables from .env.example
    local env_example_vars
    if command -v mapfile >/dev/null 2>&1; then
        mapfile -t env_example_vars < <(extract_vars_from_env_example)
    else
        # Fallback for systems without mapfile
        IFS=$'\n' read -d '' -r -a env_example_vars < <(extract_vars_from_env_example && printf '\0')
    fi

    print_status "$GREEN" "📊 Analysis Results:"
    print_status "$GREEN" "   Variables in compose files: ${#compose_vars[@]}"
    print_status "$GREEN" "   Variables in .env.example: ${#env_example_vars[@]}"

    # Check for missing variables
    local missing_vars=()
    local found_in_example

    for var in "${compose_vars[@]}"; do
        found_in_example=false
        for example_var in "${env_example_vars[@]}"; do
            if [ "$var" = "$example_var" ]; then
                found_in_example=true
                break
            fi
        done

        if [ "$found_in_example" = false ]; then
            missing_vars+=("$var")
        fi
    done

    # Check for unused variables in .env.example
    local unused_vars=()
    local found_in_compose

    for example_var in "${env_example_vars[@]}"; do
        found_in_compose=false
        for var in "${compose_vars[@]}"; do
            if [ "$example_var" = "$var" ]; then
                found_in_compose=true
                break
            fi
        done

        if [ "$found_in_compose" = false ]; then
            unused_vars+=("$example_var")
        fi
    done

    # Report results
    local exit_code=0

    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_status "$RED" "❌ Missing variables in .env.example:"
        for var in "${missing_vars[@]}"; do
            print_status "$RED" "   - $var"
        done
        exit_code=1
    fi

    if [ ${#unused_vars[@]} -gt 0 ]; then
        print_status "$YELLOW" "⚠️  Unused variables in .env.example:"
        for var in "${unused_vars[@]}"; do
            print_status "$YELLOW" "   - $var"
        done
    fi

    if [ $exit_code -eq 0 ]; then
        print_status "$GREEN" "✅ .env.example contains all required variables"
    else
        print_status "$RED" "❌ .env.example validation failed"
        print_status "$YELLOW" "💡 Suggested additions to .env.example:"
        for var in "${missing_vars[@]}"; do
            print_status "$YELLOW" "   $var=your-value-here"
        done
    fi

    return $exit_code
}

# Validate environment variable formats
validate_env_format() {
    print_status "$GREEN" "🔍 Validating .env.example format..."

    local issues=0
    local line_num=0

    while IFS= read -r line; do
        ((line_num++))

        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Check for proper format (VAR=value)
        if [[ ! "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
            print_status "$RED" "❌ Line $line_num: Invalid format - $line"
            ((issues++))
        fi

        # Check for placeholder values that should be changed
        if [[ "$line" =~ (your-|example\.|change-me|replace-me) ]]; then
            print_status "$GREEN" "✅ Line $line_num: Contains placeholder - $line"
        fi

    done < .env.example

    if [ $issues -eq 0 ]; then
        print_status "$GREEN" "✅ .env.example format is valid"
        return 0
    else
        print_status "$RED" "❌ Found $issues formatting issues in .env.example"
        return 1
    fi
}

# Main function
main() {
    print_status "$GREEN" "🚀 Starting .env.example validation..."

    local completeness_ok=true
    local format_ok=true

    if ! validate_env_completeness; then
        completeness_ok=false
    fi

    echo

    if ! validate_env_format; then
        format_ok=false
    fi

    echo
    print_status "$GREEN" "📊 Validation Summary:"

    if [ "$completeness_ok" = true ] && [ "$format_ok" = true ]; then
        print_status "$GREEN" "✅ All .env.example validations passed!"
        exit 0
    else
        print_status "$RED" "❌ .env.example validation failed"
        if [ "$completeness_ok" = false ]; then
            print_status "$RED" "   - Completeness check failed"
        fi
        if [ "$format_ok" = false ]; then
            print_status "$RED" "   - Format check failed"
        fi
        exit 1
    fi
}

# Run main function
main "$@"
