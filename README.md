# renovate-ci

Centralized templates for Renovate dependency updates + vulnerability scanning (OSV + Trivy).
Runs on the **self-hosted GitLab instance** and covers projects hosted on **GitLab** or **GitHub**.

---

## How It Works

Every scan run does, in order:

1. **OSV Scanner** — detects vulnerabilities in all lockfiles (npm, gem, gradle, pip, cargo, go, composer…)
2. **Trivy** — detects iOS/CocoaPods/SPM vulnerabilities (if `Podfile.lock`, `Package.resolved`, or `Cartfile.resolved` is present)
3. **Renovate** — opens PRs/MRs to update dependencies; vulnerable packages are automatically prioritized using OSV + Trivy results
4. **Combined report** — `combined-report.json` aggregates all results, consumed by the dashboard

---

## Architecture

| Platform | Execution model | What the target project needs |
|---|---|---|
| GitLab (same self-hosted instance) | **Distributed** — logic runs on the target project's own runner | 3 lines in `.gitlab-ci.yml` + a CI variable |
| GitHub (any repo) | **Distributed** — reusable workflow runs on the customer's own GitHub Actions runners | Workflow file + 2 secrets |

> **Automatic propagation**: no target project contains a copy of the logic.
> Any change committed to `renovate-ci` takes effect immediately on the next run.

---

## Adding a GitLab Project

### Prerequisites

- You have maintainer or owner access to the target GitLab project
- The project is on the same self-hosted GitLab instance as `renovate-ci`

### Step 1 — Add the include to `.gitlab-ci.yml`

