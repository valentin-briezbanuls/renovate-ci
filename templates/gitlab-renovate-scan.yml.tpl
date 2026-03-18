# =============================================================================
# GENERATED FILE — do not edit directly.
# Source: templates/gitlab-renovate-scan.yml.tpl + scripts/shared/
# Regenerate: bash scripts/generate.sh
# =============================================================================
# Universal Renovate + OSV/Trivy scan template
# =============================================================================
# Include this file in any project's .gitlab-ci.yml:
#
#   include:
#     - project: 'internal-projects/renovate-dashboard'
#       file: 'ci-templates/renovate-scan.yml'
#
# Requirements:
#   - CI/CD variable RENOVATE_TOKEN (masked): GitLab PAT with api, read_user,
#     read_repository scopes
#   - A renovate.json (or .renovaterc / .renovaterc.json) in the repo root
#
# Triggered by the dashboard (RUN_RENOVATE=1) or manually / on schedule.
# =============================================================================

stages:
  - security
  - renovate

# -- Lockfile lists (used in rules:exists to skip irrelevant scanners - so no trivy if project not iOS and vice-versa) ------
.osv_lockfiles: &osv_lockfiles
  - Gemfile.lock
  - package-lock.json
  - yarn.lock
  - pnpm-lock.yaml
  - build.gradle
  - build.gradle.kts
  - gradle/libs.versions.toml
  - go.sum
  - Cargo.lock
  - composer.lock
  - requirements.txt
  - poetry.lock
  - pubspec.lock

.ios_lockfiles: &ios_lockfiles
  - Podfile.lock
  - Package.resolved
  - Cartfile.resolved

# -- Reusable performance monitoring scripts --------------------------------
.perf_start: &perf_start |
##EMBED:perf-start.sh INDENT=2##

# Stops the monitor and writes JSON array to $1 (default: perf-metrics.json)
.perf_stop: &perf_stop |
##EMBED:perf-stop.sh INDENT=2##

# ---------------------------------------------------------------------------
# OSV vulnerability scan — works for any ecosystem (npm, pip, gem, cargo, go,
# gradle, maven, composer, etc.) via recursive auto-detection.
# ---------------------------------------------------------------------------
osv_vulnerability_scan:
  image: ubuntu:noble
  stage: security
  tags: [mac]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "trigger" && $RUN_RENOVATE == "1"'
      exists: *osv_lockfiles
      when: on_success
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
      exists: *osv_lockfiles
      when: on_success
    - if: '$CI_PIPELINE_SOURCE == "web"'
      exists: *osv_lockfiles
      when: on_success
    - when: never
  before_script:
    - apt-get update -qq
    - apt-get install -y wget jq procps
    - wget -q https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 -O /usr/local/bin/osv-scanner
    - chmod +x /usr/local/bin/osv-scanner
  script:
    - *perf_start
    # --- Generate Gradle lockfiles if needed ---------------------------------
    # Instead of running Gradle (which needs JDK + Android SDK), we parse
    # build.gradle files AND gradle/libs.versions.toml (version catalogs)
    # to produce synthetic lockfiles that OSV scanner can read.
    - |
##EMBED:gradle-lockfile.sh INDENT=6##

    # --- Run OSV scan --------------------------------------------------------
    - |
##EMBED:osv-scan.sh INDENT=6##
    - PERF_OUTPUT_FILE=osv-perf-metrics.json
    - *perf_stop
  artifacts:
    paths:
      - osv-report.json
      - osv-perf-metrics.json
    when: always
    expire_in: 1 week

# ---------------------------------------------------------------------------
# Trivy vulnerability scan — complements OSV for ecosystems where lockfile
# support is limited (notably iOS/CocoaPods).
# ---------------------------------------------------------------------------
trivy_vulnerability_scan:
  image: ubuntu:noble
  stage: security
  tags: [mac]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "trigger" && $RUN_RENOVATE == "1"'
      exists: *ios_lockfiles
      when: on_success
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
      exists: *ios_lockfiles
      when: on_success
    - if: '$CI_PIPELINE_SOURCE == "web"'
      exists: *ios_lockfiles
      when: on_success
    - when: never
  before_script:
    - apt-get update -qq && apt-get install -y curl jq procps
  script:
    - *perf_start
    # --- Install and run Trivy
    - |
      if [ ! -f Podfile.lock ] && [ ! -f Package.resolved ] && [ ! -f Cartfile.resolved ]; then
        echo "No iOS lockfile detected (Podfile.lock / Package.resolved / Cartfile.resolved); skipping Trivy scan."
        echo '{"Results":[]}' > trivy-report.json
        exit 0
      fi

