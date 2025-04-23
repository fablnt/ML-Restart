#!/bin/bash

# DMTCP Wrapper Script for Singularity (Non-Conda)
# Features:
# - Auto-runs Python scripts using system Python
# - Default 10-second checkpoint interval
# - Captures application output (stdout/stderr) to application_output.log
# - Organized checkpoint directories
# - Compatible with Singularity container
# - Debug mode for output capture issues

DEFAULT_INTERVAL=10

function setup_environment {
    local script_name="$1"
    CKPT_DIR="./checkpoints_${script_name}_${ID_NAME}"
    LOG_FILE="${CKPT_DIR}/execution.log"
    APP_OUTPUT_FILE="${CKPT_DIR}/application_output.log"
    
    mkdir -p "$CKPT_DIR" || {
        echo "Error: Failed to create checkpoint directory $CKPT_DIR" | tee -a "$LOG_FILE"
        exit 1
    }
    touch "$LOG_FILE" || {
        echo "Error: Failed to create log file $LOG_FILE" | tee -a "$LOG_FILE"
        exit 1
    }
    touch "$APP_OUTPUT_FILE" || {
        echo "Error: Failed to create application output file $APP_OUTPUT_FILE" | tee -a "$LOG_FILE"
        exit 1
    }
    echo "$(date): Setting up for $script_name" >> "$LOG_FILE"
    echo "$(date): Checkpoint directory: $CKPT_DIR" >> "$LOG_FILE"
    echo "$(date): Application output will be written to: $APP_OUTPUT_FILE" >> "$LOG_FILE"
}

function start_program {
    local script_path="$1"
    local interval="$2"

    local script_name
    script_name=$(basename "$script_path" .py)
    
    setup_environment "$script_name"

    echo "Starting $script_name with DMTCP (checkpoints every ${interval}s)" | tee -a "$LOG_FILE"
    echo "Checkpoints: $CKPT_DIR" | tee -a "$LOG_FILE"
    echo "Script logs: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Application output: $APP_OUTPUT_FILE" | tee -a "$LOG_FILE"

    # Set PYTHONUNBUFFERED to disable Python output buffering
    export PYTHONUNBUFFERED=1

    # Run dmtcp_launch and capture output with tee for real-time logging
    echo "$(date): Launching dmtcp_launch for $script_path" >> "$LOG_FILE"
    (dmtcp_launch --ckptdir "$CKPT_DIR" --interval "$interval" \
    python3 "$script_path" "${PYTHON_ARGS[@]}" > "$APP_OUTPUT_FILE" 2>&1) &

    local pid=$!
    echo "$(date): Process started with PID: $pid" >> "$LOG_FILE"
}

function restart_program {
    local script_path="$1"
    local interval="$2"

    local script_name
    script_name=$(basename "$script_path" .py)
    
    setup_environment "$script_name"

    LAST_CKPT=$(ls -t "$CKPT_DIR"/ckpt_*.dmtcp 2>/dev/null | head -n 1)

    if [ -z "$LAST_CKPT" ]; then
        echo "Error: No checkpoint found in $CKPT_DIR" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "Restarting from checkpoint: $(basename "$LAST_CKPT")" | tee -a "$LOG_FILE"
    echo "Application output: $APP_OUTPUT_FILE" | tee -a "$LOG_FILE"

    # Set PYTHONUNBUFFERED for restart
    export PYTHONUNBUFFERED=1

    # Run dmtcp_restart and capture output with tee
    echo "$(date): Launching dmtcp_restart for $LAST_CKPT" >> "$LOG_FILE"
    dmtcp_restart --interval "$interval" "$LAST_CKPT" >> "$APP_OUTPUT_FILE" &
    local pid=$!
    echo "$(date): Process restarted with PID: $pid" >> "$LOG_FILE"
}

# --- Main Execution ---
ACTION=""
SCRIPT=""
INTERVAL="$DEFAULT_INTERVAL"
ID_NAME=""
PYTHON_ARGS=()

# Parse args manually to enforce order and handle optional flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        start|restart)
            ACTION="$1"
            shift
            ;;
        -id)
            ID_NAME="$2"
            shift 2
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        *.py)
            SCRIPT="$1"
            shift
            PYTHON_ARGS=("$@")  # everything after .py goes to Python script
            break
            ;;
        *)
            echo "Unknown or misplaced argument: $1"
            echo "Usage:"
            echo "  $0 start|restart [-id NAME] [--interval SECONDS] script.py [args...]"
            exit 1
            ;;
    esac
done

# Check mandatory arguments
if [[ -z "$ACTION" || -z "$SCRIPT" ]]; then
    echo "Missing required parameters."
    echo "Usage:"
    echo "  $0 start|restart [-id NAME] [--interval SECONDS] script.py [args...]"
    exit 1
fi

case "$ACTION" in
    start)
        start_program "$SCRIPT" "$INTERVAL"
        ;;
    restart)
        restart_program "$SCRIPT" "$INTERVAL"
        ;;
    *)
        echo "Invalid action: $ACTION"
        echo "Usage:"
        echo "  $0 start <script.py> [--interval SECONDS]"
        echo "  $0 restart <script.py> [--interval SECONDS]"
        exit 1
        ;;
esac
