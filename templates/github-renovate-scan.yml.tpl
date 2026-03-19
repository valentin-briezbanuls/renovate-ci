# =============================================================================
# GENERATED FILE — do not edit directly.
# Source: templates/github-renovate-scan.yml.tpl + scripts/shared/
# Regenerate: bash scripts/generate.sh
# =============================================================================
# Reusable GitHub Actions workflow — Renovate + OSV/Trivy scan
# =============================================================================
# Customer repos call this with `uses:`. All scanning runs on the customer's
# own GitHub Actions runners — no code ever leaves their infrastructure.
#
# Usage in customer repo (.github/workflows/renovate.yml):
#
#   name: Renovate
#   on:
#     workflow_dispatch:
#     schedule:
#       - cron: '0 3 * * 1'
#   permissions:
#     pull-requests: write
#     contents: write
#   jobs:
#     renovate:
#       uses: valentin-briezbanuls/renovate-ci/.github/workflows/renovate-scan.yml@main
#       secrets:
#         RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN || github.token }}
#         DASHBOARD_WEBHOOK_URL: ${{ secrets.RENOVATE_DASHBOARD_WEBHOOK_URL }}
# =============================================================================

name: Renovate Scan

on:
  workflow_dispatch:
    inputs:
      target_base_branch:
        description: "Base branch to scan"
        type: string
        default: "main"
      dry_run_mode:
        description: "Renovate dry-run mode: lookup | full | false"
        type: string
        default: "lookup"
  workflow_call:
    inputs:
      target_base_branch:
        description: "Base branch to scan"
        type: string
        default: "main"
      dry_run_mode:
        description: "Renovate dry-run mode: lookup | full | false"
        type: string
        default: "lookup"
    secrets:
      RENOVATE_TOKEN:
        description: "GitHub PAT with repo scope — or omit to use the automatic GITHUB_TOKEN"
        required: false
      DASHBOARD_WEBHOOK_URL:
        description: "Full URL to POST combined-report.json back to the dashboard"
        required: false

permissions:
  pull-requests: write
  contents: write
  issues: write

jobs:
  # ---------------------------------------------------------------------------
  # OSV vulnerability scan
  # ---------------------------------------------------------------------------
  osv_scan:
    name: OSV Vulnerability Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          export DEBIAN_FRONTEND=noninteractive
          sudo apt-get update -qq
          sudo apt-get install -y jq procps

      - name: Install OSV scanner
        run: |
          wget -q https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 -O /usr/local/bin/osv-scanner
          chmod +x /usr/local/bin/osv-scanner

      - name: Start performance monitor
        run: |
##EMBED:perf-start.sh INDENT=10##

      - name: Generate Gradle lockfiles if needed
        run: |
##EMBED:gradle-lockfile.sh INDENT=10##

      - name: Run OSV scan
        run: |
##EMBED:osv-scan.sh INDENT=10##

      - name: Stop performance monitor
        if: always()
        run: |
          PERF_OUTPUT_FILE=osv-perf-metrics.json
##EMBED:perf-stop.sh INDENT=10##

      - name: Upload OSV report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: osv-report
          path: |
            osv-report.json
            osv-perf-metrics.json
          retention-days: 7

  # ---------------------------------------------------------------------------
  # Trivy vulnerability scan — iOS/CocoaPods/SPM
  # ---------------------------------------------------------------------------
  trivy_scan:
    name: Trivy Vulnerability Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          export DEBIAN_FRONTEND=noninteractive
          sudo apt-get update -qq
          sudo apt-get install -y jq procps

      - name: Start performance monitor
        run: |
##EMBED:perf-start.sh INDENT=10##

      - name: Check for iOS lockfiles and run Trivy
        run: |
          HAS_IOS=false
          if [ -f Podfile.lock ] || [ -f Package.resolved ] || [ -f Cartfile.resolved ]; then
            HAS_IOS=true
          fi
          echo "iOS lockfiles detected: $HAS_IOS"

          if [ "$HAS_IOS" = "true" ]; then
##EMBED:trivy-scan.sh INDENT=12##
          else
            echo "No iOS lockfiles detected — skipping Trivy scan."
            echo '{"Results":[]}' > trivy-report.json
          fi

      - name: Stop performance monitor
        if: always()
        run: |
          PERF_OUTPUT_FILE=trivy-perf-metrics.json
##EMBED:perf-stop.sh INDENT=10##

      - name: Upload Trivy report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: trivy-report
          path: |
            trivy-report.json
            trivy-perf-metrics.json
          retention-days: 7

  # ---------------------------------------------------------------------------
  # Renovate run — uses scan results, opens PRs, posts report to dashboard
  # ---------------------------------------------------------------------------
  renovate_run:
    name: Renovate
    runs-on: ubuntu-latest
    needs: [osv_scan, trivy_scan]
    if: ${{ !cancelled() }}
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          export DEBIAN_FRONTEND=noninteractive
          sudo apt-get update -qq
          sudo apt-get install -y jq procps

      - name: Download OSV report
        uses: actions/download-artifact@v4
        with:
          name: osv-report
          path: .
        continue-on-error: true

      - name: Download Trivy report
        uses: actions/download-artifact@v4
        with:
          name: trivy-report
          path: .
        continue-on-error: true

      - name: Start performance monitor
        run: |
