#!/bin/bash
# Script to start sglang server for qwen3-8b model
# Usage: ./start_sglang.sh [port] [model_path]

PORT=${1:-30000}
MODEL_PATH=${2:-"Qwen/Qwen2.5-8B-Instruct"}

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is 3 levels up from examples/agent/meta_planner_agent/
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "Starting sglang server..."
echo "Model: $MODEL_PATH"
echo "Port: $PORT"
echo "Project root: $PROJECT_ROOT"
echo ""

# Activate Python environment from project directory
if [ -d "$PROJECT_ROOT/.venv" ]; then
    echo "Activating .venv from project root: $PROJECT_ROOT/.venv"
    source "$PROJECT_ROOT/.venv/bin/activate"
elif [ -d "$PROJECT_ROOT/venv" ]; then
    echo "Activating venv from project root: $PROJECT_ROOT/venv"
    source "$PROJECT_ROOT/venv/bin/activate"
else
    echo "Warning: No venv found in project root ($PROJECT_ROOT)"
    echo "Using system Python..."
fi

# Verify Python environment
echo "Python path: $(which python)"
echo "Python version: $(python --version)"
echo ""

# Check if sglang is installed
echo "Checking if sglang is installed..."
if ! python -m sglang.launch_server --help &> /dev/null; then
    echo "Error: sglang is not installed in the current Python environment"
    echo "Current Python: $(which python)"
    echo ""
    echo "To install sglang, run one of:"
    echo "  pip install 'sglang[all]'"
    echo "  uv pip install 'sglang[all]'"
    echo "  uv add 'sglang[all]'"
    echo ""
    echo "Note: Make sure you're in the project's venv when installing."
    exit 1
fi

echo "✅ sglang is installed"
echo ""

# Start sglang server
echo "Starting sglang server..."
python -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --port "$PORT" \
    --host "0.0.0.0"
