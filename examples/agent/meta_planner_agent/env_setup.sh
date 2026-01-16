#!/bin/bash
# Script to setup environment for meta planner agent
# This script installs playwright and Chrome browser for browser automation

# Default values
INSTALL_CHROMIUM=true
TEST_INSTALLATION=false
SKIP_SYSTEM_DEPS_CHECK=false

# Function to display usage/help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup environment for meta planner agent by installing Playwright and Chromium browser.

OPTIONS:
    --skip-chromium          Skip Chromium installation (only check existing)
    --test                   Test installation after setup
    --skip-deps-check        Skip system dependencies check
    -h, --help               Show this help message and exit

EXAMPLES:
    # Full installation (default)
    $0

    # Only check existing installation
    $0 --skip-chromium

    # Install and test
    $0 --test

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-chromium)
            INSTALL_CHROMIUM=false
            shift
            ;;
        --test)
            TEST_INSTALLATION=true
            shift
            ;;
        --skip-deps-check)
            SKIP_SYSTEM_DEPS_CHECK=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            echo "Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

# Don't exit on error, we want to continue even if some steps fail
set +e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=========================================="
echo "Setting up environment for meta planner agent"
echo "=========================================="
echo "Project root: $PROJECT_ROOT"
echo ""

# Activate Python environment
if [ -d "$PROJECT_ROOT/.venv" ]; then
    echo "Activating .venv from project root..."
    source "$PROJECT_ROOT/.venv/bin/activate"
elif [ -d "$PROJECT_ROOT/venv" ]; then
    echo "Activating venv from project root..."
    source "$PROJECT_ROOT/venv/bin/activate"
else
    echo "Warning: No venv found in project root ($PROJECT_ROOT)"
    echo "Using system Python..."
fi

# Verify Python environment
echo "Python path: $(which python)"
echo "Python version: $(python --version)"
echo ""

# Setup Node.js/npm PATH
# Try to source nvm if available
if [ -s "$HOME/.nvm/nvm.sh" ]; then
    echo "Loading nvm..."
    . "$HOME/.nvm/nvm.sh" 2>/dev/null || true
fi

# Add Node.js bin directory to PATH if not already there
NODE_BIN_PATH="$HOME/.nvm/versions/node/v24.13.0/bin"
if [ -d "$NODE_BIN_PATH" ]; then
    # Check if path is already in PATH (compatible with sh)
    case ":$PATH:" in
        *":$NODE_BIN_PATH:"*)
            # Already in PATH
            ;;
        *)
            export PATH="$NODE_BIN_PATH:$PATH"
            echo "Added Node.js bin to PATH: $NODE_BIN_PATH"
            ;;
    esac
fi

# Check if Node.js/npm is available
if ! command -v npm &> /dev/null; then
    echo "Error: npm is not found in PATH"
    echo "Tried to add: $NODE_BIN_PATH"
    echo ""
    echo "Please install Node.js and npm first:"
    echo "  conda install -c conda-forge nodejs npm"
    echo "  or"
    echo "  apt install npm  # Debian/Ubuntu"
    echo "  or"
    echo "  Install via nvm: nvm install node"
    exit 1
fi

echo "Node.js version: $(node --version 2>/dev/null || echo 'not found')"
echo "npm version: $(npm --version)"
echo "npx version: $(npx --version)"
echo ""

# Install playwright browsers (Chrome/Chromium)
if [ "$INSTALL_CHROMIUM" = true ]; then
    echo "Installing Playwright Chromium browser (this may take a few minutes)..."
    echo "This will download Chromium browser for headless automation."
    echo ""

    # Method 1: Install via npx playwright (recommended)
    echo "Method 1: Installing via npx playwright install chromium..."
    if npx playwright install -y chromium 2>&1; then
        echo "✅ Successfully installed Chromium browser via npx"
        CHROMIUM_INSTALLED=true
    else
        echo "⚠️  Method 1 failed, trying alternative..."
        CHROMIUM_INSTALLED=false
    fi

    # Method 2: Install via Python playwright package
    if [ "$CHROMIUM_INSTALLED" = false ]; then
        echo ""
        echo "Method 2: Installing via Python playwright package..."
        if python -m pip install --quiet playwright 2>/dev/null; then
            echo "Installed playwright Python package"
            if python -m playwright install chromium 2>&1; then
                echo "✅ Successfully installed Chromium browser via Python playwright"
                CHROMIUM_INSTALLED=true
            else
                echo "⚠️  Failed to install Chromium via Python playwright"
            fi
        else
            echo "⚠️  Could not install playwright Python package"
        fi
    fi
else
    echo "Skipping Chromium installation (--skip-chromium flag set)"
    echo "Checking for existing installation..."
    CHROMIUM_INSTALLED=false
fi

echo ""

echo ""
echo "=========================================="
echo "Installation Summary"
echo "=========================================="
echo "Checking installed components..."

# Check playwright-mcp
if command -v npx &> /dev/null; then
    if npx @playwright/mcp@latest --help &> /dev/null; then
        echo "✅ playwright-mcp: Available via npx"
    else
        echo "⚠️  playwright-mcp: May need to be installed"
    fi
else
    echo "❌ npx: Not found"
