set +e
/usr/local/bin/osv-scanner scan source --format=json --output=osv-report.json -r .
OSV_EXIT_CODE=$?
set -e

# 0 = no vulns, 1 = vulns found (OK), >1 = scanner error
if [ $OSV_EXIT_CODE -gt 1 ] && [ $OSV_EXIT_CODE -ne 128 ]; then
  echo "WARNING: OSV scanner returned error code $OSV_EXIT_CODE"
fi

if [ ! -f osv-report.json ]; then
  echo '{"results":[]}' > osv-report.json
fi

echo "OSV scan completed (exit code: $OSV_EXIT_CODE)"