##EMBED:trivy-scan.sh INDENT=6##
    - PERF_OUTPUT_FILE=trivy-perf-metrics.json
    - *perf_stop
  artifacts:
    paths:
      - trivy-report.json
      - trivy-perf-metrics.json
    when: always
    expire_in: 1 week


# ---------------------------------------------------------------------------
# Renovate dry-run + combined report generation
# ---------------------------------------------------------------------------
renovate_run:
  image: renovate/renovate:latest
  stage: renovate
  tags: [mac]
  timeout: 60m
  needs:
    - job: osv_vulnerability_scan
      artifacts: true
      optional: true
    - job: trivy_vulnerability_scan
      artifacts: true
      optional: true
  rules:
    - if: '$CI_PIPELINE_SOURCE == "trigger" && $RUN_RENOVATE == "1"'
      when: on_success
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
      when: on_success
    - if: '$CI_PIPELINE_SOURCE == "web"'
      when: manual
    - when: never
  variables:
    RENOVATE_PLATFORM: gitlab
    RENOVATE_ENDPOINT: "$CI_SERVER_URL/api/v4/"
    RENOVATE_BASE_BRANCHES: "${TARGET_BASE_BRANCH:-$CI_DEFAULT_BRANCH}"
    RENOVATE_GIT_AUTHOR: "Renovate Bot <renovate@isee-u.fr>"
    RENOVATE_REPOSITORY_CACHE: "enabled"
    RENOVATE_CACHE_DIR: "${CI_PROJECT_DIR}/.renovate-cache"
    GITHUB_COM_TOKEN: "$GITHUB_COM_TOKEN"
    LOG_LEVEL: debug
  cache:
    key: "renovate-cache-${CI_PROJECT_PATH_SLUG}"
    paths:
      - .renovate-cache/
  before_script:
    - |
      if [ -z "$RENOVATE_TOKEN" ]; then
        echo "ERROR: RENOVATE_TOKEN is not set."
        echo "Renovate requires a GitLab PAT with api, read_user, read_repository scopes."
        echo ""
        echo "Either:"
        echo "  1. Add RENOVATE_TOKEN as a CI/CD variable on this project or parent group"
        echo "     (Settings > CI/CD > Variables, masked=yes, protected=no)"
        echo "  2. Pass it as a trigger variable from the Renovate Dashboard"
        exit 1
      fi
    - |
      if ! command -v jq >/dev/null; then
        if command -v apk >/dev/null; then
          apk add --no-cache jq
        elif command -v apt-get >/dev/null; then
          apt-get update -qq && apt-get install -y jq
        fi
      fi
  script:
    - *perf_start
    # --- Resolve target repo -------------------------------------------------
    - |
      REPO="${TARGET_REPO:-$CI_PROJECT_PATH}"
      echo "Target repository: $REPO"

    # --- Prioritise vulnerable packages --------------------------------------
    - |
##EMBED:prioritize-packages.sh INDENT=6##
    - |
      # Import env vars from shared script (GitLab: source directly)
      if [ -f /tmp/ci-env-exports.sh ]; then
        . /tmp/ci-env-exports.sh
        if [ -n "${RENOVATE_PACKAGE_RULES:-}" ]; then
          export RENOVATE_PACKAGE_RULES
        fi
      fi

    # --- Run Renovate --------------------------------------------------------
    - |
      # Dry-run mode: "lookup" only checks for updates (fast, no lockfile resolution),
      # "full" simulates branches+commits (slow), "false" applies changes for real.
      # Default to lookup (safe); respect DRY_RUN_MODE override from CI variables.
      # IMPORTANT: We use DRY_RUN_MODE (not RENOVATE_DRY_RUN) as input to avoid
      # conflicts with Renovate's own RENOVATE_DRY_RUN env var.
      DRY_RUN_INPUT="${DRY_RUN_MODE:-${RENOVATE_DRY_RUN:-}}"
      echo "DRY_RUN_INPUT='${DRY_RUN_INPUT}' (pipeline_source=$CI_PIPELINE_SOURCE)"
      if [ "${DRY_RUN_INPUT}" = "full" ]; then
        DRY_RUN_FLAG="full"
      elif [ "${DRY_RUN_INPUT}" = "false" ]; then
        DRY_RUN_FLAG=""
      else
        DRY_RUN_FLAG="lookup"
      fi
      # Unset env var so Renovate only uses the CLI flag
      unset RENOVATE_DRY_RUN
      if [ -n "$DRY_RUN_FLAG" ]; then
        DRY_RUN="--dry-run=$DRY_RUN_FLAG"
      else
        DRY_RUN=""
      fi
      echo "Renovate mode: ${DRY_RUN:-REAL (no dry-run)}"

      # Auto-detect renovate config in .gitlab/ if not at repo root
      if [ ! -f renovate.json ] && [ ! -f .renovaterc ] && [ ! -f .renovaterc.json ]; then
        for cfg in .gitlab/renovate.json .gitlab/.renovaterc .gitlab/.renovaterc.json; do
          if [ -f "$cfg" ]; then
            export RENOVATE_CONFIG_FILE="$cfg"
            echo "Using Renovate config from $cfg"
            break
          fi
        done
      fi

      # If no repo-level Renovate config exists, fallback to centralized config
      if [ -z "${RENOVATE_CONFIG_FILE:-}" ] && [ -z "${RENOVATE_CONFIG:-}" ]; then