##EMBED:perf-start.sh INDENT=10##

      - name: Prioritize vulnerable packages
        run: |
##EMBED:prioritize-packages.sh INDENT=10##
          # Import env vars from shared script (GitHub: write to $GITHUB_ENV)
          if [ -f /tmp/ci-env-exports.sh ]; then
            while IFS='=' read -r key value; do
              [ -z "$key" ] && continue
              echo "$key=$value" >> "$GITHUB_ENV"
            done < /tmp/ci-env-exports.sh
          fi

      - name: Detect managers and build Renovate config
        run: |
          # Check for existing renovate config in the repo
          FOUND_CONFIG=""
          for cfg in renovate.json .renovaterc .renovaterc.json .github/renovate.json .github/.renovaterc; do
            if [ -f "$cfg" ]; then
              FOUND_CONFIG="$cfg"
              echo "Found Renovate config: $cfg"
              break
            fi
          done

          if [ -n "$FOUND_CONFIG" ]; then
            echo "RENOVATE_HAS_CONFIG=true" >> "$GITHUB_ENV"
          else
##EMBED:detect-managers.sh INDENT=12##
            # Import detected managers
            if [ -f /tmp/ci-env-exports.sh ]; then
              . /tmp/ci-env-exports.sh
            fi

            RENOVATE_CONFIG='{"$schema":"https://docs.renovatebot.com/renovate-schema.json","extends":["config:recommended"],"enabled":true,"timezone":"Europe/Paris","automerge":false,"prHourlyLimit":10,"prConcurrentLimit":5,"ignorePaths":[".build/**","**/node_modules/**","**/Pods/**"],"osvVulnerabilityAlerts":true,"vulnerabilityAlerts":{"enabled":true,"labels":["security","vulnerability","high-priority"]},"dependencyDashboard":true,"reportTags":["security"],"rangeStrategy":"auto","postUpdateOptions":["bundlerConservative"],'
            if [ -n "$MANAGERS" ]; then
              RENOVATE_CONFIG="${RENOVATE_CONFIG}\"enabledManagers\":[$MANAGERS],"
            fi
            RENOVATE_CONFIG="${RENOVATE_CONFIG}\"packageRules\":[$PACKAGE_RULES],\"commitMessagePrefix\":\"chore:\",\"commitMessageAction\":\"update\",\"commitMessageTopic\":\"{{depName}}\",\"commitMessageExtra\":\"to {{newVersion}}{{#if isVulnerabilityAlert}} (security){{/if}}\"}"
            echo "RENOVATE_CONFIG=$RENOVATE_CONFIG" >> "$GITHUB_ENV"
            echo "Using centralized inline Renovate config (no renovate.json found in target repo)"
          fi

      - name: Determine dry-run flag
        run: |
          DRY_RUN_INPUT="${{ inputs.dry_run_mode }}"
          DRY_RUN_INPUT="${DRY_RUN_INPUT:-lookup}"

          if [ "${DRY_RUN_INPUT}" = "full" ]; then
            echo "RENOVATE_DRY_RUN=full" >> "$GITHUB_ENV"
            echo "Renovate dry-run mode: full"
          elif [ "${DRY_RUN_INPUT}" = "false" ]; then
            # Real mode: do NOT set RENOVATE_DRY_RUN — Renovate defaults to real mode when unset
            echo "Renovate dry-run mode: real (RENOVATE_DRY_RUN not set)"
          else
            echo "RENOVATE_DRY_RUN=lookup" >> "$GITHUB_ENV"
            echo "Renovate dry-run mode: lookup"
          fi

      - name: Set target repository for Renovate
        run: |
          REPO="${{ github.repository }}"
          echo "RENOVATE_REPOSITORIES=$REPO" >> "$GITHUB_ENV"
          echo "Renovate will scan: $REPO"

      - name: Run Renovate
        uses: renovatebot/github-action@v46.1.5
        env:
          RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN || github.token }}
          RENOVATE_PLATFORM: github
          RENOVATE_GIT_AUTHOR: "Renovate Bot <renovate@isee-u.fr>"
          RENOVATE_REPOSITORY_CACHE: enabled
          RENOVATE_BASE_BRANCHES: ${{ inputs.target_base_branch }}
          LOG_LEVEL: debug
          RENOVATE_EXPORT_SUMMARY: "true"
          RENOVATE_REPORT_PATH: renovate-report.json
          RENOVATE_POST_UPDATE_OPTIONS: '["bundlerConservative"]'
        with:
          token: ${{ secrets.RENOVATE_TOKEN || github.token }}
          renovate-version: latest

      - name: Create Renovate report from lockfiles
        if: always()
        run: |
          # Prefer Renovate's own report (RENOVATE_REPORT_PATH=renovate-report.json).
          # It contains ALL deps from packageFiles — including up-to-date ones.
          # Fall back to awk parsing only when Renovate didn't produce a report.

          RENOVATE_REPORT_HAS_DATA=false
          if [ -f "renovate-report.json" ] && jq empty renovate-report.json 2>/dev/null; then
            REPO_COUNT=$(jq '.repositories | length // 0' renovate-report.json 2>/dev/null || echo 0)
            if [ "$REPO_COUNT" -gt "0" ]; then
              RENOVATE_REPORT_HAS_DATA=true
              echo "Using Renovate's own report (found $REPO_COUNT repositories)"
            fi
          fi

          if [ "$RENOVATE_REPORT_HAS_DATA" = "true" ]; then
            echo "Skipping lockfile fallback — Renovate report is complete."
          else
            echo "Renovate report missing or empty — building from Gemfile.lock..."
            REPO="${{ github.repository }}"
            REPORT_JSON='{"repositories":{"'"$REPO"'":{"repository":"'"$REPO"'","branches":[],"packageFiles":{}}}}'

            if [ -f "Gemfile.lock" ]; then
              # Extract top-level gems (4-space indent in GEM > specs section)
              GEMS=$(awk '/^GEM$/,/^PLATFORMS$/ {
                if ($0 ~ /^    [a-zA-Z0-9_-]+ \(/) {
                  match($0, /^    ([a-zA-Z0-9_-]+) \(([^)]+)\)/, m)
                  if (m[1] != "" && m[2] != "")
                    printf "{\"depName\": \"%s\", \"currentVersion\": \"%s\", \"updates\": []}\n", m[1], m[2]
                }
              }' Gemfile.lock)

              if [ -n "$GEMS" ]; then
                DEPS_ARRAY=$(echo "$GEMS" | jq -s '.' 2>/dev/null || echo '[]')
                REPORT_JSON=$(echo "$REPORT_JSON" | jq \
                  --argjson deps "$DEPS_ARRAY" \
                  --arg repo "$REPO" \
                  '.repositories[$repo].packageFiles.bundler = [{"fileName": "Gemfile", "deps": $deps}]')
                echo "Extracted $(echo "$DEPS_ARRAY" | jq 'length') gems from Gemfile.lock"
              fi
            fi

            echo "$REPORT_JSON" | jq '.' > renovate-report.json
            if ! jq empty renovate-report.json 2>/dev/null; then
              echo '{}' > renovate-report.json
            fi
          fi

          echo "Created renovate-report.json with detected dependencies"

      - name: Stop performance monitor
        if: always()
        run: |
          PERF_OUTPUT_FILE=performance-metrics.json
