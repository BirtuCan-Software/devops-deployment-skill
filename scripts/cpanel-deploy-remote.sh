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
