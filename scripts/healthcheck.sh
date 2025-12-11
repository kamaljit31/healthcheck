#!/usr/bin/env bash
# healthcheck.sh - lightweight VM health checker
# Checks: CPU usage, Memory usage, Disk usage, Uptime, Load average

set -u

SCRIPT_NAME="healthcheck.sh"

# Thresholds (percent or multiples)
CPU_WARN=70
CPU_CRIT=85
MEM_WARN=75
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=90

# Colors (optional if terminal supports)
if [ -t 1 ]; then
  RED=$(printf "\033[31m")
  YELLOW=$(printf "\033[33m")
  GREEN=$(printf "\033[32m")
  BOLD=$(printf "\033[1m")
  RESET=$(printf "\033[0m")
else
  RED=""; YELLOW=""; GREEN=""; BOLD=""; RESET=""
fi

die() { printf "%s\n" "$*" >&2; exit 2; }

usage(){
  cat <<EOF
Usage: ./${SCRIPT_NAME} [explain]

Without arguments prints a clean health summary for CPU, Memory, Disk, Uptime and Load.
When run with the argument "explain" (./${SCRIPT_NAME} explain) the script prints a detailed
explanation of each parameter and recommended thresholds.
EOF
}

get_cpu_usage(){
  # Read /proc/stat twice and compute utilization over a short interval
  if [ -r /proc/stat ]; then
    read -r cpu a b c d e f g h < /proc/stat || return 1
    prev_total=$((a+b+c+d+e+f+g+h))
    prev_idle=$d
    sleep 0.2
    read -r cpu a b c d e f g h < /proc/stat || return 1
    total=$((a+b+c+d+e+f+g+h))
    idle=$d
    diff_total=$((total - prev_total))
    diff_idle=$((idle - prev_idle))
    if [ "$diff_total" -le 0 ]; then
      echo "0.0"
    else
      usage=$(awk "BEGIN {printf \"%.1f\", (1 - $diff_idle / $diff_total) * 100}")
      echo "$usage"
    fi
  else
    # fallback: use top one-shot (may not be available everywhere)
    top -bn1 | awk '/Cpu\(s\):/ {print $2+$4+$6}' | head -n1 || echo "N/A"
  fi
}

get_mem_usage(){
  if [ -r /proc/meminfo ]; then
    # MemAvailable is best if present
    mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo)
    if [ -z "$mem_avail_kb" ]; then
      # fallback to MemFree + Buffers + Cached
      mem_free_kb=$(awk '/MemFree:/ {print $2; exit}' /proc/meminfo)
      buffers_kb=$(awk '/Buffers:/ {print $2; exit}' /proc/meminfo)
      cached_kb=$(awk '/^Cached:/ {print $2; exit}' /proc/meminfo)
      mem_avail_kb=$((mem_free_kb + buffers_kb + cached_kb))
    fi
    used_kb=$((mem_total_kb - mem_avail_kb))
    used_pct=$(awk "BEGIN {printf \"%.1f\", $used_kb / $mem_total_kb * 100}")
    echo "$used_pct $used_kb $mem_total_kb"
  else
    # fallback to free (if present)
    free -m | awk 'NR==2 {printf "%.1f %d %d", ($3/$2)*100, $3, $2}' || echo "N/A 0 0"
  fi
}

get_disk_usage(){
  # Report usage for filesystem containing '/'
  df -h --output=pcent,size,used,avail,target / 2>/dev/null | awk 'NR==2{gsub("%","",$1); printf "%s %s %s %s", $1, $2, $3, $4; exit}' || {
    # fallback
    df -h / | awk 'NR==2{gsub("%","",$5); printf "%s %s %s %s", $5, $2, $3, $4}'
  }
}

