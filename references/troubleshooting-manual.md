# DevOps Troubleshooting & Disaster Recovery Manual

This manual provides diagnostic flows and immediate one-line remediation commands for the most frequent failures encountered during automated CI/CD deployments to cPanel and Vercel.

---

## 1. Quick Diagnostic Matrix

| Error Message / Symptom | Primary Cause | Immediate Fix |
| :--- | :--- | :--- |
| `ssh: connect to host ... port 22: Connection timed out` | Port 22 blocked by shared hosting firewall. | Probe alternate ports (`1219` or `2222`) or whitelist runner IP. |
| `Permission denied (publickey)` | SSH key not authorized in cPanel. | In cPanel: *SSH Access > Manage SSH Keys > Manage > Authorize*. |
| `Load key: error in libcrypto` | Corrupted key headers or Windows `CRLF` endings. | Run `dos2unix` or normalize headers using `normalize-ssh-key.sh`. |
| `FTP-Deploy-Action: ETIMEDOUT` | Passive mode port range blocked. | Switch to SSH deployment or request passive FTP unblock from host. |
| `Vercel CLI: Error: No project linked` | Missing `VERCEL_ORG_ID` or `VERCEL_PROJECT_ID`. | Pass both variables into `env:` block in GitHub Actions step. |
| `HTTP 500 Internal Server Error` | Incorrect file permissions (e.g. `777`). | Run `chmod 755` on dirs and `chmod 644` on files on the server. |
| `404 Not Found` on browser page refresh | Missing SPA rewrite rules. | Add `.htaccess` (cPanel) or `vercel.json` (Vercel) rewrites. |
| `Telegram HTTP 400 Bad Request` | Unescaped character or invalid thread ID. | Switch to HTML mode with entity escaping via `telegram-notify.sh`. |

---

## 2. SSH Deployment Troubleshooting (cPanel)

### Issue A: `Permission denied (publickey)`
- **Symptom:** The runner connects to the host on the correct port, but authentication is rejected immediately.
- **Root Cause:**
  1. The public key was generated in cPanel but never **Authorized**.
  2. The private key saved in GitHub Secret `CPANEL_SSH_KEY` was truncated or missing the leading `-----BEGIN RSA PRIVATE KEY-----` or trailing newline.
  3. The username defined in `vars.CPANEL_USER` does not match the cPanel Linux account name.
- **Resolution Steps:**
  1. Log in to cPanel -> **SSH Access** -> **Manage SSH Keys**.
  2. Check the **Public Keys** table. If the key says *not authorized*, click **Manage** -> **Authorize**.
  3. Ensure your secret in GitHub Secrets starts with `-----BEGIN` on its own line and ends with `-----END ...` with a valid newline.

### Issue B: SSH Port Timeouts
- **Symptom:** Pipeline hangs for 30–60 seconds, then outputs `ssh: connect to host cpanel.example.com port 22: Connection timed out`.
- **Root Cause:** The hosting company runs SSH on an alternative port (commonly `1219` or `2222`) to stop bots.
- **Resolution Steps:**
  - Verify SSH port in your hosting welcome email or cPanel sidebar under *General Information > Server Information*.
  - Update `CPANEL_SSH_PORT` in GitHub Secrets.
  - The bundled script `scripts/probe-ssh-port.sh` will automatically test candidate ports and select the open one.

### Issue C: Password or Passphrase Prompts
- **Symptom:** `Enter passphrase for key ...` appears in logs and job times out.
- **Resolution:**
  - Provide `CPANEL_SSH_PASSPHRASE` in GitHub Secrets. The script `scripts/normalize-ssh-key.sh` uses `ssh-keygen -p` to strip the passphrase non-interactively in runner memory before connecting.

---

## 3. FTPS Deployment Troubleshooting (cPanel)

