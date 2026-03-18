if [ -f build.gradle ] || [ -f build.gradle.kts ] || find . -maxdepth 3 -path "*/gradle/libs.versions.toml" 2>/dev/null | grep -q .; then
  if ! find . -name "gradle.lockfile" -maxdepth 3 2>/dev/null | grep -q .; then
    echo "Gradle project detected without lockfiles — parsing build files for OSV scan..."
    ALL_DEPS=$(mktemp)

    # ---- Strategy 1: Parse version catalog (libs.versions.toml) --------
    TOML_FILE=$(find . -maxdepth 3 -path "*/gradle/libs.versions.toml" 2>/dev/null | head -1)
    if [ -n "$TOML_FILE" ]; then
      echo "Found version catalog: $TOML_FILE"
      # Single awk pass: parse [versions] and [libraries], resolve and emit group:artifact:version
      # Compatible with mawk (no gawk capture groups) for ubuntu:noble
      awk '
        function extract(s, key,    pat, idx, rest, val) {
          # Extract value for key = "..." from an inline table string
          idx = index(s, key)
          if (idx == 0) return ""
          rest = substr(s, idx + length(key))
          gsub(/^[[:space:]]*=[[:space:]]*"/, "", rest)
          idx = index(rest, "\"")
          if (idx == 0) return ""
          return substr(rest, 1, idx - 1)
        }
        function unquote(s) {
          gsub(/^[[:space:]]*"/, "", s); gsub(/"[[:space:]]*$/, "", s)
          return s
        }

        /^\[versions\]/      { section="versions"; next }
        /^\[libraries\]/     { section="libraries"; next }
        /^\[/                { section=""; next }
        /^#/ || /^[[:space:]]*$/ { next }

        section=="versions" {
          split($0, kv, "=")
          key = kv[1]; gsub(/[[:space:]]/, "", key)
          val = ""; for (i=2; i<=length(kv); i++) { val = val (i>2?"=":"") kv[i] }
          gsub(/^[[:space:]]*/, "", val); gsub(/[[:space:]]*$/, "", val)
          if (val ~ /^\{/) {
            # { strictly = "x" } or { prefer = "x" } — grab first quoted value
            match(val, /"[^"]*"/)
            val = substr(val, RSTART+1, RLENGTH-2)
          } else {
            val = unquote(val)
          }
          versions[key] = val
          next
        }

        section=="libraries" {
          split($0, kv, "=")
          key = kv[1]; gsub(/[[:space:]]/, "", key)
          val = ""; for (i=2; i<=length(kv); i++) { val = val (i>2?"=":"") kv[i] }
          gsub(/^[[:space:]]*/, "", val); gsub(/[[:space:]]*$/, "", val)

          group=""; artifact=""; version=""

          if (val ~ /^"[^"]*"$/) {
            # Short notation: "group:artifact:version"
            tmp = unquote(val)
            split(tmp, parts, ":")
            if (length(parts) >= 3) { group=parts[1]; artifact=parts[2]; version=parts[3] }
          } else {
            # Inline table with module or group+name
            mod = extract(val, "module")
            if (mod != "") {
              split(mod, mp, ":")
              group = mp[1]; artifact = mp[2]
            } else {
              group = extract(val, "group")
              artifact = extract(val, "name")
            }
            vref = extract(val, "version.ref")
            if (vref != "") {
              version = versions[vref]
            } else {
              version = extract(val, "version")
            }
          }

          if (group != "" && artifact != "" && version != "") {
            print group ":" artifact ":" version
          }
        }
      ' "$TOML_FILE" >> "$ALL_DEPS"
      echo "Extracted $(wc -l < "$ALL_DEPS" | tr -d ' ') dependencies from version catalog"
    fi

    # ---- Strategy 2: Parse build.gradle for inline coordinates ---------
    VARS_FILE=$(mktemp)
    for bf in $(find . -maxdepth 3 \( -name "build.gradle" -o -name "build.gradle.kts" \) 2>/dev/null); do
      sed -n "s/.*ext\.\([a-zA-Z_][a-zA-Z0-9_]*\)\s*=\s*[\"']\([^\"']*\)[\"'].*/\1=\2/p" "$bf" >> "$VARS_FILE"
      sed -n "s/.*\bdef\s\+\([a-zA-Z_][a-zA-Z0-9_]*\)\s*=\s*[\"']\([^\"']*\)[\"'].*/\1=\2/p" "$bf" >> "$VARS_FILE"
      sed -n "s/.*\bval\s\+\([a-zA-Z_][a-zA-Z0-9_]*\)\s*=\s*[\"']\([^\"']*\)[\"'].*/\1=\2/p" "$bf" >> "$VARS_FILE"
    done

    for bf in $(find . -maxdepth 3 \( -name "build.gradle" -o -name "build.gradle.kts" \) 2>/dev/null); do
      DEPS_FILE=$(mktemp)

      grep -E "^\s*(implementation|api|kapt|ksp|compileOnly|runtimeOnly|annotationProcessor|testImplementation|androidTestImplementation|classpath)" "$bf" \
        | grep -oE "\"[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+:[^\"]*\"|'[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+:[^']*'" \
        | sed "s/^[\"']//;s/[\"']$//" > "$DEPS_FILE" || true

      while IFS='=' read -r vname vvalue; do
        [ -z "$vname" ] && continue
        sed -i "s/\\\$$vname/$vvalue/g;s/\${$vname}/$vvalue/g" "$DEPS_FILE" 2>/dev/null || true
      done < "$VARS_FILE"

      grep -E '^[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+:[a-zA-Z0-9._+-]+$' "$DEPS_FILE" >> "$ALL_DEPS" || true
      rm -f "$DEPS_FILE"
    done
    rm -f "$VARS_FILE"

    # ---- Write synthetic lockfile at project root ----------------------
    RESOLVED=$(sort -u "$ALL_DEPS")
    if [ -n "$RESOLVED" ]; then
      {
        echo "# Lockfile generated by CI for OSV vulnerability scanning"
        echo "$RESOLVED" | while read -r dep; do echo "${dep}=compileClasspath,runtimeClasspath"; done
        echo "empty="
      } > gradle.lockfile
      echo "Generated gradle.lockfile ($(echo "$RESOLVED" | wc -l | tr -d ' ') dependencies)"
    else
      echo "WARNING: No Gradle dependencies could be extracted"
    fi
    rm -f "$ALL_DEPS"
  fi
fi