get_uptime(){
  if command -v uptime >/dev/null 2>&1; then
    # prefer pretty uptime if available
    uptime -p 2>/dev/null || uptime
  elif [ -r /proc/uptime ]; then
    awk '{secs=int($1); days=int(secs/86400); hrs=int((secs%86400)/3600); mins=int((secs%3600)/60); printf "%dd %dh %dm", days, hrs, mins}' /proc/uptime
  else
    echo "N/A"
  fi
}

get_loadavg(){
  if [ -r /proc/loadavg ]; then
    awk '{print $1" "$2" "$3}' /proc/loadavg
  else
    uptime | awk -F'load average:' '{print $2}' | sed 's/,//g' | awk '{print $1" "$2" "$3}'
  fi
}

status_color(){
  # args: numeric_value warning_threshold critical_threshold
  local val=$1; local warn=$2; local crit=$3
  if awk "BEGIN{exit !($val >= $crit)}"; then
    printf "%sCRITICAL%s" "$RED" "$RESET"
  elif awk "BEGIN{exit !($val >= $warn)}"; then
    printf "%sWARNING%s" "$YELLOW" "$RESET"
  else
    printf "%sOK%s" "$GREEN" "$RESET"
  fi
}

explain(){
  cat <<'EXPLAIN'
Detailed explanation of parameters:

CPU usage:
  - What: Percent of CPU time spent doing non-idle work across all CPUs.
  - Why it matters: High sustained CPU usage may indicate a process is saturating the CPU,
    causing slow response or throttling. Short spikes are normal; sustained high usage is a concern.
  - Thresholds: WARN=70%, CRIT=85%.

Memory usage:
  - What: Percent of physical memory currently in use (accounts for cached/buffered memory where possible).
  - Why it matters: If RAM usage nears capacity, the system may start swapping which drastically reduces performance.
  - Thresholds: WARN=75%, CRIT=90%.

Disk usage (root '/'): 
  - What: Percent of disk space used on the filesystem hosting '/'.
  - Why it matters: When disk usage is high, processes may fail to write data, logs, or updates; services can break.
  - Thresholds: WARN=80%, CRIT=90%.

Uptime:
  - What: How long the system has been running since last boot.
  - Why it matters: Very short uptimes can indicate instability or frequent reboots. Long uptime itself isn't a problem,
    but can be used with other signals to diagnose reliability.

Load average:
  - What: The average number of runnable processes (demand for CPU) over 1, 5, and 15 minutes.
  - Why it matters: Compare load average to number of CPU cores. A load much higher than core count suggests CPU-bound backlog.
  - Example rule: WARN when 1-minute load > cores * 0.7; CRIT when > cores * 1.5.

EXPLAIN
}

