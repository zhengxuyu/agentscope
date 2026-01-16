#!/bin/bash
# Script to test sglang server
# Usage: ./test_sglang.sh [options]
#   This script passes all arguments to test_sglang.py
#   See: python test_sglang.py --help for available options

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Activate Python environment from project directory
if [ -d "$PROJECT_ROOT/.venv" ]; then
    source "$PROJECT_ROOT/.venv/bin/activate"
elif [ -d "$PROJECT_ROOT/venv" ]; then
    source "$PROJECT_ROOT/venv/bin/activate"
fi

# Run the test using the Python script, passing all arguments
python "$SCRIPT_DIR/test_sglang.py" "$@"
exit $?