##EMBED:detect-managers.sh INDENT=8##
        # Import detected managers
        if [ -f /tmp/ci-env-exports.sh ]; then
          . /tmp/ci-env-exports.sh
        fi

        export RENOVATE_CONFIG="{\"\$schema\":\"https://docs.renovatebot.com/renovate-schema.json\",\"extends\":[\"config:recommended\"],\"enabled\":true,\"timezone\":\"Europe/Paris\",\"automerge\":false,\"prHourlyLimit\":10,\"prConcurrentLimit\":5,\"ignorePaths\":[\".build/**\",\"**/node_modules/**\",\"**/Pods/**\"],\"osvVulnerabilityAlerts\":true,\"vulnerabilityAlerts\":{\"enabled\":true,\"labels\":[\"security\",\"vulnerability\",\"high-priority\"],\"prBodyNotes\":[\"**Severity:** {{{vulnerabilitySeverity}}}\",\"**CVEs:** {{{cveUrls}}}\"]}${MANAGERS:+,\"enabledManagers\":[$MANAGERS]},\"packageRules\":[$PACKAGE_RULES]${CONSTRAINTS_JSON},\"commitMessagePrefix\":\"chore:\",\"commitMessageAction\":\"update\",\"commitMessageTopic\":\"{{depName}}\",\"commitMessageExtra\":\"to {{newVersion}}{{#if isVulnerabilityAlert}} (security){{/if}}\"}"
        echo "Using centralized inline Renovate config from CI template"
      fi

      renovate "$REPO" --onboarding=false --require-config=optional --report-type=file --report-path=renovate-report.json $DRY_RUN

    # --- Stop performance monitor and build metrics file --------------------
    - PERF_OUTPUT_FILE=performance-metrics.json
    - *perf_stop

    # --- Build combined report -----------------------------------------------
    - |
      # Ensure report files exist (--slurpfile requires them)
      [ -f osv-report.json ]      || echo '{}' > osv-report.json
      [ -f trivy-report.json ]    || echo '{"Results":[]}' > trivy-report.json
      [ -f renovate-report.json ] || echo '{}' > renovate-report.json
      [ -f Package.resolved ]     || echo '{"pins":[]}' > Package.resolved
      [ -s performance-metrics.json ] || echo '[]' > performance-metrics.json
      [ -s osv-perf-metrics.json ]  || echo '[]' > osv-perf-metrics.json
      [ -s trivy-perf-metrics.json ] || echo '[]' > trivy-perf-metrics.json

              jq -n --slurpfile osv osv-report.json \
                    --slurpfile trivy trivy-report.json \
                    --slurpfile renovate renovate-report.json \
                    --slurpfile spm_resolved Package.resolved \
                    --slurpfile perf performance-metrics.json \
                    --slurpfile osv_perf osv-perf-metrics.json \
                    --slurpfile trivy_perf trivy-perf-metrics.json \
                    --arg timestamp "$(date -u -Iseconds)" \
                    --arg pipeline_id "$CI_PIPELINE_ID" \
                    --arg commit_sha "$CI_COMMIT_SHA" \
                    --arg branch "$CI_COMMIT_REF_NAME" \
                    --arg platform "gitlab" \
                    --arg target_repo "${TARGET_REPO:-$CI_PROJECT_PATH}" \
              '
##EMBED:combined-report.jq INDENT=6##
      ' > combined-report.json

    # --- Print summary -------------------------------------------------------
    - |
      REPORT_HEADER="RENOVATE SUMMARY"
##EMBED:print-summary.sh INDENT=6##

  artifacts:
    paths:
      - combined-report.json
      - osv-report.json
      - trivy-report.json
      - renovate-report.json
      - performance-metrics.json
    when: always
    expire_in: 1 hour
