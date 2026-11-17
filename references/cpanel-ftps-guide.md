# cPanel FTPS Continuous Deployment Guide

This reference guide provides instructions for deploying static frontends (React, Vue, Vite, Astro, Svelte, HTML5) to cPanel shared hosting using FTPS (FTP over Explicit TLS) when SSH terminal access is disabled or restricted.

---

## 1. When to Use FTPS vs SSH

| Factor | FTPS (FTP over TLS) | SSH / SFTP |
| :--- | :--- | :--- |
| **Hosting Compatibility** | Works on 100% of cPanel shared hosts. | Requires SSH terminal access enabled by host. |
| **Supported Applications** | Static frontends and pre-compiled client assets. | Static frontends AND backend APIs (Node, Python, PHP). |
| **Build & Execution** | All builds must occur in GitHub Actions runner. | Can run remote server tasks (`composer`, `artisan`, etc.). |
| **Speed** | File-by-file upload or differential hash sync. | Single `.zip` archive upload and instant server-side unzip. |
| **Process Control** | Cannot restart background processes or workers. | Can recycle workers via `tmp/restart.txt`. |

---

## 2. cPanel FTP Account Setup & The Directory Trap

To allow GitHub Actions to upload files safely to your hosting account:

### Step 1: Open FTP Accounts in cPanel
1. Log in to your cPanel dashboard.
2. Under the **Files** section, click **FTP Accounts**.

### Step 2: Create a Dedicated FTP Account
Fill in the form:
- **Log in:** e.g., `github-deployer`
- **Domain:** Select your target domain from the dropdown.
- **Password:** Generate a strong password and save it securely.

> [!CAUTION]
> ### THE CPANEL DIRECTORY TRAP:
> By default, cPanel automatically pre-fills the **Directory** field as:
> `public_html/github-deployer`
> 
> **You MUST delete the pre-filled username suffix.**
> - For your primary production domain, change it to: `public_html`
> - For a staging subdomain, change it to: `staging.yourdomain.com` or `public_html/staging`
> 
> If you leave the default subfolder, your pipeline will upload files to a nested subfolder (`public_html/github-deployer/`) and your live website will remain blank or return a 404!

### Step 3: Quota
- Set **Quota** to **Unlimited**.
- Click **Create FTP Account**.

---

## 3. GitHub Actions FTPS Configuration

We utilize the battle-tested `SamKirkland/FTP-Deploy-Action@v4.3.5`.

### Key Action Parameters:
```yaml
- name: Sync files via FTPS
  uses: SamKirkland/FTP-Deploy-Action@v4.3.5
  with:
    server: ${{ secrets.CPANEL_FTP_SERVER }}
    username: ${{ secrets.CPANEL_FTP_USERNAME }}
    password: ${{ secrets.CPANEL_FTP_PASSWORD }}
    protocol: ftps
    port: 21
    local-dir: ./dist/
    server-dir: /
    dangerous-clean-slate: false
    exclude: |
      **/.git*
      **/.git*/**
      **/node_modules/**
```

### Explanation of Critical Flags:
1. `protocol: ftps`: Enforces explicit TLS encryption on port 21. Passwords and source files are never transmitted in plaintext.
2. `server-dir: /`: Because cPanel FTP accounts are chrooted to the directory assigned in Step 2, `/` maps directly to your website root (`public_html`).
3. `dangerous-clean-slate: false`: Prevents the action from deleting unmanaged server-side files (such as cPanel's `.well-known/` SSL certificate renewal directory or custom server configuration).

---

## 4. Single Page Application (SPA) Routing & `.htaccess`

Static client-side SPAs (React Router, Vue Router) rely on client-side history API routing.
When a user visits `https://yourdomain.com/dashboard` directly or reloads the browser, the web server looks for a physical directory named `/dashboard`. Because it doesn't exist, the server throws a 404 Not Found error.

### Automated `.htaccess` Injection:
The GitHub Actions workflow must inject a production `.htaccess` file into the build output folder (`dist/`) before FTPS upload:

```bash
cat << 'EOF' > dist/.htaccess
Options -Indexes
RewriteEngine On
RewriteBase /
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
RewriteRule ^ index.html [L]
EOF
```

---

## 5. Troubleshooting FTPS Failures

### 1. `ETIMEDOUT` or `Connection timed out` on port 21
- **Root Cause:** The hosting provider's firewall (ConfigServer Security & Firewall / CSF) or cPHulk has temporarily blocked the GitHub runner IP range or passive mode data ports (ports 49152–65534).
- **Fix:** Contact hosting support to ensure passive FTP port ranges are open, or switch to the SSH deployment method if available.

### 2. Deployment succeeds but changes do not appear
- **Root Cause:** Directory trap was triggered. The FTP account was chrooted to `public_html/username/` instead of `public_html/`.
- **Fix:** Delete and recreate the FTP account with directory set directly to `public_html`.