In the **target project**, add these lines to `.gitlab-ci.yml` (create the file if it doesn't exist):

```yaml
include:
  - project: 'internal-projects/renovate-ci'
    ref: 'main'
    file: '/.gitlab/renovate-scan.yml'
```

> Replace `internal-projects/renovate-ci` with the actual path of this project on your GitLab instance.

### Step 2 — Add the `RENOVATE_TOKEN` CI variable

In the target project: **Settings → CI/CD → Variables → Add variable**

| Field | Value |
|---|---|
| Key | `RENOVATE_TOKEN` |
| Value | A GitLab Personal Access Token with scopes: `api`, `read_repository`, `write_repository` |
| Masked | ✅ Yes |
| Protected | ❌ No (so it works on all branches) |

This token is used by Renovate to read the project and open merge requests.
It must belong to a user (or service account) with Developer access to the target project.

### Step 3 — Register in the dashboard

Open the Renovate Dashboard and add a new project:

| Field | Value |
|---|---|
| Platform | `GitLab` |
| Repository URL | Full URL of the project (e.g. `https://git.company.com/group/myproject`) |
| Base branch | `main` (or your default branch) |

The dashboard will automatically:
- Resolve the GitLab project ID from the URL
- Create a pipeline trigger token and store it
- Set up webhooks for real-time job status

### Step 4 — Run a scan

Click **Run Renovate** in the dashboard. The first run uses **dry-run/lookup mode** by default (checks for updates without creating MRs). Switch to **full mode** when ready.

### (Optional) Customize Renovate configuration

Copy `default.json` from this repo to the root of the target project and rename it `renovate.json`.
If absent, the centralized config is used automatically.

---

## Adding a GitHub Project

GitHub projects run scans **on their own GitHub Actions runners**. No code ever leaves the customer's infrastructure — only the scan results (`combined-report.json`) are sent back to the dashboard via webhook.

### Prerequisites

- You have a GitHub Personal Access Token (PAT) with:
  - `repo` scope (for private repos: full read + write to open PRs)
  - `public_repo` scope (for public repos only)

### Step 1 — Register in the dashboard

Open the Renovate Dashboard and add a new project:

| Field | Value |
|---|---|
| Platform | `GitHub` |
| Repository | `owner/repo` format (e.g. `myorg/myapp`) |
| Base branch | `main` (or your default branch) |

The dashboard will display a **Webhook URL** (e.g. `https://renovate.company.com/api/reports/<token>`). Copy it.

### Step 2 — Add secrets to the GitHub repo

In the target GitHub repository: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `RENOVATE_TOKEN` | A GitHub PAT with `repo` scope (used by Renovate to open PRs) |
| `RENOVATE_DASHBOARD_WEBHOOK_URL` | The webhook URL from Step 1 |

### Step 3 — Add the workflow file

Create `.github/workflows/renovate.yml` in the target GitHub repository:

```yaml
name: Renovate
on:
  workflow_dispatch:
  schedule:
    - cron: '0 3 * * 1'

jobs:
  renovate:
    uses: <org>/renovate-ci/.github/workflows/renovate-scan.yml@main
    secrets:
      RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN }}
      DASHBOARD_WEBHOOK_URL: ${{ secrets.RENOVATE_DASHBOARD_WEBHOOK_URL }}
```

> Replace `<org>/renovate-ci` with the actual GitHub path of this repository.

### Step 4 — Run a scan

Either:
- Click **Run Renovate** in the dashboard (dispatches the workflow via GitHub API)
- Trigger manually in GitHub: **Actions → Renovate → Run workflow**
- Wait for the weekly schedule (`cron: '0 3 * * 1'`)

The workflow runs OSV + Trivy scans, executes Renovate, builds `combined-report.json`, and POSTs it to the dashboard webhook. The first run uses **dry-run/lookup mode** by default.

### (Optional) Customize Renovate configuration

Add a `renovate.json` to the root of the GitHub repo:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "timezone": "Europe/Paris"
}
```

If absent, the centralized `default.json` from `renovate-ci` is used automatically.

---

## Dry-Run Modes

| Mode | Behaviour | When to use |
|---|---|---|
| `lookup` | Checks what updates exist; no branches or PRs created | Default — safe first run |
| `full` | Simulates branch creation (no actual commits) | Validate config before going live |
| `false` | Full execution — creates real PRs/MRs | Production use |

---

## Supported Package Managers

| Manager | Ecosystem |
|---|---|
| `cocoapods` | iOS / CocoaPods |
| `swift` | iOS / Swift Package Manager |
| `gradle` + `gradle-wrapper` | Android |
| `npm` | Web / Node.js |
| `bundler` | Ruby / Rails |
| `pip_requirements` | Python |
| `gomod`, `cargo`, `composer`, `pub` | Go, Rust, PHP, Dart (auto-detected if lockfiles present) |

---

## Dashboard Variables Reference

### GitLab projects

| Variable | Description | Default |
|---|---|---|
| `RUN_RENOVATE` | Activation flag (`1`) | — |
| `TARGET_REPO` | GitLab path (`namespace/project`) | `$CI_PROJECT_PATH` |
| `TARGET_BASE_BRANCH` | Main branch | `$CI_DEFAULT_BRANCH` |
| `DRY_RUN_MODE` | `lookup` / `full` / `false` | `lookup` |
| `RENOVATE_TOKEN` | GitLab PAT (set in the target project's CI variables) | — |

### GitHub projects (workflow inputs)

| Input | Description | Default |
|---|---|---|
| `target_base_branch` | Base branch to scan | `main` |
| `dry_run_mode` | `lookup` / `full` / `false` | `lookup` |

| Secret | Description |
|---|---|
| `RENOVATE_TOKEN` | GitHub PAT with `repo` scope |
| `DASHBOARD_WEBHOOK_URL` | Webhook URL provided by the dashboard |

---

## Environment Variables Required on the Dashboard Server

| Variable | Purpose |
|---|---|
| `GITLAB_API_BASE` | GitLab API endpoint (e.g. `https://git.company.com/api/v4`) |
| `GITLAB_PRIVATE_TOKEN` | Admin GitLab PAT with `api` scope — used to download artifacts and trigger pipelines |
| `RENOVATE_CI_PROJECT_ID` | GitLab project ID of this `renovate-ci` repo |
| `RENOVATE_CI_TRIGGER_TOKEN` | Pipeline trigger token for `renovate-ci` (used to trigger GitHub scans) |
| `WEBHOOK_BASE_URL` | Public URL where the dashboard receives webhooks |