main(){
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage; exit 0
  fi

  if [ "${1:-}" = "explain" ]; then
    explain
    exit 0
  fi

  # Gather metrics
  cpu_usage=$(get_cpu_usage) || cpu_usage="N/A"
  read -r mem_pct mem_used_k mem_total_k <<< "$(get_mem_usage)"
  read -r disk_pct disk_size disk_used disk_avail <<< "$(get_disk_usage)"
  uptime_str=$(get_uptime)
  read -r load1 load5 load15 <<< "$(get_loadavg)"
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

  # Compute load thresholds
  load_warn=$(awk "BEGIN{printf \"%.2f\", $cores * 0.7}")
  load_crit=$(awk "BEGIN{printf \"%.2f\", $cores * 1.5}")

  # Print clean header
  printf "%s\n" "========================================"
  printf "%s\n" " VM HEALTH CHECK SUMMARY"
  printf "%s\n" "========================================"
  printf "%s: %s\n" "Checked" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  printf "%s\n" ""

  # CPU
  if [ "$cpu_usage" = "N/A" ]; then
    cpu_status="N/A"
  else
    cpu_status=$(status_color "$cpu_usage" $CPU_WARN $CPU_CRIT)
  fi
  printf "%-15s %-12s %s\n" "CPU usage" "${cpu_usage}%" "$cpu_status"

  # Memory
  if [ "$mem_pct" = "N/A" ] || [ -z "$mem_pct" ]; then
    mem_status="N/A"
    mem_display="N/A"
  else
    mem_status=$(status_color "$mem_pct" $MEM_WARN $MEM_CRIT)
    mem_used_mb=$((mem_used_k/1024))
    mem_total_mb=$((mem_total_k/1024))
    mem_display="${mem_used_mb}MB/${mem_total_mb}MB (${mem_pct}%)"
  fi
  printf "%-15s %-30s %s\n" "Memory usage" "$mem_display" "$mem_status"

  # Disk
  if [ -z "$disk_pct" ]; then
    disk_status="N/A"
    disk_display="N/A"
  else
    disk_status=$(status_color "$disk_pct" $DISK_WARN $DISK_CRIT)
    disk_display="${disk_used}/${disk_size} (avail ${disk_avail})"
  fi
  printf "%-15s %-30s %s\n" "Disk '/' usage" "${disk_pct}% - ${disk_display}" "$disk_status"

  # Load average
  load_status=$(awk "BEGIN{if($load1 >= $load_crit) print \"CRITICAL\"; else if($load1 >= $load_warn) print \"WARNING\"; else print \"OK\"}")
  # colorize load_status
  case "$load_status" in
    CRITICAL) load_status_col="${RED}${load_status}${RESET}";;
    WARNING) load_status_col="${YELLOW}${load_status}${RESET}";;
    *) load_status_col="${GREEN}${load_status}${RESET}";;
  esac
  printf "%-15s %-20s %s\n" "Load (1/5/15)" "${load1} ${load5} ${load15}" "${load_status_col} (cores=${cores})"

  # Uptime
  printf "%-15s %s\n" "Uptime" "${uptime_str}"

  printf "%s\n" ""
  printf "Legend: %sOK%s, %sWARNING%s, %sCRITICAL%s\n" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"
  printf "%s\n" "========================================"
}

main "${1:-}"
#!/usr/bin/env bash
# healthcheck.sh - lightweight VM health checker
# Checks: CPU usage, Memory usage, Disk usage, Uptime, Load average

set -u

SCRIPT_NAME="healthcheck.sh"

# Thresholds (percent or multiples)
CPU_WARN=70
CPU_CRIT=85
MEM_WARN=75
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=90

# Colors (optional if terminal supports)
if [ -t 1 ]; then
  RED=$(printf "\033[31m")
  YELLOW=$(printf "\033[33m")
  GREEN=$(printf "\033[32m")
  BOLD=$(printf "\033[1m")
  RESET=$(printf "\033[0m")
else
  RED=""; YELLOW=""; GREEN=""; BOLD=""; RESET=""
fi

die() { printf "%s\n" "$*" >&2; exit 2; }

usage(){
  cat <<EOF
Usage: ./${SCRIPT_NAME} [explain]

Without arguments prints a clean health summary for CPU, Memory, Disk, Uptime and Load.
When run with the argument "explain" (./${SCRIPT_NAME} explain) the script prints a detailed
explanation of each parameter and recommended thresholds.
EOF
}

get_cpu_usage(){
  # Read /proc/stat twice and compute utilization over a short interval
  if [ -r /proc/stat ]; then
    read -r cpu a b c d e f g h < /proc/stat || return 1
    prev_total=$((a+b+c+d+e+f+g+h))
    prev_idle=$d
    sleep 0.2
    read -r cpu a b c d e f g h < /proc/stat || return 1
    total=$((a+b+c+d+e+f+g+h))
    idle=$d
    diff_total=$((total - prev_total))
    diff_idle=$((idle - prev_idle))
    if [ "$diff_total" -le 0 ]; then
      echo "0.0"
    else
      usage=$(awk "BEGIN {printf \"%.1f\", (1 - $diff_idle / $diff_total) * 100}")
      echo "$usage"
    fi
  else
    # fallback: use top one-shot (may not be available everywhere)
    top -bn1 | awk '/Cpu\(s\):/ {print $2+$4+$6}' | head -n1 || echo "N/A"
  fi
}

