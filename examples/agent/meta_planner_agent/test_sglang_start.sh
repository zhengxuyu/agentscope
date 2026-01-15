#!/bin/bash
# Test script to check sglang startup without actually starting the server
# Usage: ./test_sglang_start.sh

PORT=${1:-30000}
MODEL_PATH=${2:-"Qwen/Qwen2.5-8B-Instruct"}

echo "========================================="
echo "Testing sglang startup configuration"
echo "========================================="
echo ""

echo "1. Checking Python environment..."
which python
python --version
echo ""

echo "2. Checking if sglang is installed..."
if python -m sglang.launch_server --help &>/dev/null; then
    echo "✅ sglang is installed"
    python -m sglang.launch_server --help | head -10
else
    echo "❌ sglang is NOT installed"
    echo ""
    echo "To install sglang, run:"
    echo "  pip install sglang[all]"
    echo "  or"
    echo "  uv pip install 'sglang[all]'"
    echo ""
    echo "Note: sglang requires CUDA and PyTorch. Make sure you have:"
    echo "  - CUDA toolkit installed"
    echo "  - PyTorch with CUDA support"
    exit 1
fi
echo ""

echo "3. Configuration check:"
echo "   Model path: $MODEL_PATH"
echo "   Port: $PORT"
echo "   Host: 0.0.0.0"
echo ""

echo "4. Checking if port $PORT is available..."
if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port $PORT is already in use!"
    echo "   Process using the port:"
    lsof -Pi :$PORT -sTCP:LISTEN
    echo ""
    echo "   You can either:"
    echo "   - Stop the process using the port"
    echo "   - Use a different port: ./start_sglang.sh 30001"
else
    echo "✅ Port $PORT is available"
fi
echo ""

echo "5. Command that would be executed:"
echo "   python -m sglang.launch_server \\"
echo "       --model-path \"$MODEL_PATH\" \\"
echo "       --port $PORT \\"
echo "       --host 0.0.0.0"
echo ""

echo "========================================="
echo "To actually start the server, run:"
echo "  ./start_sglang.sh $PORT $MODEL_PATH"
echo "========================================="
