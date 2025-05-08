#!/bin/bash

# Specify the absolute path to the bin directory of dmtcp (not to be filled in case of successful make install)
DMTCP_EXEC=""
INTERVAL=10

function setup_environment {

    local script_name="$1"
    CKPT_DIR="./checkpoints_${script_name}_${ID_NAME}"
    LOG_FILE="${CKPT_DIR}/execution.log"
    APP_OUTPUT_FILE="${CKPT_DIR}/application_output.log"
    CONFIG_FILE="${CKPT_DIR}/dmtcp_config"

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
    local script_name
    script_name=$(basename "$script_path" .py)

    setup_environment "$script_name"

   
    local COORD_PORT
    COORD_PORT=$PORT
    echo "$(date): Assigned coordinator port: $COORD_PORT" >> "$LOG_FILE"

    # Start the DMTCP coordinator in the background
    ${DMTCP_EXEC}dmtcp_coordinator --exit-on-last --ckptdir "$CKPT_DIR" --coord-port "$COORD_PORT" >> "$CKPT_DIR/coordinator.log" 2>&1 &
    local COORD_PID=$!
    echo "$(date): Started coordinator with PID: $COORD_PID" >> "$LOG_FILE"

    # Save coordinator port to config file
    echo "COORD_PORT=$COORD_PORT" > "$CKPT_DIR/dmtcp_config"
    echo "CHECKPOINT_DIR=$CKPT_DIR" >> "$CKPT_DIR/dmtcp_config"
    echo "PROGRAM=$script_path" >> "$CKPT_DIR/dmtcp_config"

    echo "Starting $script_name with DMTCP" | tee -a "$LOG_FILE"
    echo "Checkpoints: $CKPT_DIR" | tee -a "$LOG_FILE"
    echo "Script logs: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Application output: $APP_OUTPUT_FILE" | tee -a "$LOG_FILE"

    # Set environment variables for DMTCP
    export DMTCP_COORD_PORT="$COORD_PORT"
    export DMTCP_CKPT_DIR="$CKPT_DIR"
    export DMTCP_DL_PLUGIN=0

    # Launches the first execution of the script with dmtcp_launch
    echo "$(date): Launching dmtcp_launch for $script_path" >> "$LOG_FILE"
    (${DMTCP_EXEC}dmtcp_launch --interval $INTERVAL --ckpt-open-files --ckptdir $CKPT_DIR python3 -u "$script_path" "${PYTHON_ARGS[@]}" > "$APP_OUTPUT_FILE" 2>&1) &
    local pid=$!
    echo "$(date): Process started with PID: $pid" >> "$LOG_FILE"

}


function restart_program {

    local script_path="$1"
    local script_name
    script_name=$(basename "$script_path" .py)

    setup_environment "$script_name"
    CONFIG_FILE="${CKPT_DIR}/dmtcp_config"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Configuration file $CONFIG_FILE not found" | tee -a "$LOG_FILE"
        exit 1
    fi
    source "$CONFIG_FILE"

    
    LAST_CKPT="$CKPT_DIR/dmtcp_restart_script.sh"    

    if [ -z "$LAST_CKPT" ]; then
        echo "Error: No checkpoint found in $CKPT_DIR" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "Restarting from checkpoint: $(basename "$LAST_CKPT")" | tee -a "$LOG_FILE"
    echo "Application output: $APP_OUTPUT_FILE" | tee -a "$LOG_FILE"

    COORD_PORT=$PORT
    # Start a new coordinator on the same port
    ${DMTCP_EXEC}dmtcp_coordinator --interval $INTERVAL --exit-on-last --ckptdir $CKPT_DIR --coord-port "$COORD_PORT"  >> "$CKPT_DIR/coordinator.log" 2>&1 &
    local COORD_PID=$!
    echo "$(date): Started coordinator with PID: $COORD_PID" >> "$LOG_FILE"

    
    # Set environment variables for DMTCP
    export DMTCP_COORD_PORT="$COORD_PORT"
    export DMTCP_CKPT_DIR="$CKPT_DIR"

    # Restart the script
    echo "$(date): Launching dmtcp_restart for $LAST_CKPT" >> "$LOG_FILE"
    (./"$LAST_CKPT" &>> "$APP_OUTPUT_FILE") &
    local pid=$!
    echo "$(date): Process restarted with PID: $pid" >> "$LOG_FILE"

}

# --- Main Execution ---
ACTION=""
SCRIPT=""
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
     	-i)
	    INTERVAL="$2"
	    shift 2
	    ;;
    	-p)
	    PORT="$2"	
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
            echo "  $0 start|restart [-id NAME] script.py [args...]"
            exit 1
            ;;
    esac
done

# Check mandatory arguments
if [[ -z "$ACTION" || -z "$SCRIPT" ]]; then
    echo "Missing required parameters."
    echo "Usage:"
    echo "  $0 start|restart [-id NAME] script.py [args...]"
    exit 1
fi

case "$ACTION" in
    start)
        start_program "$SCRIPT"
        ;;
    restart)
        restart_program "$SCRIPT"
        ;;
    *)
        echo "Invalid action: $ACTION"
        echo "Usage:"
        echo "  $0 start <script.py>"
        echo "  $0 restart <script.py>"
        exit 1
        ;;
esac