fi

# Check Chromium installation
echo "Checking Chromium installation..."
CHROMIUM_PATHS=(
    "$HOME/.cache/ms-playwright/chromium-*/chrome"
    "$HOME/.local/share/ms-playwright/chromium-*/chrome"
    "$HOME/.cache/playwright/chromium-*/chrome"
    "$HOME/.cache/ms-playwright/chromium-*/chrome-linux/chrome"
    "$HOME/.local/share/ms-playwright/chromium-*/chrome-linux/chrome"
)

CHROMIUM_FOUND=false
CHROMIUM_PATH=""
for path_pattern in "${CHROMIUM_PATHS[@]}"; do
    # Use find to avoid shell expansion issues
    found_path=$(find "$HOME" -path "$(echo "$path_pattern" | sed 's/\*/.*/g')" -type f 2>/dev/null | head -1)
    if [ -n "$found_path" ] && [ -f "$found_path" ] && [ -x "$found_path" ]; then
        CHROMIUM_PATH="$found_path"
        echo "✅ Chromium: Found at $CHROMIUM_PATH"
        CHROMIUM_FOUND=true
        break
    fi
done

if [ "$CHROMIUM_FOUND" = false ]; then
    echo "⚠️  Chromium: Not found in common locations"
    echo "   Installation may have failed or browser is in a different location"
    echo "   Try running manually: npx playwright install chromium"
else
    # Verify Chromium can run
    echo "   Verifying Chromium executable..."
    if "$CHROMIUM_PATH" --version &> /dev/null; then
        CHROMIUM_VERSION=$("$CHROMIUM_PATH" --version 2>/dev/null | head -1)
        echo "   Version: $CHROMIUM_VERSION"
    fi
fi

# Check system dependencies for headless browser
if [ "$SKIP_SYSTEM_DEPS_CHECK" = false ]; then
    echo ""
    echo "Checking system dependencies for headless browser..."
    MISSING_DEPS=()

    # Check for common libraries needed by Chromium
    check_lib() {
        local lib_name=$1
        if ldconfig -p 2>/dev/null | grep -q "$lib_name" || \
           find /usr/lib* /lib* -name "*$lib_name*" 2>/dev/null | grep -q .; then
            return 0
        else
            MISSING_DEPS+=("$lib_name")
            return 1
        fi
    }

    # Common dependencies for headless Chrome
    check_lib "libnss3" && echo "  ✅ libnss3: Found" || echo "  ⚠️  libnss3: May be missing"
    check_lib "libatk" && echo "  ✅ libatk: Found" || echo "  ⚠️  libatk: May be missing"
    check_lib "libcups" && echo "  ✅ libcups: Found" || echo "  ⚠️  libcups: May be missing"

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo ""
        echo "⚠️  Some system libraries may be missing. If browser fails to start, install:"
        echo "   sudo apt-get install -y libnss3 libatk1.0-0 libatk-bridge2.0-0 \\"
        echo "     libcups2 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \\"
        echo "     libxfixes3 libxrandr2 libgbm1 libasound2"
    fi
else
    echo ""
    echo "Skipping system dependencies check (--skip-deps-check flag set)"
fi

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="

# Final status summary
echo ""
if [ "$CHROMIUM_INSTALLED" = true ] || [ "$CHROMIUM_FOUND" = true ]; then
    echo "✅ Chromium browser is ready for use"
else
    echo "❌ Chromium browser installation may have failed"
    echo "   Please check the error messages above"
fi

if command -v npx &> /dev/null; then
    echo "✅ npx is available for playwright-mcp"
else
    echo "❌ npx is not available"
fi

echo ""
echo "Next steps:"
echo "  1. Test playwright-mcp: npx @playwright/mcp@latest --help"
echo "  2. Run your agent: python test_gaia.py --model_type sglang"
echo ""
echo "If browser tools fail, check:"
echo "  - Chromium is installed: npx playwright install chromium"
echo "  - System dependencies: See warnings above"
echo "  - Logs: Check tool.py browser client connection errors"
echo ""

# Test installation if requested
if [ "$TEST_INSTALLATION" = true ]; then
    echo "=========================================="
    echo "Testing Installation"
    echo "=========================================="
    echo ""
    
    # Test npx
    echo "Testing npx..."
    if npx --version &> /dev/null; then
        echo "✅ npx: Working"
    else
        echo "❌ npx: Not working"
    fi
    
    # Test playwright-mcp
    echo "Testing playwright-mcp..."
    if timeout 10 npx @playwright/mcp@latest --help &> /dev/null; then
        echo "✅ playwright-mcp: Available"
    else
        echo "⚠️  playwright-mcp: May need to be downloaded (this is normal on first use)"
    fi
    
    # Test Chromium if found
    if [ "$CHROMIUM_FOUND" = true ] && [ -n "$CHROMIUM_PATH" ]; then
        echo "Testing Chromium executable..."
        if "$CHROMIUM_PATH" --headless --disable-gpu --version &> /dev/null; then
            echo "✅ Chromium: Executable works"
        else
            echo "⚠️  Chromium: Executable found but may have issues"
        fi
    fi
    
    echo ""
    echo "Test complete!"
    echo ""
fi
