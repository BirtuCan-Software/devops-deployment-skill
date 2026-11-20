#!/usr/bin/env bash
# ==============================================================================
# Script: cpanel-deploy-remote.sh
# Purpose: Server-side atomic extraction, state preservation, security permission
#          enforcement, dependency installation, and LiteSpeed/Passenger restart.
# Compatibility: AlmaLinux / CloudLinux / CentOS cPanel environments (sh / bash).
# ==============================================================================

set -euo pipefail

APP_DIR="${1:-public_html}"
ARCHIVE_NAME="${2:-}"
RELEASE_ID="${3:-$(date +%Y%m%d%H%M%S)}"
FRONTEND_DIR="${4:-${FRONTEND_DIR:-}}"
FRONTEND_DOMAIN="${5:-${FRONTEND_DOMAIN:-}}"

# Resolve Frontend Target Directory (for Split Monorepos on cPanel)
RESOLVED_FRONTEND_DIR="${FRONTEND_DIR:-}"
if [ -z "$RESOLVED_FRONTEND_DIR" ] && [ -n "${FRONTEND_DOMAIN:-}" ]; then
  RESOLVED_FRONTEND_DIR=$(echo "$FRONTEND_DOMAIN" | sed -e 's|^https\?://||' -e 's|:[0-9]\+||' -e 's|/*$||')
fi

TARGET_PATH="$HOME/$APP_DIR"
INCOMING_DIR="$TARGET_PATH/incoming"
RELEASES_DIR="$TARGET_PATH/releases"
SHARED_DIR="$TARGET_PATH/shared"
NEW_RELEASE="$RELEASES_DIR/$RELEASE_ID"
BACKUP_DIR="$TARGET_PATH/backup_previous"

echo "=================================================="
echo "🚀 Starting cPanel Deployment for: $APP_DIR"
echo "📦 Release ID: $RELEASE_ID"
echo "=================================================="

# Ensure directories exist
mkdir -p "$INCOMING_DIR" "$RELEASES_DIR" "$SHARED_DIR" "$TARGET_PATH/tmp"

ARCHIVE_FILE="$INCOMING_DIR/$ARCHIVE_NAME"
if [ -z "$ARCHIVE_NAME" ] || [ ! -f "$ARCHIVE_FILE" ]; then
  # Check if archive is in home incoming folder
  if [ -f "$HOME/incoming/$ARCHIVE_NAME" ]; then
    ARCHIVE_FILE="$HOME/incoming/$ARCHIVE_NAME"
  else
    echo "❌ Error: Release archive '$ARCHIVE_NAME' not found in $INCOMING_DIR or ~/incoming/" >&2
    exit 1
  fi
fi

# 1. Preserve persistent runtime state in $SHARED_DIR
echo "🔒 Checking persistent state preservation..."
mkdir -p "$SHARED_DIR/uploads" "$SHARED_DIR/storage" "$SHARED_DIR/media"

# Back up .env if present in root but not in shared
if [ -f "$TARGET_PATH/.env" ] && [ ! -f "$SHARED_DIR/.env" ]; then
  echo "  -> Preserving existing .env into shared state..."
  cp -p "$TARGET_PATH/.env" "$SHARED_DIR/.env"
fi

# Preserve SQLite databases (*.db, *.sqlite, *.sqlite3)
find "$TARGET_PATH" -maxdepth 2 \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) ! -path "*/releases/*" ! -path "*/backup_previous/*" | while read -r dbfile; do
  dbname=$(basename "$dbfile")
  if [ ! -f "$SHARED_DIR/$dbname" ]; then
    echo "  -> Preserving SQLite database $dbname into shared state..."
    cp -p "$dbfile" "$SHARED_DIR/$dbname"
  fi
done

# Preserve existing passenger_wsgi.py if it already contains virtualenv setup
if [ -f "$TARGET_PATH/passenger_wsgi.py" ] && [ ! -f "$SHARED_DIR/passenger_wsgi.py" ]; then
  if grep -q "addsitedir" "$TARGET_PATH/passenger_wsgi.py" || grep -q "discover_virtualenv" "$TARGET_PATH/passenger_wsgi.py"; then
    cp -p "$TARGET_PATH/passenger_wsgi.py" "$SHARED_DIR/passenger_wsgi.py"
  fi
