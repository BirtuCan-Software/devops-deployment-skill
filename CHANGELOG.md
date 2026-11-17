# Changelog

All notable changes to the `devops-deployment` skill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-11-16

### Added
- **Multi-Mode Installation Support:**
  - **Global Installation:** Installs to user directory (`~/.agentskills/skills/devops-deployment` or agent-specific paths) with optional live symbolic linking (`--link`) to central repository.
  - **Project-Level Installation:** Installs a self-contained copy into the target repository's agent discovery directory (`.agentskills/`, `.gemini/skills/`, `.cursor/skills/`, etc.).
- **Central Installation Registry:**
  - Centralized registry maintained at `~/.agentskills/registry.json` tracking all installed projects, versions, installation modes (copy vs. symlink), and pin statuses.
- **Update Management & Atomic Rollback:**
  - `check-updates`: Compares local installations against latest repository releases and semantic tags.
  - `update`: Interactive or automated update with preview of changes (diff / changelog), confirmation gates, pre-update backup, atomic sync, and automated rollback if integrity verification fails.
  - `update --all`: Batch updates all registered, unpinned projects across the workstation.
- **Version Pinning:**
  - Ability to pin project installations to a specific semantic version (`--pin <version>`), preventing accidental or silent updates.
- **Cross-Platform Management Utilities:**
  - Core Python engine: `bin/skill-manager.py` (standard library only, zero pip dependencies, cross-platform on Windows, macOS, and Linux).
  - Native POSIX scripts: `install.sh`, `update.sh`, `uninstall.sh`, and `check-updates.sh`.
  - Native CLI wrappers: `bin/skill-manager` (Unix bash) and `bin/skill-manager.ps1` (Windows PowerShell).
  - Out-of-the-box compatibility with Vercel's `skills` CLI (`npx skills add`).
- **Package Manifest:** Added `skill.json` adhering to the Agent Skills discovery specification.
- **CLI Ergonomics & Agent Auto-Discovery:**
  - Added automatic agent environment detection (`detect_agent_environment`) in `skill-manager.py` (`.cursor/`, `.claude/`, `.gemini/`, `.windsurf/`, `.github/`), removing the need for manual `--agent` flags.
  - Added `status` command and `status.sh` wrapper for instant reporting on global, local, and registered project installations.
  - Added auto-pruning of stale/deleted temporary directories in `~/.agentskills/registry.json`.
- **Pipeline Delivery Modes (Zero-Clutter Mode):**
  - Added Zero-Clutter Single-File delivery mode with inline cURL Telegram notifications and atomic extraction fallbacks directly inside `.github/workflows/deploy.yml`, requiring zero auxiliary script files in target repositories.
- **Shared Hosting & Jailshell Resilience:**
  - Added Python 3 `zipfile` and `tar` fallbacks in `scripts/cpanel-deploy-remote.sh` and workflow templates when `unzip` is missing.
  - Added POSIX `cp -rn` and `find` fallbacks when `rsync` is disabled inside restricted CloudLinux jailshell environments.
- **Context Window Optimization:**
  - Streamlined `SKILL.md` by ~35% via strict progressive disclosure, delegating verbose static tables to `references/security-and-secrets.md` and `references/troubleshooting-manual.md`.

---

## [1.0.0] - 2026-11-16

### Added
- **Initial Release:** Complete DevOps Continuous Deployment skill conforming to the official Agent Skills specification (`agentskills.io`).
- **Progressive Disclosure Architecture:** Three-tier progressive disclosure model separating orchestration (`SKILL.md`), references (`references/`), scripts (`scripts/`), and templates (`assets/`).
- **Universal Repository Inspection:** Stack detection heuristics for Node.js, Python, PHP, Go, and static frontend SPAs with package manager detection (npm, pnpm, yarn, bun, pip, poetry, uv, composer).
- **Mandatory Confirmation Gates:**
  - Gate 1: Stack detection findings and target hosting confirmation (cPanel SSH vs. FTPS vs. Vercel vs. Hybrid).
  - Gate 2: Pre-execution file creation and overwrite guard.
- **cPanel Deployment (SSH & FTPS):**
  - Dynamic SSH port probing across custom ports (`1219`, `2222`, and `22`).
  - OpenSSH key normalization and non-interactive passphrase stripping.
  - Server-side atomic release extraction with state preservation (`.env`, SQLite databases, uploads/media).
  - Web server worker recycling (`tmp/restart.txt` for LiteSpeed/Passenger; OPcache for PHP).
  - FTPS deployment via `SamKirkland/FTP-Deploy-Action@v4.3.5` with directory chroot trap handling.
- **Vercel Deployment:**
  - Zero-config deployment using official Vercel CLI prebuilt flow (`vercel pull`, `vercel build`, `vercel deploy --prebuilt`).
  - Automatic Single Page Application (SPA) fallback routing via `vercel.json`.
- **Telegram Deployment Notifications:**
  - Atomic **Start-Delete-Replace** lifecycle posting to group topics (`message_thread_id`).
  - HTML entity formatting eliminating MarkdownV2 parse errors on arbitrary Git commit messages.
- **Engineering Guides:** Detailed documentation for stack detection, SSH, FTPS, Vercel, Telegram, security/secrets, and troubleshooting.