##EMBED:perf-stop.sh INDENT=10##

      - name: Build combined report
        if: always()
        run: |
          [ -f osv-report.json ]      || echo '{}' > osv-report.json
          [ -f trivy-report.json ]    || echo '{"Results":[]}' > trivy-report.json
          [ -f renovate-report.json ] || echo '{}' > renovate-report.json
          [ -f Package.resolved ]     || echo '{"pins":[]}' > Package.resolved
          [ -s performance-metrics.json ] || echo '[]' > performance-metrics.json
          [ -s osv-perf-metrics.json ]    || echo '[]' > osv-perf-metrics.json
          [ -s trivy-perf-metrics.json ]  || echo '[]' > trivy-perf-metrics.json

          jq -n --slurpfile osv osv-report.json \
                --slurpfile trivy trivy-report.json \
                --slurpfile renovate renovate-report.json \
                --slurpfile spm_resolved Package.resolved \
                --slurpfile perf performance-metrics.json \
                --slurpfile osv_perf osv-perf-metrics.json \
                --slurpfile trivy_perf trivy-perf-metrics.json \
                --arg timestamp "$(date -u -Iseconds)" \
                --arg pipeline_id "${{ github.run_id }}" \
                --arg commit_sha "${{ github.sha }}" \
                --arg branch "${{ inputs.target_base_branch }}" \
                --arg target_repo "${{ github.repository }}" \
                --arg platform "github" \
          '
##EMBED:combined-report.jq INDENT=10##
          ' > combined-report.json

      - name: Print summary
        if: always()
        run: |
          REPORT_HEADER="RENOVATE SUMMARY (${{ github.repository }})"
##EMBED:print-summary.sh INDENT=10##

      - name: POST report to dashboard
        if: always()
        run: |
          if [ ! -f combined-report.json ]; then
            echo "No combined report to send"
            exit 0
          fi

          WEBHOOK_URL="${{ secrets.DASHBOARD_WEBHOOK_URL }}"
          if [ -z "$WEBHOOK_URL" ]; then
            echo "WARNING: DASHBOARD_WEBHOOK_URL not set — skipping report upload"
            exit 0
          fi

          HTTP_STATUS=$(curl -s -o /tmp/webhook-response.txt -w "%{http_code}" \
            -X POST \
            -H "Content-Type: application/json" \
            -d @combined-report.json \
            "$WEBHOOK_URL")

          echo "Dashboard webhook response: HTTP $HTTP_STATUS"
          if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
            echo "Report successfully sent to dashboard"
          else
            echo "WARNING: Dashboard returned HTTP $HTTP_STATUS"
            cat /tmp/webhook-response.txt 2>/dev/null || true
          fi
