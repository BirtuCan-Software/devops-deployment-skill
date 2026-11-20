# DevOps Deployment Skill (`devops-deployment`)

[![Agent Skills Specification](https://img.shields.io/badge/Agent%20Skills-v1.0-blue.svg)](https://agentskills.io/specification)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-green.svg)](https://opensource.org/licenses/Apache-2.0)
[![CI/CD Platform](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-orange.svg)](https://github.com/features/actions)
[![Version: 1.1.0](https://img.shields.io/badge/Version-1.1.0-brightgreen.svg)](CHANGELOG.md)

An enterprise-grade, modular Continuous Deployment (CD) skill built in accordance with the official **[Agent Skills specification](https://agentskills.io/specification)**.

Designed for AI coding assistants (**Antigravity**, **Cursor**, **Claude Code**, **Windsurf**, and **GitHub Copilot**), this skill enables agents to inspect any application repository, enforce human-in-the-loop confirmation gates, synthesize hardened GitHub Actions deployment workflows for **cPanel** (via SSH or FTPS) and **Vercel**, and provide complete post-implementation operational manuals with optional **Telegram** topic alerts.

This repository serves as the **single source of truth** and includes full lifecycle management: global and project-level installation, live symbolic linking, semantic version pinning, update verification, and automated rollback.

---

## 1. Skill Directory Structure

Built on the principle of **progressive disclosure**, the skill separates high-level agent instructions from reference manuals, automation scripts, and workflow templates:

```
devops-deployment-skill/
├── SKILL.md                          # Master orchestration, stack detection & confirmation gates
├── README.md                         # Architecture, installation & operations manual
├── CHANGELOG.md                      # Semantic version history (Keep a Changelog)
├── skill.json                        # Skill discovery manifest & compatibility metadata
├── install.sh                        # POSIX installer wrapper
├── update.sh                         # POSIX updater wrapper with rollback protection
├── check-updates.sh                  # POSIX update checker across managed projects
├── status.sh                         # POSIX status inspection wrapper
├── uninstall.sh                      # POSIX uninstaller wrapper
├── bin/                              # Cross-platform CLI utilities
│   ├── skill-manager.py              # Zero-dependency Python 3 engine (cross-platform core)
│   ├── skill-manager                 # Unix executable wrapper
│   └── skill-manager.ps1             # Windows PowerShell wrapper
├── references/                       # Deep technical reference guides
│   ├── stack-detection-matrix.md     # Heuristics for runtimes, frameworks & monorepos
│   ├── cpanel-ssh-guide.md           # SSH keys, port probing, atomic sync & worker recycling
│   ├── cpanel-ftps-guide.md          # FTPS configuration, chroot directory traps & action tuning
│   ├── vercel-guide.md               # Vercel CLI prebuilt flow, project linking & token security
│   ├── telegram-notifications.md     # BotFather, topic routing, HTML escaping & lifecycle
│   ├── security-and-secrets.md       # GitHub Secrets, Environments, token permissions & masking
│   └── troubleshooting-manual.md     # Root cause analysis & fixes for top deployment errors
├── scripts/                          # Hardened POSIX helper scripts
│   ├── probe-ssh-port.sh             # Dynamic SSH port probing (configured, 22, 1219, 2222)
│   ├── normalize-ssh-key.sh          # OpenSSH key validation & passphrase stripping
│   ├── cpanel-deploy-remote.sh       # Atomic remote extraction, state preservation & rollback
│   └── telegram-notify.sh            # Telegram Bot API notification engine with HTML formatting
└── assets/                           # Production-tested GitHub Actions workflow & config templates
    ├── workflows/
    │   ├── deploy-cpanel-ssh.yml     # cPanel SSH deployment workflow template
    │   ├── deploy-cpanel-ftps.yml    # cPanel FTPS deployment workflow template
    │   ├── deploy-vercel.yml         # Vercel frontend deployment workflow template
    │   └── deploy-hybrid-monorepo.yml# Hybrid monorepo deployment workflow template
    └── configs/
        ├── htaccess-spa.txt          # Production Apache/LiteSpeed SPA rewrite template
        └── vercel-spa.json           # Production Vercel SPA rewrite configuration
```

---

## 2. Interactive Decision Engine (Tree of Choice)

An AI coding agent can inspect source code, lockfiles, and build artifacts, but **cannot inspect external infrastructure, hosting provider privileges, or server-side firewall configurations**.

Whenever more than one deployment target exists, or when external hosting capabilities cannot be inspected from code, the skill enforces an **interactive confirmation gate** resolved in a single consolidated turn:

```
[Phase 1: Codebase Inspection]
         │
         ├──► 1. Static Frontend / UI Only
         │         └──► [QUESTION 1: Target]
         │                   ├── Option 1: Vercel (Edge serverless & preview deployments)
         │                   ├── Option 2: cPanel via SSH (Atomic .zip + port probe)
         │                   └── Option 3: cPanel via FTPS (For shared plans without SSH)
         │
         ├──► 2. Backend / Full-Stack Application
         │         └──► [QUESTION 1: Target]
         │                   ├── Option 1: cPanel via SSH (Standard - backends require SSH)
         │                   └── Option 2: Other cloud provider (If SSH is disabled on cPanel)
         │
         ├──► 3. Monorepo (frontend/ + backend/)
         │         └──► [QUESTION 1: Target]
         │                   ├── Option 1: Hybrid (Frontend to Vercel, Backend to cPanel SSH)
         │                   └── Option 2: Split / Unified cPanel (Both services to cPanel SSH)
         │
         └──► Common Final Question (All Targets)
                   └──► [QUESTION 2: Telegram Alerts]
                             ├── Option 1: No Telegram notifications
                             ├── Option 2: Yes, alert on Production (main) only
                             └── Option 3: Yes, alert on all deployment branches (main & staging)
```

---

## 3. Installation & Distribution

### Prerequisites
- **Git** (version 2.20+)
- **Python** (version 3.8+; uses Standard Library only, zero pip dependencies)
- **Bash** (macOS, Linux, WSL, or Git Bash on Windows) OR **PowerShell** (Windows)

---

### Option A: Standard Skills CLI (`npx skills`)
This repository complies with the Agent Skills specification and can be installed directly using Vercel's `skills` CLI:

```bash
# Install into current project
npx skills add BirtuCan-Software/devops-deployment-skill

# Install globally across all projects
npx skills add BirtuCan-Software/devops-deployment-skill -g
```

---

### Option B: Bundled Skill Manager CLI

The repository includes a dedicated manager supporting **global installations**, **project-level copies**, **symbolic linking**, and **central registry tracking**.

#### 1. Global Installation (User-Level)
Installs the skill into your central user directory (`~/.agentskills/skills/devops-deployment`), making it accessible machine-wide:

```bash
# Linux / macOS / Git Bash
./install.sh --global

# Windows PowerShell
.\bin\skill-manager.ps1 install --global
```

To create a **live symbolic link** to this repository (so updates to this repo immediately reflect globally):
```bash
./install.sh --global --link
```

#### 2. Project-Level Installation (Self-Contained Copy)
Installs a self-contained copy of the skill directly into an application repository:

```bash
# Install into current project (auto-detects agent environment)
./install.sh --project .

# Install into a specific project path
./install.sh --project /path/to/my-application
```

> [!TIP]
> **Automatic Agent Detection:** If you omit `--agent`, the CLI automatically inspects the target directory for `.cursor/`, `.claude/`, `.gemini/`, `.windsurf/`, or `.github/` and installs the skill into the appropriate directory without requiring extra flags!

#### 3. Agent-Specific Discovery Paths
You can explicitly target the discovery folder of your preferred AI coding assistant using the `--agent` parameter:

| Agent | Discovery Path | Command |
| :--- | :--- | :--- |
| **Universal (agentskills.io)** | `.agentskills/devops-deployment` | `./install.sh --project . --agent agentskills` |
| **Antigravity / Gemini** | `.gemini/skills/devops-deployment` | `./install.sh --project . --agent antigravity` |
| **Cursor** | `.cursor/skills/devops-deployment` | `./install.sh --project . --agent cursor` |
| **Claude Code** | `.claude/skills/devops-deployment` | `./install.sh --project . --agent claude` |
| **Windsurf** | `.windsurf/skills/devops-deployment` | `./install.sh --project . --agent windsurf` |
| **GitHub Copilot** | `.github/skills/devops-deployment` | `./install.sh --project . --agent copilot` |

#### 4. Shared Symbolic Links Across Projects
Where supported, you can link individual projects to the central skill repository. Changes made in the central repository are immediately available to all linked projects:

```bash
./install.sh --project /path/to/my-application --link
```
*(On Windows, this automatically uses Directory Junctions, requiring no Administrator privileges).*

---

## 3. Version Management & Pinning

This project adheres to **Semantic Versioning** (`MAJOR.MINOR.PATCH`). Releases are tracked via Git tags (`v1.0.0`, `v1.1.0`) and documented in `CHANGELOG.md`.

### Pinning a Project to a Specific Version
To protect mission-critical application pipelines from unexpected upstream changes, you can pin a project installation to a specific release:

```bash
./install.sh --project /path/to/my-application --pin 1.0.0
```

When pinned:
- The installation records its pinned state in `.skill-metadata.json` and `~/.agentskills/registry.json`.
- Automated batch updates (`update --all`) will **safely skip** the pinned project.
- Upgrading a pinned project requires an intentional override via `--force`.

---

## 4. Update Management

The update manager checks for new versions, previews changelogs, performs atomic directory updates, and provides automated rollback.

### Inspect Installation Status
Get an instant report on your global installation, current repository, and all registered project installations (stale or removed paths are automatically pruned):

```bash
# Linux / macOS / Git Bash
./status.sh

# Target a specific project directory
./status.sh --project /path/to/my-application

# Or via check-updates
./check-updates.sh --status
```

### Check for Available Updates
Inspect your central installation and all registered projects for newer versions:

```bash
# Check all managed installations
./check-updates.sh
# or:
.\bin\skill-manager.ps1 check-updates
```

**Example Output:**
```
Target                 Version    Mode       Status             Path
--------------------------------------------------------------------------------
Global                 v1.1.0     symlink    🟢 Live linked      ~/.agentskills/skills/devops-deployment
Project (agentskills)  v1.0.0     copy       🟡 Update: v1.1.0  /workspaces/app1/.agentskills/devops-deployment
Project (cursor)       v1.0.0     copy       📌 Pinned (1.0.0)  /workspaces/app2/.cursor/skills/devops-deployment
--------------------------------------------------------------------------------
💡 1 installation(s) can be upgraded.
```

### Update a Single Project
```bash
# Updates skill in current project (shows preview & asks confirmation)
./update.sh

# Target specific project
./update.sh --project /path/to/my-application

# Skip interactive prompt
./update.sh --yes
```

### Update All Managed Projects
Updates all unpinned, copy-based installations registered in `~/.agentskills/registry.json`:

```bash
./update.sh --all
```

### Force-Upgrading a Pinned Project
```bash
./update.sh --project /path/to/my-application --force
```

### Safety & Automated Rollback
Every update follows an atomic execution pipeline:
1. Validates that the target is not locked or pinned.
2. Displays a changelog preview of incoming changes.
3. Creates a timestamped safety backup (`<target>.bak_<timestamp>`).
4. Copies the updated skill files.
5. Performs an integrity audit (verifying `SKILL.md` presence and YAML frontmatter).
6. **On failure:** Automatically restores the backup snapshot, preserving the existing installation and alerting the user.

---

## 5. Uninstallation

Safely removes the skill and unregisters it from `~/.agentskills/registry.json`:

```bash
# Remove global installation
./uninstall.sh --global

# Remove from current project
./uninstall.sh

# Remove from specific project
./uninstall.sh --project /path/to/my-application

# Remove all managed installations
./uninstall.sh --all
```

---

## 6. Central Installation Registry

All installations are tracked centrally in `~/.agentskills/registry.json`. This enables multi-project discovery, batch updates, and health monitoring without touching application source code.

Example `~/.agentskills/registry.json`:
```json
{
  "version": "1.0",
  "global": {
    "path": "/home/user/.agentskills/skills/devops-deployment",
    "mode": "symlink",
    "version": "1.1.0",
    "installedAt": "2026-11-16T22:30:00Z"
  },
  "projects": [
    {
      "projectPath": "/workspaces/ecommerce-app",
      "skillPath": "/workspaces/ecommerce-app/.agentskills/devops-deployment",
      "agent": "agentskills",
      "mode": "copy",
      "installedVersion": "1.1.0",
      "pinnedVersion": null,
      "installedAt": "2026-11-16T22:30:00Z",
      "lastUpdated": "2026-11-16T22:45:00Z"
    }
  ]
}
```

---

## 7. Troubleshooting

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| `Symbolic link privilege not held` | Windows security policy restricting symlinks. | The CLI automatically falls back to Directory Junctions (`mklink /J`) or copies. |
| `Installation is pinned to vX.X.X` | Project version is pinned. | Pass `--force` to intentionally upgrade: `./update.sh --force`. |
| `Target destination already exists` | Existing installation detected. | Pass `--force` or `-y` to overwrite existing skill files. |
| Agent does not detect skill | Agent using a non-standard discovery folder. | Specify agent layout during install: `./install.sh --agent <agent_name>`. |

---

## 8. License

This project is licensed under the [Apache License 2.0](LICENSE).