### Issue A: Site Shows Old Version After Successful Deployment
- **Symptom:** GitHub Actions reports green checkmark on FTPS sync, but the browser displays stale code or 404.
- **Root Cause:** **The cPanel Directory Trap**. When creating the FTP account, cPanel defaulted the directory to `public_html/username/`. The files were uploaded into that subfolder.
- **Resolution Steps:**
  1. In cPanel, go to **FTP Accounts**.
  2. Check the **Directory** column for the deployer account.
  3. If it points to `public_html/<username>`, delete the FTP account and recreate it, setting the directory strictly to `public_html` (or `public_html/staging`).

### Issue B: SPA 404 on Route Refresh
- **Symptom:** Visiting `https://example.com/` works, but navigating to `https://example.com/login` and refreshing returns 404 Not Found.
- **Root Cause:** Apache/LiteSpeed web server receives a request for physical file `/login`, finds nothing, and serves a 404 page instead of passing routing to `index.html`.
- **Resolution Steps:**
  - Verify that `.htaccess` is present in your build output folder (`dist/`) before uploading.
  - Template `.htaccess`:
    ```apache
    Options -Indexes
    RewriteEngine On
    RewriteBase /
    RewriteCond %{REQUEST_FILENAME} -f [OR]
    RewriteCond %{REQUEST_FILENAME} -d
    RewriteRule ^ - [L]
    RewriteRule ^ index.html [L]
    ```

---

## 4. Vercel Deployment Troubleshooting

### Issue A: `Error: No project linked`
- **Symptom:** Step `vercel pull` fails with:
  `Error: No project linked. Either use the --yes flag or run vercel link.`
- **Root Cause:** Vercel CLI in CI/CD requires `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` passed as environment variables.
- **Resolution:**
  Ensure the step definition in `.github/workflows/deploy.yml` contains:
  ```yaml
  env:
    VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
    VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
  ```

### Issue B: Expired Vercel Token
- **Symptom:** `Error: Invalid token` or `HTTP 403 Forbidden`.
- **Resolution:**
  Regenerate your personal access token in Vercel (*Account Settings > Tokens*) and update the `VERCEL_TOKEN` secret in GitHub.

---

## 5. Web Server 500 / Worker Issues (cPanel)

### Issue A: HTTP 500 Internal Server Error immediately after deploy
- **Root Cause:** Permissions misconfiguration. cPanel suPHP / LSAPI terminates execution if any directory is world-writable (`777`) or files are `666`/`777`.
- **Resolution Commands (Run via SSH):**
  ```bash
  # Fix directories
  find ~/public_html -type d -exec chmod 755 {} +
  # Fix files
  find ~/public_html -type f -exec chmod 644 {} +
  ```

### Issue B: Application code updated, but server continues serving old version
- **Root Cause:** Phusion Passenger or LiteSpeed worker pool has cached the application in memory.
- **Resolution Commands:**
  ```bash
  # Passenger / LiteSpeed worker reload
  touch ~/public_html/tmp/restart.txt
  
  # For PHP / Laravel: Clear application and OPcache
  cd ~/public_html && php artisan optimize:clear
  ```

---

## 6. Rollback Procedures

### Instant Rollback on cPanel (SSH):
If a broken release passes tests but fails in production:
1. Log in via SSH:
   ```bash
   ssh -p <PORT> <USER>@<HOST>
   ```
2. Check the releases folder:
   ```bash
   ls -la ~/$CPANEL_APP_DIR/releases/
   ```
3. Point symlink to the previous working release:
   ```bash
   ln -sfn ~/$CPANEL_APP_DIR/releases/<PREVIOUS_TIMESTAMP> ~/$CPANEL_APP_DIR/current
   touch ~/$CPANEL_APP_DIR/current/tmp/restart.txt
   ```

### Instant Rollback on Vercel:
1. Open your project in the Vercel Dashboard.
2. Navigate to the **Deployments** tab.
3. Locate the previous working deployment.
4. Click the three dots (`...`) menu and select **Instant Rollback**.
