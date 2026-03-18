OSV_PACKAGES=""
TRIVY_PACKAGES=""

if [ -f osv-report.json ]; then
  OSV_PACKAGES=$(jq -r '.results[]?.packages[]? | select(.vulnerabilities | length > 0) | .package.name // empty' osv-report.json 2>/dev/null | sort -u)
fi

if [ -f trivy-report.json ]; then
  TRIVY_PACKAGES=$(jq -r '
    [
      (.Results[]? | (.Vulnerabilities // .vulnerabilities // [])[]? | .PkgName),
      (.results[]? | (.Vulnerabilities // .vulnerabilities // [])[]? | .PkgName)
    ]
    | flatten
    | .[]?
    | select(. != null and . != "")
  ' trivy-report.json 2>/dev/null | sort -u)
fi

VULNERABLE_PACKAGES=$(printf "%s\n%s\n" "$OSV_PACKAGES" "$TRIVY_PACKAGES" | sed '/^$/d' | sort -u)
echo "OSV vulnerable packages count: $(printf "%s\n" "$OSV_PACKAGES" | sed '/^$/d' | wc -l | tr -d ' ')"
echo "Trivy vulnerable packages count: $(printf "%s\n" "$TRIVY_PACKAGES" | sed '/^$/d' | wc -l | tr -d ' ')"
echo "Merged vulnerable packages count: $(printf "%s\n" "$VULNERABLE_PACKAGES" | sed '/^$/d' | wc -l | tr -d ' ')"

if [ -n "$VULNERABLE_PACKAGES" ]; then
  VULNERABLE_PACKAGES_CSV=$(printf "%s\n" "$VULNERABLE_PACKAGES" | paste -sd, -)
  echo "Vulnerable packages detected: $VULNERABLE_PACKAGES_CSV"

  PACKAGE_ARRAY_JSON=$(printf "%s\n" "$VULNERABLE_PACKAGES" | jq -Rsc 'split("\n") | map(select(length > 0))')
  RENOVATE_PACKAGE_RULES=$(jq -nc \
    --argjson pkgs "$PACKAGE_ARRAY_JSON" \
    '[{"matchPackageNames":$pkgs,"labels":["security","high-priority"],"prPriority":10}]')
  echo "RENOVATE_PACKAGE_RULES=$RENOVATE_PACKAGE_RULES" > /tmp/ci-env-exports.sh
fi
