#! /bin/sh

# Variables
name="dfs-dev"
phpinterpreter="/usr/bin/php"
pathtoconsole="/var/www/mautic/${name}/bin/console"
logdir="/var/log/mautic/${name}/crons"
lockfile="/tmp/mautic-${name}crons.lock"

# Ensure the log directory exists
mkdir -p "$logdir"

(
    # Try to acquire the lock
    if ! flock -n 9; then
        echo "Script is already running."
        exit 1
    fi

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

    # Execute commands in sequence
    execute_command "mautic:segments:update --batch-limit=900" false
    execute_command "mautic:campaigns:update --batch-limit=300" false
    execute_command "mautic:campaigns:trigger" false

    # Parallel command execution
    execute_command "mautic:broadcasts:send --max-threads=4 --thread-id=1 --batch=800" &
    execute_command "mautic:broadcasts:send --max-threads=4 --thread-id=2 --batch=800" &
    execute_command "mautic:broadcasts:send --max-threads=4 --thread-id=3 --batch=800" &
    execute_command "mautic:broadcasts:send --max-threads=4 --thread-id=4 --batch=800" &
    wait

    # Parallel command execution
    execute_command "mautic:emails:send --lock-name=thread1 --lock_mode=flock --message-limit=790" &
    execute_command "mautic:emails:send --lock-name=thread2 --lock_mode=flock --message-limit=790" &
    execute_command "mautic:emails:send --lock-name=thread3 --lock_mode=flock --message-limit=790" &
    execute_command "mautic:emails:send --lock-name=thread4 --lock_mode=flock --message-limit=790" &
    wait

) 9>"$lockfile"
