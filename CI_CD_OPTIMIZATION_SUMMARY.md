# Homelab CI/CD - Simple & Practical

## 🏠 Overview

This homelab uses a minimal CI/CD approach focused on one thing: **making sure your configuration works**. No enterprise complexity, no automated updates, no release management - just basic validation so you don't break your homelab.

## ✅ What We Do

### GitHub Actions Validation
**Location**: `.github/workflows/ci.yml`

**What it checks**:
- ✅ Docker Compose files are valid syntax
- ✅ YAML files can be parsed correctly  
- ✅ Shell scripts have valid syntax

**When it runs**:
- On pushes to `main` branch
- On pull requests to `main` branch

**Why this matters**:
- Catches typos and syntax errors before you deploy
- Ensures your services will actually start
- Takes less than 2 minutes to run

## 🛠️ Local Tools

You still have these scripts for local development:

### Essential Scripts
- `scripts/health_check.py` - Check if your services are running
- `scripts/validate_compose.sh` - Test your Docker Compose locally
- `scripts/security_audit.py` - Basic security checks

### Using the Scripts
```bash
# Quick health check
python3 scripts/health_check.py

# Validate your compose files
./scripts/validate_compose.sh

# Basic security audit
python3 scripts/security_audit.py
```

## 🎯 Homelab Philosophy

### What We Removed
- ❌ **Dependabot** - You can update Docker images when YOU want to
- ❌ **Release Drafter** - This isn't a product, it's your homelab  
- ❌ **Advanced Security Scanning** - Overkill for home use
- ❌ **Team Notifications** - It's just you
- ❌ **Complex Testing** - Keep it simple

### What We Kept
- ✅ **Basic Validation** - Make sure things actually work
- ✅ **Syntax Checking** - Catch typos before deployment
- ✅ **Simple Health Checks** - Know when services are down

## 🚀 Usage

### Day-to-Day Development
1. Make changes to your docker-compose.yml or configs
2. Push to GitHub (or create a PR)
3. GitHub checks if everything is valid
4. If green ✅ - deploy to your homelab
5. If red ❌ - fix the syntax error first

### Local Testing
```bash
# Before pushing changes, test locally:
docker compose config                    # Check syntax
./scripts/validate_compose.sh          # Full validation
python3 scripts/health_check.py        # Check running services
```

## 🔧 Customization

Want to add checks? Edit `.github/workflows/ci.yml`:

```yaml
# Add a step like this:
- name: My Custom Check
  run: |
    echo "🔍 Running my custom validation..."
    # Your custom commands here
    echo "✅ Custom check passed"
```

## 💡 Benefits

### For Homelab Use
- **Fast feedback** - Know if changes work in under 2 minutes
- **No surprises** - Catch errors before they break your services  
- **Simple maintenance** - No complex dependencies to maintain
- **Your control** - Update things when YOU decide to

### Peace of Mind
- Services will start after configuration changes
- No syntax errors breaking your homelab
- Basic validation without enterprise overhead

## 🎉 That's It!

This CI/CD setup does exactly what a homelab needs:
1. **Validates** your configuration files
2. **Catches** syntax errors  
3. **Stays out of your way** for everything else

No automated updates forcing changes on you. No complex release processes. Just simple validation that your homelab configuration works.

Deploy with confidence! 🏠✨