get_mem_usage(){
  if [ -r /proc/meminfo ]; then
    # MemAvailable is best if present
    mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail_kb=$(awk '/MemAvailable:/ {print $2; exit}' /proc/meminfo)
    if [ -z "$mem_avail_kb" ]; then
      # fallback to MemFree + Buffers + Cached
      mem_free_kb=$(awk '/MemFree:/ {print $2; exit}' /proc/meminfo)
      buffers_kb=$(awk '/Buffers:/ {print $2; exit}' /proc/meminfo)
      cached_kb=$(awk '/^Cached:/ {print $2; exit}' /proc/meminfo)
      mem_avail_kb=$((mem_free_kb + buffers_kb + cached_kb))
    fi
    used_kb=$((mem_total_kb - mem_avail_kb))
    used_pct=$(awk "BEGIN {printf \"%.1f\", $used_kb / $mem_total_kb * 100}")
    echo "$used_pct $used_kb $mem_total_kb"
  else
    # fallback to free (if present)
    free -m | awk 'NR==2 {printf "%.1f %d %d", ($3/$2)*100, $3, $2}' || echo "N/A 0 0"
  fi
}

get_disk_usage(){
  # Report usage for filesystem containing '/'
  df -h --output=pcent,size,used,avail,target / 2>/dev/null | awk 'NR==2{gsub("%","",$1); printf "%s %s %s %s", $1, $2, $3, $4; exit}' || {
    # fallback
    df -h / | awk 'NR==2{gsub("%","",$5); printf "%s %s %s %s", $5, $2, $3, $4}'
  }
}

get_uptime(){
  if command -v uptime >/dev/null 2>&1; then
    # prefer pretty uptime if available
    uptime -p 2>/dev/null || uptime
  elif [ -r /proc/uptime ]; then
    awk '{secs=int($1); days=int(secs/86400); hrs=int((secs%86400)/3600); mins=int((secs%3600)/60); printf "%dd %dh %dm", days, hrs, mins}' /proc/uptime
  else
    echo "N/A"
  fi
}

get_loadavg(){
  if [ -r /proc/loadavg ]; then
    awk '{print $1" "$2" "$3}' /proc/loadavg
  else
    uptime | awk -F'load average:' '{print $2}' | sed 's/,//g' | awk '{print $1" "$2" "$3}'
  fi
}

status_color(){
  # args: numeric_value warning_threshold critical_threshold
  local val=$1; local warn=$2; local crit=$3
  if awk "BEGIN{exit !($val >= $crit)}"; then
    printf "%sCRITICAL%s" "$RED" "$RESET"
  elif awk "BEGIN{exit !($val >= $warn)}"; then
    printf "%sWARNING%s" "$YELLOW" "$RESET"
  else
    printf "%sOK%s" "$GREEN" "$RESET"
  fi
}

explain(){
  cat <<'EXPLAIN'
Detailed explanation of parameters:

CPU usage:
  - What: Percent of CPU time spent doing non-idle work across all CPUs.
  - Why it matters: High sustained CPU usage may indicate a process is saturating the CPU,
    causing slow response or throttling. Short spikes are normal; sustained high usage is a concern.
  - Thresholds: WARN=70%, CRIT=85%.

Memory usage:
  - What: Percent of physical memory currently in use (accounts for cached/buffered memory where possible).
  - Why it matters: If RAM usage nears capacity, the system may start swapping which drastically reduces performance.
  - Thresholds: WARN=75%, CRIT=90%.

Disk usage (root '/'): 
  - What: Percent of disk space used on the filesystem hosting '/'.
  - Why it matters: When disk usage is high, processes may fail to write data, logs, or updates; services can break.
  - Thresholds: WARN=80%, CRIT=90%.

Uptime:
  - What: How long the system has been running since last boot.
  - Why it matters: Very short uptimes can indicate instability or frequent reboots. Long uptime itself isn't a problem,
    but can be used with other signals to diagnose reliability.

Load average:
  - What: The average number of runnable processes (demand for CPU) over 1, 5, and 15 minutes.
  - Why it matters: Compare load average to number of CPU cores. A load much higher than core count suggests CPU-bound backlog.
  - Example rule: WARN when 1-minute load > cores * 0.7; CRIT when > cores * 1.5.

EXPLAIN
}

