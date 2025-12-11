#!/bin/bash

# Function to display CPU usage
check_cpu() {
    echo "CPU Usage:"
    mpstat | awk '$3 ~ /[0-9.]+/ { printf("  %s%%\n", 100 - $12) }'
}

# Function to display memory usage
check_memory() {
    echo "Memory Usage:"
    free -h | awk '/^Mem:/ { printf("  Used: %s, Total: %s\n", $3, $2) }'
}

# Function to display disk space usage
check_disk() {
    echo "Disk Space Usage:"
    df -h | awk '$NF=="/"{printf("  Used: %s, Total: %s\n", $3, $2)}'
}

# Function to display system uptime
check_uptime() {
    echo "System Uptime:"
    uptime | awk '{print "  " $3, $4, $5}'
}

# Function to display load average
check_load() {
    echo "Load Average:"
    uptime | awk '{print "  1 min: " $10 ", 5 min: " $11 ", 15 min: " $12}'
}

# Function to explain health parameters
explain_parameters() {
    echo "Health Parameters Explanation:"
    echo "1. CPU Usage: Percentage of CPU currently in use."
    echo "2. Memory Usage: Amount of RAM currently in use compared to total available."
    echo "3. Disk Space Usage: Amount of disk space currently in use compared to total available."
    echo "4. System Uptime: Duration the system has been running since the last reboot."
    echo "5. Load Average: Average system load over the last 1, 5, and 15 minutes."
}

# Main script execution
if [ "$1" == "explain" ]; then
    explain_parameters
else
    check_cpu
    check_memory
    check_disk
    check_uptime
    check_load
fi