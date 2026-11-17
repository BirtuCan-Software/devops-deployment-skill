# cPanel SSH Continuous Deployment Guide

This reference guide details enterprise best practices for continuous deployment to cPanel shared, VPS, and dedicated hosting environments via SSH using GitHub Actions.

---

## 1. cPanel Shared Hosting Architecture & Constraints

Shared hosting on cPanel imposes specific security boundaries and operational constraints:

1. **Jailed Shell (Jailshell / CageFS):**
   - User sessions are chrooted under CloudLinux CageFS or cPanel's `jailshell`.
   - Privilege escalation (`sudo`) is strictly disabled.
   - Compilers (`gcc`, `make`) and development header files (`python3-dev`, `libmysqlclient-dev`) are disabled or restricted.
   - All deployments must build assets inside the GitHub Actions runner (an unconstrained Ubuntu Linux container) and transfer prebuilt, optimized artifacts to the server.

2. **Security Permissions (suPHP / suExec / LSAPI):**
   - cPanel web servers (Apache with suPHP/FastCGI or LiteSpeed LSAPI) enforce strict permission audits.
   - **Any directory with `777` permissions or file with `666` or `777` permissions will instantly trigger `HTTP 500 Internal Server Error`**.
   - Mandatory permissions:
     - Directories: `0755` (`drwxr-xr-x`)
     - Files: `0644` (`-rw-r--r--`)
     - Executable scripts (CGI/Passenger): `0755`

3. **Process Supervision & Recycling:**
   - Web workers (LiteSpeed Web Server or Phusion Passenger) maintain persistent worker pools for Node.js, Python, and Ruby applications.
   - Updating files on disk does not immediately restart the in-memory workers.
   - Worker restart trigger: creating or updating the timestamp of `tmp/restart.txt` inside the application root (`touch tmp/restart.txt`).

---

## 2. cPanel SSH Key Setup (Click-by-Click)

To authenticate GitHub Actions to cPanel via SSH without passwords:

### Step 1: Generate or Import Key in cPanel
1. Log in to your cPanel dashboard.
2. Scroll to the **Security** section and click **SSH Access**.
3. Click **Manage SSH Keys**.
4. Click **Generate a New Key**:
   - **Key Name:** `github_actions_deploy` (or leave as `id_rsa`)
   - **Key Password:** Enter a strong passphrase or leave empty (if empty, no passphrase stripping is required).
   - **Key Type:** `RSA`
   - **Key Size:** `4096` (recommended) or `2048`.
5. Click **Generate Key**.

### Step 2: Authorize the Public Key
> [!IMPORTANT]
> Newly generated keys in cPanel are **NOT authorized by default**. If you skip this step, SSH authentication will fail with `Permission denied (publickey)`.
1. Under *Public Keys*, find your newly generated key.
2. Click **Manage** next to the key.
3. Click **Authorize** to append the key to `~/.ssh/authorized_keys`.

### Step 3: View & Download the Private Key
1. Under *Private Keys*, find the key and click **View/Download**.
2. If a passphrase was set, enter it to convert the key to OpenSSH format, or click **Download Key**.
3. Copy the entire contents of the private key, including:
   ```
   -----BEGIN RSA PRIVATE KEY-----
   ...
   -----END RSA PRIVATE KEY-----
   ```
4. Save this value into the GitHub Secret `CPANEL_SSH_KEY`.

---

## 3. Dynamic SSH Port Probing

Many hosting providers (Namecheap, Bluehost, HostGator, InMotion, etc.) disable standard port `22` to mitigate automated brute-force attacks, binding SSH instead to:
- Port `1219` (Common shared hosting SSH port)
- Port `2222` (Alternative cPanel SSH port)
- Custom ISP port configured by the system administrator

### Automated Port Probe Routine:
The deployment pipeline probes candidate ports in sequence using `nc` (netcat), bash `/dev/tcp`, or `ssh-keyscan` with a 3-second timeout:

```bash
candidate_ports=("$PREFERRED_PORT" 22 1219 2222)
for port in "${candidate_ports[@]}"; do
  if [ -n "$port" ] && ssh-keyscan -p "$port" -T 3 "$HOST" 2>/dev/null | grep -q "$HOST"; then
    echo "Identified active SSH port: $port"
    SELECTED_PORT="$port"
    break
  fi
done
```

The script then populates `~/.ssh/known_hosts` to prevent `Host key verification failed` prompts.

---

## 4. Atomic Deployments & State Preservation

A naive deployment copies files directly over the live directory while web traffic is hitting the server. This causes broken page loads, asset 404s, and half-migrated states.

### Enterprise Deployment Strategy:
1. **Runner Packaging:**
   - Compile all assets in the runner (`npm run build`, `collectstatic`, etc.).
   - Package production files into a unique zip: `release-${{ github.sha }}.zip`.
   - Exclude `.git`, development configs, test suites, and temporary caches.
2. **Transfer:**
   - Securely copy the archive to `~/$CPANEL_APP_DIR/incoming/` via `scp`.
3. **Server-Side Extraction & Sync:**
   - Unpack archive into an isolated temporary folder: `~/$CPANEL_APP_DIR/incoming/temp_${BUILD_ID}/`.
   - Enforce file permissions (`755` dirs / `644` files).
   - Sync files into the live directory while **strictly preserving persistent runtime assets**:
     - `.env` and environment configuration files.
     - SQLite databases (`*.db`, `*.sqlite`, `*.sqlite3`).
     - User media and upload folders (`storage/`, `media/`, `uploads/`, `public/uploads/`).
     - Server-side runtime logs (`logs/`, `storage/logs/`).
   - Run remote post-deployment tasks (database migrations, cache clearing).
   - Recycle worker processes: `touch tmp/restart.txt`.
   - Clean up incoming archive and temporary directories.

---

## 5. Technology-Specific cPanel Configurations

### A. Python / Django / FastAPI via Phusion Passenger
1. **WSGI Entrypoint:**
   cPanel's *Setup Python App* generates a `passenger_wsgi.py` in the application directory.
   Ensure the WSGI entrypoint correctly bridges your application:
   ```python
   # Example passenger_wsgi.py for Django
   import os
   import sys
   from <project_name>.wsgi import application
   sys.path.insert(0, os.path.dirname(__file__))
   ```
2. **Database Driver Workaround (`pymysql`):**
   Standard `mysqlclient` requires compiling C extensions during `pip install`, which fails on shared hosting due to missing `mysql_config` headers.
   Add `pymysql` to your dependencies and insert this into your `settings.py` or `passenger_wsgi.py`:
   ```python
   import pymysql
   pymysql.install_as_MySQLdb()
   ```

### B. PHP / Laravel Applications
1. **Document Root Alignment:**
   Laravel requires the web root to point to `public/`. In cPanel:
   - For primary domains (`public_html`): Either place the Laravel codebase in `~/laravel_app/` and symlink `public/` to `~/public_html/`, or use an `.htaccess` rewrite inside `public_html/`.
   - For subdomains / addon domains: Set the document root in cPanel directly to `~/subdomain/public/`.
2. **Post-Deploy Commands:**
   ```bash
   php artisan migrate --force
   php artisan config:cache
   php artisan route:cache
   php artisan view:cache
   ```

### C. Single Page Applications (React, Vue, Vite SPA)
If serving a static SPA from cPanel Apache/LiteSpeed, refreshing any route other than `/` will return a 404 error unless Apache URL rewriting is configured. Ensure a production `.htaccess` is present:

```apache
Options -Indexes
RewriteEngine On
RewriteBase /
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
RewriteRule ^ index.html [L]
```