main(){
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage; exit 0
  fi

  if [ "${1:-}" = "explain" ]; then
    explain
    exit 0
  fi

  # Gather metrics
  cpu_usage=$(get_cpu_usage) || cpu_usage="N/A"
  read -r mem_pct mem_used_k mem_total_k <<< "$(get_mem_usage)"
  read -r disk_pct disk_size disk_used disk_avail <<< "$(get_disk_usage)"
  uptime_str=$(get_uptime)
  read -r load1 load5 load15 <<< "$(get_loadavg)"
  cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)

  # Compute load thresholds
  load_warn=$(awk "BEGIN{printf \"%.2f\", $cores * 0.7}")
  load_crit=$(awk "BEGIN{printf \"%.2f\", $cores * 1.5}")

  # Print clean header
  printf "%s\n" "========================================"
  printf "%s\n" " VM HEALTH CHECK SUMMARY"
  printf "%s\n" "========================================"
  printf "%s: %s\n" "Checked" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  printf "%s\n" ""

  # CPU
  if [ "$cpu_usage" = "N/A" ]; then
    cpu_status="N/A"
  else
    cpu_status=$(status_color "$cpu_usage" $CPU_WARN $CPU_CRIT)
  fi
  printf "%-15s %-12s %s\n" "CPU usage" "${cpu_usage}%" "$cpu_status"

  # Memory
  if [ "$mem_pct" = "N/A" ] || [ -z "$mem_pct" ]; then
    mem_status="N/A"
    mem_display="N/A"
  else
    mem_status=$(status_color "$mem_pct" $MEM_WARN $MEM_CRIT)
    mem_used_mb=$((mem_used_k/1024))
    mem_total_mb=$((mem_total_k/1024))
    mem_display="${mem_used_mb}MB/${mem_total_mb}MB (${mem_pct}%)"
  fi
  printf "%-15s %-30s %s\n" "Memory usage" "$mem_display" "$mem_status"

  # Disk
  if [ -z "$disk_pct" ]; then
    disk_status="N/A"
    disk_display="N/A"
  else
    disk_status=$(status_color "$disk_pct" $DISK_WARN $DISK_CRIT)
    disk_display="${disk_used}/${disk_size} (avail ${disk_avail})"
  fi
  printf "%-15s %-30s %s\n" "Disk '/' usage" "${disk_pct}% - ${disk_display}" "$disk_status"

  # Load average
  load_status=$(awk "BEGIN{if($load1 >= $load_crit) print \"CRITICAL\"; else if($load1 >= $load_warn) print \"WARNING\"; else print \"OK\"}")
  # colorize load_status
  case "$load_status" in
    CRITICAL) load_status_col="${RED}${load_status}${RESET}";;
    WARNING) load_status_col="${YELLOW}${load_status}${RESET}";;
    *) load_status_col="${GREEN}${load_status}${RESET}";;
  esac
  printf "%-15s %-20s %s\n" "Load (1/5/15)" "${load1} ${load5} ${load15}" "${load_status_col} (cores=${cores})"

  # Uptime
  printf "%-15s %s\n" "Uptime" "${uptime_str}"

  printf "%s\n" ""
  printf "Legend: %sOK%s, %sWARNING%s, %sCRITICAL%s\n" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"
  printf "%s\n" "========================================"
}

main "${1:-}"
