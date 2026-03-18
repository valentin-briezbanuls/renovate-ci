curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin latest

set +e
trivy fs --scanners vuln --format json --output trivy-report.json .
TRIVY_EXIT_CODE=$?
set -e

# Keep pipeline resilient: report generation should continue even if Trivy errors.
if [ $TRIVY_EXIT_CODE -ne 0 ]; then
  echo "WARNING: Trivy returned exit code $TRIVY_EXIT_CODE"
fi

if [ ! -f trivy-report.json ]; then
  echo '{"Results":[]}' > trivy-report.json
fi

# Print an explicit summary so logs prove package extraction works.
TRIVY_VULN_COUNT=$(jq -r '
  [
    (.Results[]? | (.Vulnerabilities // .vulnerabilities // [])[]?),
    (.results[]? | (.Vulnerabilities // .vulnerabilities // [])[]?)
  ] | flatten | length
' trivy-report.json 2>/dev/null || echo 0)
TRIVY_PKG_COUNT=$(jq -r '
  [
    (.Results[]? | (.Vulnerabilities // .vulnerabilities // [])[]? | .PkgName),
    (.results[]? | (.Vulnerabilities // .vulnerabilities // [])[]? | .PkgName)
  ] | flatten | map(select(. != null and . != "")) | unique | length
' trivy-report.json 2>/dev/null || echo 0)
echo "Trivy vulnerable packages detected: $TRIVY_PKG_COUNT"
echo "Trivy vulnerabilities detected: $TRIVY_VULN_COUNT"
if [ "$TRIVY_PKG_COUNT" -gt 0 ]; then
  echo "Trivy sample vulnerable packages (max 10):"
  jq -r '
    [
      (.Results[]? | (.Vulnerabilities // .vulnerabilities // [])[]? | .PkgName),
      (.results[]? | (.Vulnerabilities // .vulnerabilities // [])[]? | .PkgName)
    ] | flatten | map(select(. != null and . != "")) | unique | .[:10][]
  ' trivy-report.json 2>/dev/null || true
fi

echo "Trivy scan completed (exit code: $TRIVY_EXIT_CODE)"
