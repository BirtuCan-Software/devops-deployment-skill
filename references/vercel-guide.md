# Vercel Frontend Deployment Guide

This reference guide provides engineering specifications for deploying modern frontend frameworks (Next.js, Vite, React, Vue, SvelteKit, Astro, Nuxt) to Vercel using GitHub Actions with production and preview environments.

---

## 1. Vercel Architecture & Deployment Model

Vercel provides automated edge-network hosting optimized for frontend web applications. In our GitHub Actions pipeline:
- **Production Deployments (`main` branch):** Deployed to production domains with edge caching and live traffic routing.
- **Preview Deployments (`staging` branch or pull requests):** Deployed to isolated preview URLs with full branch preview isolation.

---

## 2. Credential Retrieval (Click-by-Click)

To authenticate GitHub Actions with Vercel, three configuration tokens are required:

### 1. `VERCEL_TOKEN` (Personal Access Token)
1. Log in to your [Vercel Dashboard](https://vercel.com).
2. Click your profile avatar in the top right corner and select **Account Settings**.
3. In the left navigation, click **Tokens**.
4. Click **Create Token**:
   - **Name:** `github-actions-deploy`
   - **Scope:** Choose your account or team.
   - **Expiration:** Set desired expiration (e.g. 1 year or No Expiry).
5. Click **Create** and copy the secret token immediately.

### 2. `VERCEL_ORG_ID` (Organization or Account Identifier)
1. In Account Settings, click **General**.
2. Find the **Your ID** field (format: `team_...` or `usr_...`).
3. Copy this string.

### 3. `VERCEL_PROJECT_ID` (Unique Project Identifier)
1. Return to the Vercel Dashboard and open your project.
2. Click **Settings** (project settings, not account settings).
3. Under the **General** tab, scroll to **Project ID** (format: `prj_...`).
4. Copy this string.

> [!TIP]
> Alternatively, if you have the Vercel CLI installed locally, run `npx vercel link` in your repository root. Vercel will create `.vercel/project.json` containing `orgId` and `projectId`.

---

## 3. Official Vercel CLI Prebuilt Pipeline

Using the official Vercel CLI with prebuilt assets ensures maximum consistency between local builds and CI:

```yaml
- name: Install Vercel CLI
  run: npm install --global vercel@latest

- name: Pull Vercel Environment Information
  env:
    VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
    VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
  run: |
    vercel pull --yes \
      --environment=${{ github.ref_name == 'main' && 'production' || 'preview' }} \
      --token=${{ secrets.VERCEL_TOKEN }}

- name: Build Project Artifacts
  env:
    VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
    VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
  run: |
    vercel build ${{ github.ref_name == 'main' && '--prod' || '' }} \
      --token=${{ secrets.VERCEL_TOKEN }}

- name: Deploy to Vercel
  id: vercel_deploy
  env:
    VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}
    VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}
  run: |
    DEPLOY_URL=$(vercel deploy --prebuilt ${{ github.ref_name == 'main' && '--prod' || '' }} --token=${{ secrets.VERCEL_TOKEN }})
    echo "deploy_url=$DEPLOY_URL" >> "$GITHUB_OUTPUT"
    echo "### 🚀 Vercel Deployment Successful" >> "$GITHUB_STEP_SUMMARY"
    echo "Deployment URL: [$DEPLOY_URL]($DEPLOY_URL)" >> "$GITHUB_STEP_SUMMARY"
```

> [!IMPORTANT]
> **CRITICAL CI/CD CONFIGURATION:**
> You MUST set `env: VERCEL_ORG_ID: ${{ secrets.VERCEL_ORG_ID }}` and `VERCEL_PROJECT_ID: ${{ secrets.VERCEL_PROJECT_ID }}` on all `vercel` CLI steps. If these are omitted, `vercel pull` runs in interactive mode and immediately aborts with `Error: No project linked`.

---

## 4. SPA Fallback Routing (`vercel.json`)

For Vite, Create React App, Vue, or Svelte SPAs using HTML5 pushState client routing (React Router, Vue Router), page refresh on deep routes (e.g. `/profile/settings`) returns a 404 error on Vercel unless a route rewrite is defined.

Create `vercel.json` in your repository root:
```json
{
  "rewrites": [
    {
      "source": "/(.*)",
      "destination": "/index.html"
    }
  ]
}
```

---

## 5. Vercel Environment Variables

Set your runtime and build-time variables in the Vercel Dashboard under **Project Settings > Environment Variables**:
- **Production:** Applied when building commits pushed to `main`.
- **Preview:** Applied when building commits pushed to `staging` or Pull Requests.
- **Development:** For local development via `vercel dev`.

Variables required at build time (e.g., `VITE_API_URL` or `NEXT_PUBLIC_API_URL`) are automatically pulled into the build step by `vercel pull`.
