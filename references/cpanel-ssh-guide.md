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

#### 1. CloudLinux Python Selector & Passenger Architecture
On cPanel servers using CloudLinux Python Selector or LiteSpeed Phusion Passenger:
- **Isolated Virtual Environments:** When creating an application via cPanel's *Setup Python App*, the virtual environment is provisioned at:
  ```
  $HOME/virtualenv/<app_dir>/<python_version>/
  ```
  Installed packages reside inside `lib/pythonX.X/site-packages/` and `lib64/pythonX.X/site-packages/`.
- **The Global Python Trap:** Phusion Passenger spawns application worker processes using the host's base Python interpreter. If `passenger_wsgi.py` directly executes `from myapp.wsgi import application`, Python attempts to import packages from global site-packages, failing with `ModuleNotFoundError: No module named 'django'` (or `pymysql`, `rest_framework`, etc.).
- **The Requirement for `site.addsitedir()`:**
  Adding paths via `sys.path.append()` is insufficient because it does not process `.pth` files or configure package namespaces. Using `site.addsitedir()` ensures all installed dependencies, namespace packages, and compiled wheels in `lib/` and `lib64/` are fully registered.
- **Working Directory Enforcement (`os.chdir`):**
  Passenger worker processes may run with the current working directory set to `$HOME` or `/`. Forcing `os.chdir(APP_ROOT)` ensures configuration loaders like `python-decouple`, `django-environ`, and `dotenv` locate the `.env` file reliably.
- **The Disguised "CORS Error" Phenomenon:**
  When Passenger crashes during WSGI bootstrap, it aborts before Django's `CorsMiddleware` can process the request. LiteSpeed Web Server intercepts the crash and serves a static 500 HTML error page with no `Access-Control-Allow-Origin` headers. Modern browsers block the response with a misleading CORS error. Always check `stderr.log` before troubleshooting CORS headers.

#### 2. Hardened `passenger_wsgi.py` Bridge
Deployments should utilize the enterprise virtualenv bridge (`assets/configs/passenger-wsgi-template.py`):
```python
import os, sys, glob, site
from pathlib import Path

# Enforce working directory and sys.path
APP_ROOT = Path(__file__).resolve().parent
os.chdir(str(APP_ROOT))
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

# Dynamically locate CloudLinux / cPanel virtualenv
home = Path.home()
target_venv = None
venv_root = home / "virtualenv"
if venv_root.is_dir():
    for candidate in list(venv_root.glob(f"{APP_ROOT.name}/*")) + list(venv_root.glob("*/*")):
        if (candidate / "bin" / "activate").is_file():
            target_venv = candidate
            break

# Fallback: check in-project virtualenvs (.venv, venv, env)
if not target_venv:
    for folder in [".venv", "venv", "env"]:
        candidate = APP_ROOT / folder
        if (candidate / "bin" / "activate").is_file():
            target_venv = candidate
            break

# Register virtualenv site-packages with site.addsitedir
if target_venv:
    for sp in glob.glob(str(target_venv / "lib*" / "python*" / "site-packages")):
        if os.path.isdir(sp):
            site.addsitedir(sp)
    vbin = str(target_venv / "bin")
    if vbin not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{vbin}:{os.environ.get('PATH', '')}"

# Pure-Python MySQL bridge for shared hosting
try:
    import pymysql
    pymysql.install_as_MySQLdb()
except ImportError:
    pass

# Export WSGI application
from backend_config.wsgi import application
```

#### 3. Database Driver Workaround (`pymysql`)
Standard `mysqlclient` requires compiling C extensions during `pip install`, which fails on shared hosting due to missing `mysql_config` headers.
Add `pymysql` to `requirements.txt` and ensure `pymysql.install_as_MySQLdb()` is executed before Django initializes.

#### 4. Automated Python Lifecycle Tasks
During remote SSH deployment, the deployment script executes:
```bash
# 1. Discover and activate virtual environment (search depth 4/5)
source $VENV_ACTIVATE

# 2. Install dependencies without script path warnings
pip install -r requirements.txt --no-warn-script-location

# 3. Execute Django migrations and collect static assets
python manage.py migrate --noinput
python manage.py collectstatic --noinput

# 4. Trigger Passenger worker pool reload
touch tmp/restart.txt
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

### D. Split Monorepos on cPanel (Vite SPA Subdomain + Django/FastAPI Passenger)

When a monorepo deploys both a frontend SPA and a backend Python API to cPanel, they must be partitioned into two distinct filesystem targets:

1. **Separation of Targets:**
   - **Python Application Root (`$HOME/$CPANEL_APP_DIR`, e.g. `~/natranapi`):** Hosts the backend codebase, Python dependencies, database configuration, migrations, static assets, and `passenger_wsgi.py`.
   - **Apache Subdomain Document Root (`$HOME/$CPANEL_FRONTEND_DIR`, e.g. `~/natran.koshomecafe.com`):** Hosts the built frontend SPA static assets (`index.html`, `assets/`, `.htaccess`).

2. **Frontend Routing & Vite Base Configuration:**
   - SPAs hosted on standalone subdomains (e.g. `natran.koshomecafe.com`) must build with `base: "/"` (not `"/static/"` or relative `./`).
   - The subdomain document root must contain an Apache SPA rewrite `.htaccess` routing all non-file requests to `index.html`.
   - A compatibility symlink (`ln -s . static`) is created inside the frontend document root to prevent asset 404s if legacy paths reference `/static/`.

3. **cPanel CloudLinux/CageFS Virtualenv Discovery:**
   - Standard cPanel CloudLinux "Setup Python App" places virtualenvs in:
     ```
     $HOME/virtualenv/<app_dir>/<python_version>/bin/activate
     ```
   - Discovering this virtualenv requires a search depth of at least **4** (not depth 2):
     ```bash
     VENV_ACTIVATE=$(find $HOME/virtualenv/$APP_DIR -maxdepth 4 -name activate 2>/dev/null | head -n 1 || true)
     if [ -z "$VENV_ACTIVATE" ]; then
       VENV_ACTIVATE=$(find $HOME/virtualenv -maxdepth 5 -name activate 2>/dev/null | grep -i "$APP_DIR" | head -n 1 || true)
     fi
     ```
   - Once activated, run migrations (`python manage.py migrate --noinput`) and collectstatic, followed by recycling Passenger workers (`touch $HOME/$CPANEL_APP_DIR/tmp/restart.txt`).
