#!/bin/bash
# Script to start sglang server for qwen3-8b model

# Default values
PORT=30000
MODEL_PATH="Qwen/Qwen3-4B-Instruct-2507"
TOOL_PARSER="qwen25"
REASONING_PARSER=""
HOST="0.0.0.0"

# Function to display usage/help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Start sglang server for model inference.

OPTIONS:
    -p, --port PORT              Port number for the server (default: 30000)
    -m, --model-path PATH        Model path or HuggingFace model ID (default: Qwen/Qwen3-4B-Instruct-2507)
    -t, --tool-parser PARSER     Tool call parser type (default: qwen25)
                                 Options: qwen25, deepseekv3, glm45, pythonic, etc.
    -r, --reasoning-parser PARSER
                                 Reasoning parser type (optional)
                                 If not specified, reasoning parser is not used
    --host HOST                  Host address to bind (default: 0.0.0.0)
    -h, --help                   Show this help message and exit

EXAMPLES:
    # Start server with default settings
    $0

    # Start server on custom port
    $0 --port 30001

    # Start server with custom model and tool parser
    $0 --model-path Qwen/Qwen2.5-7B-Instruct --tool-parser qwen25

    # Start server with reasoning parser
    $0 --reasoning-parser deepseekv3

    # Start server with all options
    $0 -p 30001 -m Qwen/Qwen2.5-7B-Instruct -t qwen25 -r deepseekv3

NOTES:
    - The script will automatically stop any existing sglang servers on the same port
    - Logs are saved to logs/sglang/sglang_server_<PORT>_<TIMESTAMP>.log
    - PID file is saved to sglang_server_<PORT>.pid

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--port)
            if [ -z "$2" ]; then
                echo "Error: --port requires a value" >&2
                echo "Use --help for usage information." >&2
                exit 1
            fi
            PORT="$2"
            shift 2
            ;;
        -m|--model-path)
            if [ -z "$2" ]; then
                echo "Error: --model-path requires a value" >&2
                echo "Use --help for usage information." >&2
                exit 1
            fi
            MODEL_PATH="$2"
            shift 2
            ;;
        -t|--tool-parser)
            if [ -z "$2" ]; then
                echo "Error: --tool-parser requires a value" >&2
                echo "Use --help for usage information." >&2
                exit 1
            fi
            TOOL_PARSER="$2"
            shift 2
            ;;
        -r|--reasoning-parser)
            if [ -z "$2" ]; then
                echo "Error: --reasoning-parser requires a value" >&2
                echo "Use --help for usage information." >&2
                exit 1
            fi
            REASONING_PARSER="$2"
            shift 2
            ;;
        --host)
            if [ -z "$2" ]; then
                echo "Error: --host requires a value" >&2
                echo "Use --help for usage information." >&2
                exit 1
            fi
            HOST="$2"
            shift 2
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

# Validate port number
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "Error: Invalid port number: $PORT (must be between 1 and 65535)" >&2
    exit 1
fi

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is 3 levels up from examples/agent/meta_planner_agent/
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

echo "=========================================="
echo "Starting sglang server..."
echo "=========================================="
echo "Configuration:"
echo "  Model path:      $MODEL_PATH"
echo "  Port:            $PORT"
echo "  Host:            $HOST"
echo "  Tool parser:     $TOOL_PARSER"
if [ -n "$REASONING_PARSER" ]; then
    echo "  Reasoning parser: $REASONING_PARSER"
else
    echo "  Reasoning parser: (not used)"
fi
echo "  Project root:    $PROJECT_ROOT"
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

# Create logs directory if it doesn't exist
LOG_DIR="$SCRIPT_DIR/logs/sglang"
mkdir -p "$LOG_DIR"

# Log file name with timestamp
LOG_FILE="$LOG_DIR/sglang_server_${PORT}_$(date +%Y%m%d_%H%M%S).log"
PID_FILE="$SCRIPT_DIR/sglang_server_${PORT}.pid"

# Kill any existing sglang servers before starting a new one
echo "Checking for existing sglang servers..."
KILLED_COUNT=0

