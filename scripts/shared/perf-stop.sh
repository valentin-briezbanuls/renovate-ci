PERF_OUTPUT="${PERF_OUTPUT_FILE:-perf-metrics.json}"
if [ -f /tmp/perf-monitor.pid ]; then
  PERF_PID=$(cat /tmp/perf-monitor.pid)
  kill "$PERF_PID" 2>/dev/null || true
  sleep 1
  echo "Performance monitor stopped (PID: $PERF_PID)"
fi
if [ -s /tmp/perf-metrics.jsonl ]; then
  echo "Raw JSONL lines: $(wc -l < /tmp/perf-metrics.jsonl)"
  if jq -s '.' /tmp/perf-metrics.jsonl > /tmp/perf-array.json 2>/dev/null; then
    mv /tmp/perf-array.json "$PERF_OUTPUT"
  else
    echo '[]' > "$PERF_OUTPUT"
  fi
  echo "Collected $(jq 'length' "$PERF_OUTPUT" 2>/dev/null || echo 0) performance samples in $PERF_OUTPUT"
else
  echo '[]' > "$PERF_OUTPUT"
  echo "No performance metrics collected"
fi