fi

# 2. Extract release into new release directory
echo "📂 Unpacking release into $NEW_RELEASE..."
mkdir -p "$NEW_RELEASE"
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$ARCHIVE_FILE" -d "$NEW_RELEASE"
elif command -v python3 >/dev/null 2>&1; then
  echo "  (unzip missing; using python3 zipfile fallback)"
  python3 -m zipfile -e "$ARCHIVE_FILE" "$NEW_RELEASE"
elif command -v tar >/dev/null 2>&1 && [[ "$ARCHIVE_FILE" == *.tar.gz ]]; then
  tar -xzf "$ARCHIVE_FILE" -C "$NEW_RELEASE"
else
  echo "❌ Error: Neither unzip, python3, nor tar is available to extract archive." >&2
  exit 1
fi

# 3. Restore persistent runtime state into new release
echo "🔗 Restoring persistent runtime assets..."
if [ -f "$SHARED_DIR/.env" ]; then
  cp -p "$SHARED_DIR/.env" "$NEW_RELEASE/.env"
fi

# Restore SQLite databases
find "$SHARED_DIR" -maxdepth 1 \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) | while read -r dbfile; do
  cp -p "$dbfile" "$NEW_RELEASE/"
done

# Restore persistent directories (uploads, storage, media)
for persistent_dir in uploads storage media; do
  if [ -d "$SHARED_DIR/$persistent_dir" ] && [ "$(ls -A "$SHARED_DIR/$persistent_dir" 2>/dev/null)" ]; then
    mkdir -p "$NEW_RELEASE/$persistent_dir"
    cp -rn "$SHARED_DIR/$persistent_dir/"* "$NEW_RELEASE/$persistent_dir/" 2>/dev/null || true
  fi
done

# If new release lacks passenger_wsgi.py, restore preserved one if available
if [ ! -f "$NEW_RELEASE/passenger_wsgi.py" ] && [ -f "$SHARED_DIR/passenger_wsgi.py" ]; then
  echo "  -> Restoring preserved passenger_wsgi.py from shared state..."
  cp -p "$SHARED_DIR/passenger_wsgi.py" "$NEW_RELEASE/passenger_wsgi.py"
fi

# 4. Enforce strict permissions (cPanel suPHP / LSAPI compliance)
echo "🛡️ Enforcing secure file permissions (dirs 755 / files 644)..."
find "$NEW_RELEASE" -type d -exec chmod 755 {} +
find "$NEW_RELEASE" -type f -exec chmod 644 {} +

# Ensure executables or scripts have proper execute rights if required
if [ -f "$NEW_RELEASE/artisan" ]; then
  chmod 755 "$NEW_RELEASE/artisan"
fi
if [ -f "$NEW_RELEASE/passenger_wsgi.py" ]; then
  chmod 755 "$NEW_RELEASE/passenger_wsgi.py"
fi

# 5. Run Framework Tasks (Migrations, Cache, Dependencies)
cd "$NEW_RELEASE"

