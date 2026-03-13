# renovate-ci

Templates centralisés pour Renovate + scan de vulnérabilités (OSV + Trivy).  
Ce projet s'exécute sur le **GitLab self-hosted** et couvre les projets hébergés sur **GitLab** ou **GitHub**.

---

## Architecture

```
renovate-ci/ (GitLab self-hosted — privé)
├── .gitlab/renovate-scan.yml         ← inclus par les projets GitLab (même instance)
├── .gitlab/renovate-scan-github.yml  ← déclenché par le dashboard pour les projets GitHub
└── default.json                      ← config Renovate de référence
```

| Plateforme | Modèle d'exécution | Ce que fait le projet cible |
|------------|--------------------|-----------------------------|
| GitLab (même instance) | **Include** — la logique s'exécute dans le runner du projet cible | Ajouter 3 lignes dans `.gitlab-ci.yml` |
| GitHub (tout projet) | **Centralisé** — la logique s'exécute depuis `renovate-ci` sur GitLab | S'enregistrer dans le dashboard |

> **Propagation automatique** : aucun projet cible ne contient de copie de la logique.  
> Toute modification dans `renovate-ci` s'applique immédiatement au prochain run.

---

## Ce que font les scans

Chaque run effectue, dans l'ordre :

1. **OSV Scanner** — détecte les vulnérabilités dans tous les lockfiles (npm, gem, gradle, pip, cargo, go, composer…)
2. **Trivy** — détecte les vulnérabilités iOS/CocoaPods/SPM (si `Podfile.lock`, `Package.resolved` ou `Cartfile.resolved` est présent)
3. **Renovate** — ouvre des PRs/MRs pour mettre à jour les dépendances ; les packages vulnérables sont priorisés automatiquement via les résultats OSV + Trivy
4. **Rapport combiné** — `combined-report.json` agrège tous les résultats (consommé par le dashboard)

---

## Onboarding — Projet GitLab (même instance self-hosted)

### 1. Ajouter l'include dans `.gitlab-ci.yml`

```yaml
include:
  - project: 'internal-projects/renovate-ci'
    ref: 'main'
    file: '/.gitlab/renovate-scan.yml'
```

### 2. Ajouter la variable CI/CD `RENOVATE_TOKEN`

**Settings → CI/CD → Variables → Add variable**

| Champ | Valeur |
|-------|--------|
| Key | `RENOVATE_TOKEN` |
| Value | PAT GitLab avec scopes `api`, `read_repository`, `write_repository` |
| Masked | ✅ Oui |
| Protected | ❌ Non (pour fonctionner sur toutes les branches) |

### 3. (Optionnel) Personnaliser la config Renovate

Copier `default.json` à la racine du projet et le renommer `renovate.json`.  
Si absent, la config centralisée est utilisée automatiquement.

### Déclencheurs disponibles

| Source | Comportement |
|--------|-------------|
| Trigger pipeline (dashboard) avec `RUN_RENOVATE=1` | Run automatique complet |
| Schedule GitLab | Run automatique complet |
| Pipeline manuel (web) | Run manuel — demande confirmation |

---

## Onboarding — Projet GitHub

### 1. S'enregistrer dans le dashboard

Ouvrir le dashboard et ajouter le projet avec :

| Champ | Valeur |
|-------|--------|
| Platform | `github` |
| Repository | `owner/repo` |
| Base branch | ex: `main` |

Le dashboard utilise le token GitHub déjà configuré pour le groupe/utilisateur.

### 2. (Optionnel) Personnaliser la config Renovate

Ajouter un `renovate.json` à la racine du projet GitHub.  
Si absent, la config centralisée de `renovate-ci` est utilisée automatiquement.

Exemple minimaliste :

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "timezone": "Europe/Paris"
}
```

### Aucun fichier CI à ajouter

Les projets GitHub n'ont **pas besoin** d'un workflow `.github/workflows/`.  
Toute la logique s'exécute depuis les runners GitLab de `renovate-ci`.

---

## Variables de déclenchement (dashboard → pipeline)

### Projets GitLab

| Variable | Description | Défaut |
|----------|-------------|--------|
| `RUN_RENOVATE` | Flag d'activation (`1`) | — |
| `TARGET_REPO` | Chemin GitLab (`namespace/project`) | `$CI_PROJECT_PATH` |
| `TARGET_BASE_BRANCH` | Branche principale | `$CI_DEFAULT_BRANCH` |
| `DRY_RUN_MODE` | `lookup` / `full` / `false` | `lookup` |
| `RENOVATE_TOKEN` | PAT GitLab (variable CI/CD du projet) | — |

### Projets GitHub

| Variable | Description | Défaut |
|----------|-------------|--------|
| `RUN_GITHUB` | Flag d'activation (`1`) | — |
| `TARGET_REPO` | Dépôt GitHub (`owner/repo`) | — |
| `TARGET_BASE_BRANCH` | Branche principale | `main` |
| `DRY_RUN_MODE` | `lookup` / `full` / `false` | `lookup` |
| `GITHUB_TOKEN` | PAT GitHub (masqué, géré par le dashboard) | — |

---

## Config Renovate de référence (`default.json`)

Écosystèmes couverts par défaut :

| Manager | Écosystème |
|---------|-----------|
| `cocoapods` | iOS / CocoaPods |
| `swift` | iOS / Swift Package Manager |
| `gradle` + `gradle-wrapper` | Android / Gradle |
| `npm` | Web / Node.js |
| `bundler` | Ruby / Rails |
| `pip_requirements` | Python / pip |

Pour ajouter d'autres managers (`gomod`, `cargo`, `composer`, `pub`…), les définir dans le `renovate.json` du projet cible.

---

## Structure des fichiers

```
renovate-ci/
├── .gitlab-ci.yml                        ← pipeline de renovate-ci (inclut les deux templates)
├── default.json                          ← config Renovate de référence (unique source de vérité)
├── .gitlab/
│   ├── renovate-scan.yml                 ← template inclus par les projets GitLab
│   ├── renovate-scan-github.yml          ← template déclenché par le dashboard pour GitHub
│   └── renovate.json                     ← DEPRECATED — doublon de default.json
├── .github/
│   └── workflows/
│       └── renovate-scan.yml             ← DEPRECATED — remplacé par renovate-scan-github.yml
└── PLAN.md                               ← plan d'architecture
```

