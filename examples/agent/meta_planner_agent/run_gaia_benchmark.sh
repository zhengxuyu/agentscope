#!/bin/bash
# Script to run GAIA benchmark test
# This script manages environment setup and launches test_gaia.py
# All arguments are passed directly to test_gaia.py

set -e  # Exit on error

# Function to display help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

This script sets up the environment and runs test_gaia.py.
All options are passed directly to test_gaia.py.

Options:
  -h, --help              Show this help message and exit

For test_gaia.py options, run:
  python test_gaia.py --help

Or see the examples below:

Examples:
  # Run with default settings
  $0

  # Test a single sample
  $0 --sample_idx 0

  # Test a range of samples
  $0 --start_idx 0 --end_idx 10

  # Use sglang model
  $0 --model_type sglang --api_base http://localhost:30000/v1

  # Use custom result directory
  $0 --result_dir ./my_results

  # Use custom model
  $0 --model_type dashscope --model_name qwen3-max

Environment Variables:
  DASHSCOPE_API_KEY       API key for DashScope models
  OPENAI_API_KEY          API key for OpenAI/SGLang models

EOF
}

# Parse help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    show_help
    exit 0
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Load environment configuration (for API keys and npm PATH)
if [ -f "$HOME/.config.sh" ]; then
    source "$HOME/.config.sh"
fi

# Change to project root
cd "$PROJECT_ROOT"

# Activate Python environment from project directory
# Priority: .venv (uv) > venv > conda
if [ -d "$PROJECT_ROOT/.venv" ]; then
    echo "Activating .venv from project root: $PROJECT_ROOT/.venv"
    source "$PROJECT_ROOT/.venv/bin/activate"
elif [ -d "$PROJECT_ROOT/venv" ]; then
    echo "Activating venv from project root: $PROJECT_ROOT/venv"
    source "$PROJECT_ROOT/venv/bin/activate"
else
    echo "Warning: No venv found in project root ($PROJECT_ROOT)"
    echo "Available options:"
    echo "  1. Create venv: python -m venv .venv"
    echo "  2. Or use uv: uv venv"
    echo "  3. Or use conda: source activate agentscope"
    echo ""
    echo "Falling back to system Python..."
fi

# Verify Python environment
echo "Python path: $(which python)"
echo "Python version: $(python --version)"
echo "Working directory: $(pwd)"
echo ""

# Change back to script directory for running the test
cd "$SCRIPT_DIR"

# Create logs directory if it doesn't exist
mkdir -p logs

# Set environment variables
export PYTHONUNBUFFERED=1

# Print command
echo "Running test_gaia.py with arguments: $@"
echo "----------------------------------------"

# Run test_gaia.py with all passed arguments
python test_gaia.py "$@"
EXIT_CODE=$?

# Print completion time
echo "----------------------------------------"
echo "End Time: $(date)"
if [ $EXIT_CODE -eq 0 ]; then
    echo "Job completed successfully"
else
    echo "Job completed with exit code: $EXIT_CODE"
fi

exit $EXIT_CODE
