#!/bin/bash
# Script to start sglang server for qwen3-8b model
# Usage: ./start_sglang.sh [port] [model_path]

PORT=${1:-30000}
MODEL_PATH=${2:-"Qwen/Qwen2.5-8B-Instruct"}

echo "Starting sglang server..."
echo "Model: $MODEL_PATH"
echo "Port: $PORT"
echo ""

# Check if sglang is installed
if ! command -v python -m sglang.launch_server &> /dev/null; then
    echo "Error: sglang is not installed or not in PATH"
    echo "Install with: pip install sglang[all]"
    exit 1
fi

# Start sglang server
python -m sglang.launch_server \
    --model-path "$MODEL_PATH" \
    --port "$PORT" \
    --host "0.0.0.0"