# Kill server by PID file if it exists and process is running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Stopping existing sglang server (PID: $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null
        sleep 2
        # Force kill if still running
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "Force killing sglang server (PID: $OLD_PID)..."
            kill -9 "$OLD_PID" 2>/dev/null
        fi
        KILLED_COUNT=$((KILLED_COUNT + 1))
    fi
    rm -f "$PID_FILE"
fi

# Kill all sglang.launch_server processes to ensure clean state
EXISTING_PIDS=$(pgrep -f "sglang.launch_server" 2>/dev/null || true)
if [ -n "$EXISTING_PIDS" ]; then
    echo "Stopping all sglang.launch_server processes..."
    pkill -f "sglang.launch_server" 2>/dev/null || true
    sleep 2
    # Force kill if any are still running
    REMAINING_PIDS=$(pgrep -f "sglang.launch_server" 2>/dev/null || true)
    if [ -n "$REMAINING_PIDS" ]; then
        echo "Force killing remaining sglang processes..."
        pkill -9 -f "sglang.launch_server" 2>/dev/null || true
    fi
    KILLED_COUNT=$((KILLED_COUNT + 1))
fi

# Clean up any PID files for this port
rm -f "$SCRIPT_DIR/sglang_server_${PORT}.pid"

if [ $KILLED_COUNT -gt 0 ]; then
    echo "✅ Stopped $KILLED_COUNT existing sglang server(s)"
    sleep 1  # Give processes time to fully terminate
else
    echo "No existing sglang servers found"
fi
echo ""

# Start sglang server in background
echo "Starting sglang server in background..."
echo "Log file: $LOG_FILE"
echo "PID file: $PID_FILE"
echo ""

# Build command arguments
SGLANG_ARGS=(
    --model-path "$MODEL_PATH"
    --port "$PORT"
    --host "$HOST"
    --tool-call-parser "$TOOL_PARSER"
)

# Add reasoning parser if specified
if [ -n "$REASONING_PARSER" ]; then
    SGLANG_ARGS+=(--reasoning-parser "$REASONING_PARSER")
fi

# Start sglang server
echo "Starting sglang server with command:"
echo "  python -m sglang.launch_server ${SGLANG_ARGS[*]}"
echo ""

python -m sglang.launch_server "${SGLANG_ARGS[@]}" > "$LOG_FILE" 2>&1 &

SERVER_PID=$!
echo $SERVER_PID > "$PID_FILE"

echo "✅ sglang server process started (PID: $SERVER_PID)"
echo "   Waiting for server to be ready..."
echo ""

# Wait for server to be ready by checking if port is listening
MAX_WAIT=120  # Maximum wait time in seconds
WAIT_INTERVAL=2  # Check every 2 seconds
ELAPSED=0
READY=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if process is still running
    if ! ps -p "$SERVER_PID" > /dev/null 2>&1; then
        echo "❌ Server process died unexpectedly!"
        echo "   Check logs: $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
    
    # Check if port is listening (use localhost for connection check)
    if command -v nc >/dev/null 2>&1; then
        if nc -z localhost "$PORT" 2>/dev/null; then
            READY=true
            break
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
            READY=true
            break
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp 2>/dev/null | grep -q ":$PORT "; then
            READY=true
            break
        fi
    else
        # Fallback: check if we can make a simple HTTP request
        if python -c "import requests; requests.get('http://localhost:${PORT}/health', timeout=2)" 2>/dev/null; then
            READY=true
            break
        fi
    fi
    
    echo -n "."
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

echo ""
echo ""

if [ "$READY" = true ]; then
    echo "✅ sglang server is ready!"
    echo "   PID: $SERVER_PID"
    echo "   Port: $PORT"
    echo "   Log: $LOG_FILE"
    echo "   To stop: kill $SERVER_PID or use the PID file: $PID_FILE"
    echo ""
    echo "To view logs in real-time: tail -f $LOG_FILE"
else
    echo "⚠️  Server may not be fully ready yet (waited ${ELAPSED}s)"
    echo "   PID: $SERVER_PID"
    echo "   Port: $PORT"
    echo "   Log: $LOG_FILE"
    echo "   Check logs to verify server status: tail -f $LOG_FILE"
fi
