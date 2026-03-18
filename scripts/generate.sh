#!/bin/sh
# generate.sh — Assembles final CI files from templates + shared scripts.
# Usage:
#   bash scripts/generate.sh          # generate .gitlab/ and .github/ CI files
#   bash scripts/generate.sh --check  # verify generated files match committed ones
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts/shared"
TEMPLATES_DIR="$REPO_ROOT/templates"

process_template() {
  local tpl="$1"
  local out="$2"
  local tmpfile
  tmpfile=$(mktemp)

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"##EMBED:"*"##"*)
        # Extract filename and indent from ##EMBED:filename INDENT=N##
        marker=$(echo "$line" | sed 's/.*##EMBED:\([^ ]*\) INDENT=\([0-9]*\)##.*/\1 \2/')
        filename=$(echo "$marker" | cut -d' ' -f1)
        indent=$(echo "$marker" | cut -d' ' -f2)
        padding=$(printf "%${indent}s" "")
        script_file="$SCRIPTS_DIR/$filename"
        if [ ! -f "$script_file" ]; then
          echo "ERROR: Missing script: $script_file" >&2
          exit 1
        fi
        # Emit each line of the script with the specified indentation
        first=true
        while IFS= read -r sline || [ -n "$sline" ]; do
          if $first; then
            echo "${padding}${sline}"
            first=false
          else
            echo "${padding}${sline}"
          fi
        done < "$script_file"
        ;;
      *)
        echo "$line"
        ;;
    esac
  done < "$tpl" > "$tmpfile"

  if [ "${CHECK_MODE:-}" = "1" ]; then
    if ! diff -q "$tmpfile" "$out" >/dev/null 2>&1; then
      echo "MISMATCH: $out is out of date. Run 'bash scripts/generate.sh' to regenerate." >&2
      diff -u "$out" "$tmpfile" >&2 || true
      rm -f "$tmpfile"
      return 1
    fi
    rm -f "$tmpfile"
  else
    mv "$tmpfile" "$out"
    echo "Generated: $out"
  fi
}

if [ "${1:-}" = "--check" ]; then
  CHECK_MODE=1
  export CHECK_MODE
  FAILED=0
  process_template "$TEMPLATES_DIR/gitlab-renovate-scan.yml.tpl" "$REPO_ROOT/.gitlab/renovate-scan.yml" || FAILED=1
  process_template "$TEMPLATES_DIR/github-renovate-scan.yml.tpl" "$REPO_ROOT/.github/workflows/renovate-scan.yml" || FAILED=1
  if [ "$FAILED" -eq 1 ]; then
    echo "Generated files are out of date. Run 'bash scripts/generate.sh' to fix." >&2
    exit 1
  fi
  echo "All generated files are up to date."
  exit 0
fi

process_template "$TEMPLATES_DIR/gitlab-renovate-scan.yml.tpl" "$REPO_ROOT/.gitlab/renovate-scan.yml"
process_template "$TEMPLATES_DIR/github-renovate-scan.yml.tpl" "$REPO_ROOT/.github/workflows/renovate-scan.yml"
echo "Done."
