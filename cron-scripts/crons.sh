#! /bin/sh

# Variables
name="dfs-dev"
phpinterpreter="/usr/bin/php"
pathtoconsole="/var/www/mautic/${name}/bin/console"
lockfile="/tmp/mautic-${name}crons.lock"
logdir="/var/log/mautic/${name}/crons"

# Trap function to ensure cleanup
cleanup() {
    rm -f "$lockfile"
}

trap 'cleanup' EXIT

# Locking mechanism
if [ -f "$lockfile" ]; then
    # Get current time and file modification time
    current_time=$(date +%s)
    file_mod_time=$(date -r "$lockfile" +%s)
    
    # Calculate the difference in time in minutes
    diff_min=$(( (current_time - file_mod_time) / 60 ))

    # Check if the lockfile is older than 10 minutes
    if [ "$diff_min" -gt 10 ]; then
        echo "Lockfile is older than 10 minutes. Ignoring old lock."
        rm -f "$lockfile"  # Remove old lock file
    else
        echo "Script is already running."
        exit 1
    fi
fi
touch "$lockfile"  # Create a new lockfile or refresh the existing one

# Function to time and execute commands
execute_command() {
    command_name=$(echo $1 | cut -d ' ' -f 1 | tr ':' '_')  # Extract and normalize command name for filename
    cmd_logfile="$logdir/${command_name}.log"  # Create log file based on command
    log_output="${2:-true}" # Use default true if no parameter is passed

    START_TIME=$(date +%s%N)

    echo "$(date '+%Y-%m-%d %H:%M:%S') Executing command: $phpinterpreter $pathtoconsole $1" >> "$cmd_logfile"

    # Conditional logging based on the log_output parameter
    if [ "$log_output" = true ]; then
        if ! $phpinterpreter $pathtoconsole $1 >> "$cmd_logfile" 2>&1; then
            echo "Failed to execute $command_name, see $cmd_logfile for details" >> "$cmd_logfile"
            return 1
        fi
    else
        if ! $phpinterpreter $pathtoconsole $1 > /dev/null 2>&1; then
            echo "Failed to execute $command_name. You may want to turn on log_output for this command for easier debugging."
            return 1
        fi
    fi

    END_TIME=$(date +%s%N)
    ELAPSED_TIME=$(( (END_TIME - START_TIME) / 1000000 ))  # Calculate elapsed time in milliseconds
    echo "$(date '+%Y-%m-%d %H:%M:%S') Execution time for $command_name: $ELAPSED_TIME ms" >> "$cmd_logfile"
}

# Ensure the log directory exists
mkdir -p "$logdir"

# Execute commands in sequence
execute_command "mautic:segments:update --batch-limit=900" false
execute_command "mautic:campaigns:update --batch-limit=300" false
execute_command "mautic:campaigns:trigger" false

# Parallel command execution
execute_command "mautic:broadcasts:send --max-threads=3 --thread-id=1 --batch=800" &
execute_command "mautic:broadcasts:send --max-threads=3 --thread-id=2 --batch=800" &
execute_command "mautic:broadcasts:send --max-threads=3 --thread-id=3 --batch=800" &
wait

# Parallel command execution
execute_command "mautic:emails:send --lock-name=thread1 --lock_mode=flock --message-limit=790" &
execute_command "mautic:emails:send --lock-name=thread2 --lock_mode=flock --message-limit=790" &
execute_command "mautic:emails:send --lock-name=thread3 --lock_mode=flock --message-limit=790" &
wait
