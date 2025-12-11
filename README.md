# VM Health Check

## Overview
The VM Health Check project provides a Bash script that monitors various health parameters of a virtual machine (VM). This includes checking CPU usage, memory usage, disk space usage, system uptime, and load average. The script is designed to help system administrators ensure that their VMs are running optimally.

## Features
- Checks CPU usage
- Monitors memory usage
- Reports disk space usage
- Displays system uptime
- Shows load average
- Provides detailed explanations of each health parameter with the `explain` argument

## Prerequisites
- A Unix-like operating system (Linux, macOS)
- Bash shell
- Basic command-line knowledge

## Installation
1. Clone the repository:
   ```
   git clone https://github.com/yourusername/vm-healthcheck.git
   ```
2. Navigate to the project directory:
   ```
   cd vm-healthcheck
   ```

## Usage
To run the health check script, use the following command:
```
bash scripts/healthcheck.sh
```

To get detailed explanations of each health parameter, use the `explain` argument:
```
bash scripts/healthcheck.sh explain
```

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License. See the LICENSE file for more details.