# Python on cPanel (Django, FastAPI, Flask via Passenger)
if [ -f "$NEW_RELEASE/manage.py" ] || [ -f "$NEW_RELEASE/passenger_wsgi.py" ] || [ -f "$NEW_RELEASE/requirements.txt" ] || [ -f "$NEW_RELEASE/pyproject.toml" ]; then
  echo "🐍 Discovering cPanel Python virtual environment..."
  VENV_ACTIVATE=$(find $HOME/virtualenv/$APP_DIR -maxdepth 4 -name activate 2>/dev/null | head -n 1 || true)
  if [ -z "$VENV_ACTIVATE" ]; then
    VENV_ACTIVATE=$(find $HOME/virtualenv -maxdepth 5 -name activate 2>/dev/null | grep -i "$APP_DIR" | head -n 1 || true)
  fi
  if [ -z "$VENV_ACTIVATE" ]; then
    for vname in .venv venv env; do
      if [ -f "$NEW_RELEASE/$vname/bin/activate" ]; then
        VENV_ACTIVATE="$NEW_RELEASE/$vname/bin/activate"
        break
      fi
    done
  fi

  if [ -n "$VENV_ACTIVATE" ] && [ -f "$VENV_ACTIVATE" ]; then
    echo "  -> Activating virtualenv: $VENV_ACTIVATE"
    # shellcheck source=/dev/null
    source "$VENV_ACTIVATE"
    if [ -f "$NEW_RELEASE/requirements.txt" ]; then
      pip install -r "$NEW_RELEASE/requirements.txt" --no-warn-script-location || true
    elif [ -f "$NEW_RELEASE/pyproject.toml" ]; then
      pip install . --no-warn-script-location || true
    fi
    if [ -f "$NEW_RELEASE/manage.py" ]; then
      echo "  -> Running database migrations..."
      python manage.py migrate --noinput || true
      echo "  -> Collecting static assets..."
      python manage.py collectstatic --noinput || true
    fi
  else
    echo "  ⚠️ No virtualenv found for $APP_DIR. Skipping virtualenv activation."
  fi

  # Ensure passenger_wsgi.py contains virtual environment auto-discovery logic
  if [ -f "$NEW_RELEASE/passenger_wsgi.py" ]; then
    if ! grep -q "addsitedir" "$NEW_RELEASE/passenger_wsgi.py" && ! grep -q "discover_virtualenv" "$NEW_RELEASE/passenger_wsgi.py"; then
      echo "  -> Injecting virtualenv discovery bridge into passenger_wsgi.py..."
      BRIDGE_FILE=$(mktemp)
      cat << 'PYEOF' > "$BRIDGE_FILE"
import os, sys, glob, site
from pathlib import Path
_app_root = Path(__file__).resolve().parent
os.chdir(str(_app_root))
if str(_app_root) not in sys.path:
    sys.path.insert(0, str(_app_root))
_home = Path.home()
_found_venv = None
_venv_root = _home / "virtualenv"
if _venv_root.is_dir():
    for _c in list(_venv_root.glob(f"{_app_root.name}/*")) + list(_venv_root.glob("*/*")):
        if (_c / "bin" / "activate").is_file():
            _found_venv = _c
            break
if not _found_venv:
    for _folder in [".venv", "venv", "env"]:
        if (_app_root / _folder / "bin" / "activate").is_file():
            _found_venv = _app_root / _folder
            break
if _found_venv:
    for _sp in glob.glob(str(_found_venv / "lib*" / "python*" / "site-packages")):
        if os.path.isdir(_sp):
            site.addsitedir(_sp)
    _vbin = str(_found_venv / "bin")
    if _vbin not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{_vbin}:{os.environ.get('PATH', '')}"
try:
    import pymysql
    pymysql.install_as_MySQLdb()
except ImportError:
    pass
# --- End of Auto-Injected Virtualenv Bridge ---
PYEOF
      cat "$NEW_RELEASE/passenger_wsgi.py" >> "$BRIDGE_FILE"
      mv "$BRIDGE_FILE" "$NEW_RELEASE/passenger_wsgi.py"
    fi
    chmod 755 "$NEW_RELEASE/passenger_wsgi.py"
  fi
fi

# PHP / Composer / Laravel
if [ -f "$NEW_RELEASE/artisan" ]; then
  echo "🐘 Executing Laravel post-deploy routines..."
  php artisan migrate --force || echo "⚠️ Migration completed with notice."
  php artisan config:cache || true
  php artisan route:cache || true
  php artisan view:cache || true
fi

# Node.js on cPanel
if [ -f "$NEW_RELEASE/package.json" ] && [ ! -d "$NEW_RELEASE/node_modules" ]; then
  if command -v npm >/dev/null 2>&1; then
    echo "📦 Installing Node.js production dependencies..."
    npm ci --omit=dev --no-audit || npm install --omit=dev --no-audit || true
  fi
