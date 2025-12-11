# Usage Instructions for VM Health Check Script

## Overview
The `healthcheck.sh` script is designed to monitor the health of your virtual machine (VM) by checking various system parameters. It provides insights into CPU usage, memory usage, disk space usage, system uptime, and load average.

## Running the Script
To execute the health check script, navigate to the `scripts` directory in your terminal and run the following command:

```bash
./healthcheck.sh
```

## Command-Line Arguments
The script accepts one optional command-line argument:

- `explain`: When this argument is provided, the script will display detailed explanations of each health parameter being checked.

### Example Usage
To run the health check without explanations:

```bash
./healthcheck.sh
```

To run the health check with explanations:

```bash
./healthcheck.sh explain
```

## Output
The script will output the following health parameters:

- **CPU Usage**: Percentage of CPU currently in use.
- **Memory Usage**: Amount of memory currently in use versus total available memory.
- **Disk Space Usage**: Percentage of disk space currently in use.
- **System Uptime**: Duration for which the system has been running since the last reboot.
- **Load Average**: Average system load over the last 1, 5, and 15 minutes.

Ensure that the script has executable permissions. You can set this by running:

```bash
chmod +x healthcheck.sh
```

## Conclusion
Use the `healthcheck.sh` script regularly to monitor the health of your VM and ensure optimal performance.