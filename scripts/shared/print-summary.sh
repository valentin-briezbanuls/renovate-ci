if [ ! -f combined-report.json ]; then
  echo "No combined report generated"
  exit 0
fi
echo ""
echo "=========================================="
echo "      ${REPORT_HEADER:-RENOVATE SUMMARY}"
echo "=========================================="
jq -r '
  "Generated: " + .report.generated_at,
  "Pipeline:  " + .report.pipeline_id,
  (if .report.target_repo then "Repo:      " + .report.target_repo else empty end),
  "Branch:    " + .report.branch,
  "",
  "SECURITY:",
  "  Vulnerable packages: " + (.security.summary.total_packages_with_vulnerabilities | tostring),
  "  Total vulnerabilities: " + (.security.summary.total_vulnerabilities | tostring),
  "  OSV vulnerabilities: " + (.security.summary.osv_total_vulnerabilities | tostring),
  "  Trivy vulnerabilities: " + (.security.summary.trivy_total_vulnerabilities | tostring),
  (if .security.summary.cves | length > 0 then "  CVEs: " + (.security.summary.cves | join(", ")) else "  No CVEs found" end),
  "",
  "DEPENDENCIES:",
  "  Updates available: " + (.dependencies.summary.total_updates_available | tostring),
  "  Security updates: " + (.dependencies.summary.security_updates | tostring),
  "",
  "NEXT ACTIONS:",
  (.recommendations.priority_actions[] | "  > " + .)
' combined-report.json
echo "=========================================="