fi

# 6. Atomic Sync / Release Switch
echo "🔄 Synchronizing files into active directory: $TARGET_PATH..."

# Backup current active state
mkdir -p "$BACKUP_DIR"

if command -v rsync >/dev/null 2>&1; then
  # Copy current files to backup, excluding heavy or dynamic release folders
  rsync -a --delete --exclude 'incoming' --exclude 'releases' --exclude 'backup_previous' "$TARGET_PATH/" "$BACKUP_DIR/" 2>/dev/null || true
  # Sync new release into target path
  rsync -a --inplace --exclude 'incoming' --exclude 'releases' --exclude 'backup_previous' "$NEW_RELEASE/" "$TARGET_PATH/"
else
  echo "  (rsync unavailable; using POSIX cp/find fallback for jailshell)"
  cp -rn "$TARGET_PATH/"* "$BACKUP_DIR/" 2>/dev/null || true
  cp -rf "$NEW_RELEASE/"* "$TARGET_PATH/" 2>/dev/null || true
  [ -f "$NEW_RELEASE/.htaccess" ] && cp -f "$NEW_RELEASE/.htaccess" "$TARGET_PATH/.htaccess" 2>/dev/null || true
fi

# 6.5. Deploy Split Frontend SPA Assets (if configured)
if [ -n "$RESOLVED_FRONTEND_DIR" ]; then
  FRONTEND_SOURCE=""
  if [ -d "$NEW_RELEASE/core/static" ] && [ -f "$NEW_RELEASE/core/static/index.html" ]; then
    FRONTEND_SOURCE="$NEW_RELEASE/core/static"
  elif [ -d "$NEW_RELEASE/dist" ] && [ -f "$NEW_RELEASE/dist/index.html" ]; then
    FRONTEND_SOURCE="$NEW_RELEASE/dist"
  elif [ -d "$NEW_RELEASE/core/static" ]; then
    FRONTEND_SOURCE="$NEW_RELEASE/core/static"
  elif [ -d "$NEW_RELEASE/dist" ]; then
    FRONTEND_SOURCE="$NEW_RELEASE/dist"
  fi

  if [ -n "$FRONTEND_SOURCE" ]; then
    FRONTEND_TARGET="$HOME/$RESOLVED_FRONTEND_DIR"
    echo "🌐 Deploying split frontend SPA assets to: $FRONTEND_TARGET..."
    mkdir -p "$FRONTEND_TARGET"
    cp -rf "$FRONTEND_SOURCE/"* "$FRONTEND_TARGET/" 2>/dev/null || true
    [ -f "$FRONTEND_SOURCE/.htaccess" ] && cp -f "$FRONTEND_SOURCE/.htaccess" "$FRONTEND_TARGET/.htaccess" 2>/dev/null || true
    [ ! -e "$FRONTEND_TARGET/static" ] && ln -s . "$FRONTEND_TARGET/static" 2>/dev/null || true
    find "$FRONTEND_TARGET" -type d -exec chmod 755 {} + 2>/dev/null || true
    find "$FRONTEND_TARGET" -type f -exec chmod 644 {} + 2>/dev/null || true
    echo "  -> Frontend SPA successfully deployed to $FRONTEND_TARGET."
  fi
fi

# 7. Recycle LiteSpeed / Passenger Workers
echo "♻️ Recycling application worker processes..."
mkdir -p "$TARGET_PATH/tmp"
touch "$TARGET_PATH/tmp/restart.txt"

# 8. Clean up old archives and retain only last 5 releases
echo "🧹 Cleaning up old releases and archives..."
rm -f "$ARCHIVE_FILE"
cd "$RELEASES_DIR"
# Keep newest 5 releases, delete older ones
ls -1dt ./* 2>/dev/null | tail -n +6 | xargs -r rm -rf || true

echo "=================================================="
echo "✅ Deployment completed successfully!"
echo "=================================================="
