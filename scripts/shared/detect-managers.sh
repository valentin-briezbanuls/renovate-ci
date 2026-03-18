# Auto-detect relevant package managers based on files present
MANAGERS=""
PACKAGE_RULES=""
if [ -f Podfile ] || [ -f Podfile.lock ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"cocoapods\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group iOS CocoaPods updates\",\"matchManagers\":[\"cocoapods\"],\"groupName\":\"iOS CocoaPods dependencies\",\"labels\":[\"dependencies\",\"automated\",\"ios\",\"cocoapods\"]}"
fi
if [ -f Package.swift ] || [ -f Package.resolved ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"swift\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group iOS SPM updates\",\"matchManagers\":[\"swift\"],\"groupName\":\"iOS Swift Package Manager dependencies\",\"labels\":[\"dependencies\",\"automated\",\"ios\",\"spm\"]}"
fi
if [ -f build.gradle ] || [ -f build.gradle.kts ] || find . -maxdepth 2 -name "build.gradle*" 2>/dev/null | grep -q .; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"gradle\",\"gradle-wrapper\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group Android Gradle updates\",\"matchManagers\":[\"gradle\",\"gradle-wrapper\"],\"groupName\":\"Android Gradle dependencies\",\"labels\":[\"dependencies\",\"automated\",\"android\",\"gradle\"]}"
fi
if [ -f package.json ] || [ -f package-lock.json ] || [ -f yarn.lock ] || [ -f pnpm-lock.yaml ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"npm\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group npm updates\",\"matchManagers\":[\"npm\"],\"groupName\":\"Web npm dependencies\",\"labels\":[\"dependencies\",\"automated\",\"web\",\"npm\"]}"
fi
if [ -f Gemfile ] || [ -f Gemfile.lock ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"bundler\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group Ruby/Rails updates\",\"matchManagers\":[\"bundler\"],\"groupName\":\"Web Ruby dependencies\",\"labels\":[\"dependencies\",\"automated\",\"web\",\"ruby\",\"bundler\"]}"
fi
if [ -f requirements.txt ] || [ -f poetry.lock ] || [ -f Pipfile ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"pip_requirements\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group Python pip updates\",\"matchManagers\":[\"pip_requirements\"],\"groupName\":\"Python pip dependencies\",\"labels\":[\"dependencies\",\"automated\",\"python\",\"pip\"]}"
fi
if [ -f pubspec.yaml ] || [ -f pubspec.lock ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"pub\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group Flutter/Dart updates\",\"matchManagers\":[\"pub\"],\"groupName\":\"Flutter Dart dependencies\",\"labels\":[\"dependencies\",\"automated\",\"dart\",\"pub\"]}"
fi
if [ -f go.mod ] || [ -f go.sum ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"gomod\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group Go module updates\",\"matchManagers\":[\"gomod\"],\"groupName\":\"Go module dependencies\",\"labels\":[\"dependencies\",\"automated\",\"go\"]}"
fi
if [ -f Cargo.toml ] || [ -f Cargo.lock ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"cargo\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group Rust Cargo updates\",\"matchManagers\":[\"cargo\"],\"groupName\":\"Rust Cargo dependencies\",\"labels\":[\"dependencies\",\"automated\",\"rust\",\"cargo\"]}"
fi
if [ -f composer.json ] || [ -f composer.lock ]; then
  MANAGERS="${MANAGERS:+$MANAGERS,}\"composer\""
  PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}{\"description\":\"Group PHP Composer updates\",\"matchManagers\":[\"composer\"],\"groupName\":\"PHP Composer dependencies\",\"labels\":[\"dependencies\",\"automated\",\"php\",\"composer\"]}"
fi

echo "Detected managers: $MANAGERS"

# Auto-detect runtime constraints so Renovate resolves compatible versions
CONSTRAINTS=""
RUBY_VERSION=""
if [ -f .ruby-version ]; then
  RUBY_VERSION=$(head -1 .ruby-version | tr -d '[:space:]')
elif [ -f .tool-versions ]; then
  RUBY_VERSION=$(awk '/^ruby / {print $2}' .tool-versions | tr -d '[:space:]')
elif [ -f Gemfile ]; then
  RUBY_VERSION=$(sed -n "s/^ruby [\"']\([^\"']*\)[\"'].*/\1/p" Gemfile | head -1 | tr -d '[:space:]')
fi
if [ -n "$RUBY_VERSION" ]; then
  CONSTRAINTS="\"ruby\":\"$RUBY_VERSION\""
  echo "Detected Ruby version constraint: $RUBY_VERSION"
fi

NODE_VERSION=""
if [ -f .node-version ]; then
  NODE_VERSION=$(head -1 .node-version | tr -d '[:space:]')
elif [ -f .nvmrc ]; then
  NODE_VERSION=$(head -1 .nvmrc | tr -d '[:space:]')
elif [ -f .tool-versions ]; then
  NODE_VERSION=$(awk '/^nodejs / {print $2}' .tool-versions | tr -d '[:space:]')
fi
if [ -n "$NODE_VERSION" ]; then
  CONSTRAINTS="${CONSTRAINTS:+$CONSTRAINTS,}\"node\":\"$NODE_VERSION\""
  echo "Detected Node version constraint: $NODE_VERSION"
fi

CONSTRAINTS_JSON=""
if [ -n "$CONSTRAINTS" ]; then
  CONSTRAINTS_JSON=",\"constraints\":{$CONSTRAINTS}"
fi

# Common package rules (appended to ecosystem-specific ones)
COMMON_RULES='{"matchCategories":["ruby"],"isVulnerabilityAlert":true,"groupName":"Ruby security updates","groupSlug":"rubygems-security","labels":["security","high-priority","ruby"]},{"matchCategories":["js"],"isVulnerabilityAlert":true,"groupName":"npm security updates","groupSlug":"npm-security","labels":["security","high-priority","npm"]},{"matchPackagePatterns":["*"],"isVulnerabilityAlert":true,"groupName":"Security updates","groupSlug":"security","labels":["security","high-priority"]},{"matchUpdateTypes":["patch"],"automerge":false,"labels":["patch-update"]},{"matchDepTypes":["devDependencies"],"labels":["dev-dependencies"],"automerge":false}'
PACKAGE_RULES="${PACKAGE_RULES:+$PACKAGE_RULES,}$COMMON_RULES"

# Write results to /tmp/ci-env-exports.sh for platform-specific consumption
# Export as bash arrays and pre-computed JSON to avoid quoting issues
{
  echo "MANAGERS='$MANAGERS'"
  echo "PACKAGE_RULES='$PACKAGE_RULES'"
  echo "CONSTRAINTS_JSON='$CONSTRAINTS_JSON'"
} > /tmp/ci-env-exports.sh
