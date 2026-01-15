#!/bin/bash
# Script to submit multiple GAIA benchmark jobs to SLURM
# Usage: ./submit_gaia_batch.sh [total_samples] [samples_per_job] [result_base_dir]

TOTAL_SAMPLES=${1:-100}  # Total number of samples to process
SAMPLES_PER_JOB=${2:-10}  # Number of samples per job
RESULT_BASE_DIR=${3:-"./results/gaia"}  # Base directory for results

# Calculate number of jobs needed
NUM_JOBS=$(( (TOTAL_SAMPLES + SAMPLES_PER_JOB - 1) / SAMPLES_PER_JOB ))

echo "Submitting $NUM_JOBS jobs to process $TOTAL_SAMPLES samples"
echo "Each job will process $SAMPLES_PER_JOB samples"
echo "Results will be saved to: $RESULT_BASE_DIR"
echo ""

# Create logs directory
mkdir -p logs

# Submit jobs
for ((i=0; i<NUM_JOBS; i++)); do
    START_IDX=$((i * SAMPLES_PER_JOB))
    END_IDX=$((START_IDX + SAMPLES_PER_JOB))
    
    # Don't exceed total samples
    if [ $END_IDX -gt $TOTAL_SAMPLES ]; then
        END_IDX=$TOTAL_SAMPLES
    fi
    
    RESULT_DIR="${RESULT_BASE_DIR}/batch_${i}"
    
    echo "Submitting job $((i+1))/$NUM_JOBS: samples $START_IDX to $((END_IDX-1))"
    
    sbatch \
        --job-name=gaia_${i} \
        --output=logs/gaia_batch_${i}_%j.out \
        --error=logs/gaia_batch_${i}_%j.err \
        run_gaia_benchmark.sh \
        "" \
        $START_IDX \
        $END_IDX \
        $RESULT_DIR \
        ""
done

echo ""
echo "All jobs submitted. Check status with: squeue -u $USER"
echo "Monitor logs in: logs/"
