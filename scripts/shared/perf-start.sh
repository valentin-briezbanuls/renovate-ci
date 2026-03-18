rm -f /tmp/perf-metrics.jsonl
touch /tmp/perf-metrics.jsonl
(
  if [ -f /sys/fs/cgroup/cpu.stat ]; then CGROUP_V2=true; else CGROUP_V2=false; fi
  if date +%s%N 2>/dev/null | grep -q 'N$'; then HAS_NANO=false; else HAS_NANO=true; fi
  PREV_CPU_USAGE=0
  PREV_TIMESTAMP_NS=0
  while true; do
    if [ "$CGROUP_V2" = true ]; then
      CPU_USAGE_US=$(awk '/^usage_usec/ {print $2}' /sys/fs/cgroup/cpu.stat 2>/dev/null || echo 0)
      CPU_USAGE_NS=$((CPU_USAGE_US * 1000))
    else
      CPU_USAGE_NS=$(cat /sys/fs/cgroup/cpuacct/cpuacct.usage 2>/dev/null || cat /sys/fs/cgroup/cpu,cpuacct/cpuacct.usage 2>/dev/null || echo 0)
    fi
    if [ "$HAS_NANO" = true ]; then
      CURRENT_NS=$(date +%s%N 2>/dev/null || echo 0)
    else
      CURRENT_NS=$(date +%s 2>/dev/null || echo 0)000000000
    fi
    if [ "$PREV_CPU_USAGE" -gt 0 ] 2>/dev/null && [ "$PREV_TIMESTAMP_NS" -gt 0 ] 2>/dev/null; then
      DELTA_CPU=$((CPU_USAGE_NS - PREV_CPU_USAGE)) 2>/dev/null || DELTA_CPU=0
      DELTA_TIME=$((CURRENT_NS - PREV_TIMESTAMP_NS)) 2>/dev/null || DELTA_TIME=0
      if [ "$DELTA_TIME" -gt 0 ] 2>/dev/null; then
        CPU_PERCENT=$((DELTA_CPU * 100 / DELTA_TIME)) 2>/dev/null || CPU_PERCENT=0
      else
        CPU_PERCENT=0
      fi
    else
      CPU_PERCENT=0
    fi
    PREV_CPU_USAGE=$CPU_USAGE_NS
    PREV_TIMESTAMP_NS=$CURRENT_NS
    if [ "$CGROUP_V2" = true ]; then
      RAM_USED_BYTES=$(awk '/^anon / {print $2}' /sys/fs/cgroup/memory.stat 2>/dev/null || echo 0)
      RAM_LIMIT_BYTES=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo 0)
    else
      RAM_USED_BYTES=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.usage_in_bytes 2>/dev/null || echo 0)
      RAM_LIMIT_BYTES=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || cat /sys/fs/cgroup/memory.limit_in_bytes 2>/dev/null || echo 0)
    fi
    if [ "$RAM_LIMIT_BYTES" = "max" ] || [ "$RAM_LIMIT_BYTES" -gt 100000000000 ] 2>/dev/null; then
      RAM_TOTAL_MB=$(awk '/^MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)
    else
      RAM_TOTAL_MB=$((RAM_LIMIT_BYTES / 1024 / 1024)) 2>/dev/null || RAM_TOTAL_MB=0
    fi
    RAM_USED_MB=$((RAM_USED_BYTES / 1024 / 1024)) 2>/dev/null || RAM_USED_MB=0
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TOP_PROCS=$(ps -eo pid,%cpu,rss,comm --no-headers --sort=-rss 2>/dev/null \
      | head -5 \
      | awk '{pid=$1; cpu=$2; ram_mb=int($3/1024); cmd=$4; printf "{\"pid\":%s,\"cpu\":%s,\"ram_mb\":%d,\"command\":\"%s\"},", pid, cpu, ram_mb, cmd}' \
      | sed 's/,$//' 2>/dev/null || true)
    echo "{\"timestamp\":\"$TIMESTAMP\",\"cpu_percent\":$CPU_PERCENT,\"ram_used_mb\":$RAM_USED_MB,\"ram_total_mb\":$RAM_TOTAL_MB,\"top_processes\":[$TOP_PROCS]}" >> /tmp/perf-metrics.jsonl
    sleep 5
  done
) &
echo $! > /tmp/perf-monitor.pid
disown $(cat /tmp/perf-monitor.pid) 2>/dev/null || true
echo "Performance monitor started (PID: $(cat /tmp/perf-monitor.pid))"
