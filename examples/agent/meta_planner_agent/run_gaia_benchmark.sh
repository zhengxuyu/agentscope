#!/bin/bash
#SBATCH --job-name=gaia_benchmark
#SBATCH --output=logs/gaia_benchmark_%j.out
#SBATCH --error=logs/gaia_benchmark_%j.err
#SBATCH --time=24:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
# Note: For sglang, you may need more memory and CPUs. Adjust accordingly.

# Note: Adjust the above parameters according to your cluster configuration
# Common partitions: gpu, cpu, general, etc.
# If you don't need GPU, remove --gres=gpu:1 and change partition to cpu

# Print job information
echo "Job ID: $SLURM_JOB_ID"
echo "Job Name: $SLURM_JOB_NAME"
echo "Node: $SLURM_NODELIST"
echo "Start Time: $(date)"
echo "Working Directory: $(pwd)"

# Load necessary modules (adjust according to your cluster)
# module load python/3.12
# module load cuda/11.8

# Set up environment
export PYTHONUNBUFFERED=1

# Set API key (make sure DASHSCOPE_API_KEY is set in your environment or .env file)
# export DASHSCOPE_API_KEY="your-api-key-here"

# Activate Python environment (adjust path as needed)
# Option 1: Using conda
# source activate agentscope

# Option 2: Using venv
# source /path/to/venv/bin/activate

# Option 3: Using uv (if installed)
# source .venv/bin/activate

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create logs directory if it doesn't exist
mkdir -p logs

# Parse command line arguments
SAMPLE_IDX=${1:-""}
START_IDX=${2:-0}
END_IDX=${3:-""}
RESULT_DIR=${4:-"./results/gaia"}
DATA_DIR=${5:-""}
MODEL_TYPE=${6:-"dashscope"}  # dashscope, sglang, or openai
MODEL_NAME=${7:-""}           # Model name (optional)
API_BASE=${8:-""}             # API base URL for sglang/openai (optional)
API_KEY=${9:-""}              # API key (optional)
SGLANG_PORT=${10:-"30000"}    # Port for sglang server (default: 30000)
SGLANG_MODEL_PATH=${11:-""}   # Model path for sglang (optional, uses MODEL_NAME if not set)

# Build command
CMD="uv run python test_gaia.py --result_dir $RESULT_DIR --model_type $MODEL_TYPE"

if [ -n "$SAMPLE_IDX" ]; then
    CMD="$CMD --sample_idx $SAMPLE_IDX"
else
    CMD="$CMD --start_idx $START_IDX"
    if [ -n "$END_IDX" ]; then
        CMD="$CMD --end_idx $END_IDX"
    fi
fi

if [ -n "$DATA_DIR" ]; then
    CMD="$CMD --data_dir $DATA_DIR"
fi

if [ -n "$MODEL_NAME" ]; then
    CMD="$CMD --model_name $MODEL_NAME"
fi

if [ -n "$API_BASE" ]; then
    CMD="$CMD --api_base $API_BASE"
fi

if [ -n "$API_KEY" ]; then
    CMD="$CMD --api_key $API_KEY"
fi

# Start sglang server if needed
SGLANG_PID=""
if [ "$MODEL_TYPE" = "sglang" ]; then
    echo "Starting sglang server..."
    
    # Determine model path
    if [ -z "$SGLANG_MODEL_PATH" ]; then
        if [ -n "$MODEL_NAME" ]; then
            SGLANG_MODEL_PATH="$MODEL_NAME"
        else
            SGLANG_MODEL_PATH="Qwen/Qwen2.5-8B-Instruct"
        fi
    fi
    
    # Set default API base if not provided
    if [ -z "$API_BASE" ]; then
        API_BASE="http://localhost:${SGLANG_PORT}/v1"
    fi
    
    echo "Model path: $SGLANG_MODEL_PATH"
    echo "Port: $SGLANG_PORT"
    echo "API base: $API_BASE"
    
    # Check if sglang is available
    if ! command -v python -m sglang.launch_server &> /dev/null; then
        echo "Error: sglang is not installed or not in PATH"
        echo "Install with: pip install sglang[all]"
        exit 1
    fi
    
    # Start sglang server in background
    python -m sglang.launch_server \
        --model-path "$SGLANG_MODEL_PATH" \
        --port "$SGLANG_PORT" \
        --host "0.0.0.0" \
        > logs/sglang_server_${SLURM_JOB_ID}.log 2>&1 &
    
    SGLANG_PID=$!
    echo "sglang server started with PID: $SGLANG_PID"
    
    # Wait for server to be ready (check if port is listening)
    echo "Waiting for sglang server to be ready..."
    MAX_WAIT=300  # Maximum wait time in seconds
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        if curl -s "http://localhost:${SGLANG_PORT}/health" > /dev/null 2>&1 || \
           nc -z localhost ${SGLANG_PORT} 2>/dev/null; then
            echo "sglang server is ready!"
            break
        fi
        sleep 2
        WAIT_COUNT=$((WAIT_COUNT + 2))
        echo "Waiting... (${WAIT_COUNT}s/${MAX_WAIT}s)"
    done
    
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        echo "Error: sglang server failed to start within ${MAX_WAIT} seconds"
        if [ -n "$SGLANG_PID" ]; then
            kill $SGLANG_PID 2>/dev/null
        fi
        exit 1
    fi
    
    # Update API_BASE in command if it was auto-set
    if [ -z "$8" ]; then
        CMD="$CMD --api_base $API_BASE"
    fi
fi

# Print command
echo "Running command: $CMD"
echo "----------------------------------------"

# Function to cleanup sglang server on exit
cleanup() {
    if [ -n "$SGLANG_PID" ]; then
        echo "Stopping sglang server (PID: $SGLANG_PID)..."
        kill $SGLANG_PID 2>/dev/null
        wait $SGLANG_PID 2>/dev/null
        echo "sglang server stopped"
    fi
}

# Register cleanup function
trap cleanup EXIT INT TERM

# Run the benchmark
eval $CMD
EXIT_CODE=$?

# Print completion time
echo "----------------------------------------"
echo "End Time: $(date)"
if [ $EXIT_CODE -eq 0 ]; then
    echo "Job completed successfully"
else
    echo "Job completed with exit code: $EXIT_CODE"
fi

# Cleanup will be handled by trap
exit $EXIT_CODE
