```markdown
# Hunting API Keys in JavaScript Files: Practical Methodology

## 1. Objective

Build a repeatable workflow to find exposed API keys and other secrets inside JavaScript files for bug bounty and penetration testing.
---

## 2. High-Level Flow

1. Enumerate subdomains and web assets.
2. Collect all possible JavaScript URLs (including historical ones).
3. Filter only live JS endpoints.
4. Download JS and source maps locally.
5. Search for secrets (manual + automated).
6. Classify and validate keys.
7. Report via responsible disclosure.

---

## 3. Recon: Subdomains and JS Discovery

### 3.1 Subdomain Enumeration

Use your preferred recon stack to expand the attack surface:

- `amass enum -d target.com -o subs.txt`
- `subfinder -d target.com -o subs_subfinder.txt`
- `assetfinder target.com | tee subs_assetfinder.txt`

Merge and deduplicate:

```
cat subs*.txt | sort -u > all_subs.txt
```

These subdomains become the base for URL and JS hunting.

### 3.2 Collecting JavaScript URLs with gau

Use `gau` (GetAllUrls) to pull URLs (including from Wayback and Common Crawl):

```
gau target.com | grep -i "\.js" | sort -u > js_urls.txt
```

Repeat for important subdomains if needed:

```
while read sub; do
  gau "$sub" | grep -i "\.js" >> js_urls_raw.txt
done < all_subs.txt

sort -u js_urls_raw.txt > js_urls.txt
```

This often reveals old, forgotten JS files that still contain secrets.

---

## 4. Filter Live JS and Download Locally

### 4.1 Filter with httpx

Only keep JS endpoints that respond with HTTP 200:

```
cat js_urls.txt | httpx -silent -mc 200 -threads 50 -o js_alive.txt
```

Adjust status codes if needed (e.g., `-mc 200,302`).

### 4.2 Download with wget

Create a workspace and download all live JS:

```
mkdir -p downloaded_js

wget --wait=0.5 --random-wait \
     -i js_alive.txt \
     -P downloaded_js
```

Now you have all JS files locally for fast searching and offline analysis.
---

## 5. Manual Analysis in Browser

### 5.1 DevTools: Sources Tab

Steps:

1. Open target in browser.
2. Launch DevTools (F12 / Ctrl+Shift+I).
3. Go to **Sources** tab.
4. Browse each JS file and use search (Ctrl+F / global search) for:
   - `apiKey`, `apikey`, `api_key`
   - `secret`, `client_secret`
   - `token`, `auth`, `authorization`, `Bearer`
   - Vendor patterns like `AKIA` (AWS), `AIza` (Firebase), `sk_live_` / `pk_live_` (Stripe), `ghp_` (GitHub).

Look for:

- Config objects (e.g., Firebase, SDK configs).
- Hardcoded credentials or tokens.
- Endpoints pointing to internal APIs, admin panels, or staging.

### 5.2 DevTools: Network Tab & Source Maps

1. Open **Network** tab and reload the page.
2. Filter for:
   - `*.js`
   - `config`, `auth`, `token` in request paths.
3. Inspect:
   - Responses for embedded keys or JWTs.
   - `Authorization` / `x-api-key` headers in requests.
Check for source maps:

- At bottom of minified bundles, look for:
  - `//# sourceMappingURL=app.js.map`
- Open that `.map` file directly; it can expose readable source with comments and clearer variable names, often leaking more context and secrets.

---

## 6. Automated Grep/Ripgrep Secret Scans

From your `downloaded_js` directory, use `ripgrep` (rg) or `grep` with tailored patterns.

### 6.1 Generic Secret Search

```
rg -n -i 'apiKey|apikey|api_key|secret|token|auth|x-api-key|Bearer|client_secret' downloaded_js/
```

This quickly surfaces likely locations of secrets, auth headers, and tokens.

### 6.2 Vendor-Specific Patterns

Examples (extend as needed):

- **AWS Access Key ID**:

  ```
  rg -n 'AKIA[0-9A-Z]{16}' downloaded_js/
  ```

- **AWS Secret Key (approximate)**:

  ```
  rg -n '(?i)aws(.{0,20})?["\'][0-9a-zA-Z/+]{40}["\']' downloaded_js/
  ```

- **JWT tokens**:

  ```
  rg -n '[A-Za-z0-9-_]{20,}\.[A-Za-z0-9-_]{10,}\.[A-Za-z0-9-_]{10,}' downloaded_js/
  ```

- **Stripe**:

  ```
  rg -n 'sk_live_[0-9a-zA-Z]{16,}|pk_live_[0-9a-zA-Z]{16,}' downloaded_js/
  ```

- **Generic `api_key` / `client_secret`**:

  ```
  rg -n 'api_key[="\']?[A-Za-z0-9_\-]{8,}|client_secret[="\']?[A-Za-z0-9_\-]{8,}' downloaded_js/
  ```

You can also reuse or adapt public regex collections for API keys to increase coverage.
---

## 7. Classifying and Assessing Impact

Once potential secrets are found, classify them:

- **AWS Keys**: May allow S3 access, IAM actions, or resource management depending on permissions.
- **Stripe Keys**:
  - `pk_live_...` → publishable, low risk by itself.
  - `sk_live_...` → secret; high risk (charges, refunds, etc.).
- **Firebase Config**:
  - Public API key alone is not always critical, but misconfigured rules can expose DB read/write, storage, or authentication bypass.
- **GitHub tokens (`ghp_...`)**: Can allow repo read/write, access to private code, or internal docs depending on scopes.
- **Custom / Internal keys**: Look at context (used in `Authorization` headers, access to `/api/*`, or admin endpoints) to determine sensitivity.

Impact evaluation:

- Map what the key can access (e.g., specific API, environment).
- Check if you can:
  - Read sensitive data.
  - Write/modify data.
  - Perform admin actions.
  - Trigger financial consequences (billing, resource creation)
Follow program rules and avoid destructive or out-of-scope actions.

---

## 8. Optional: GitHub & Dorking for Extra Keys

Beyond JS on the main site, use GitHub and search engines to find more leaks:

- GitHub search syntax for `apiKey`, `client_secret`, `token`, etc.
- Custom dorks combining `site:github.com` + target’s org/repo names and secret-related keywords.
This often surfaces keys in:

- Old front-end repos.
- Internal tooling.
- Demo or PoC projects accidentally pushed public.
---

## 9. Reporting and Responsible Disclosure

When you confirm a valid secret:

1. Capture evidence:
   - Where the key is found (URL, JS file, line number).
   - What you can do with it (read-only vs write or admin).
2. Minimize usage:
   - Only enough to prove impact, strictly within scope.
3. Prepare a clean report:
   - Summary, impact, clear reproduction steps, affected assets.
4. Submit via:
   - Bug bounty platform (HackerOne, Bugcrowd, Intigriti, etc.).
   - Vendor’s security.txt or disclosure email if no program exists.[web:4][web:9]

Avoid posting keys publicly or sharing them outside the program.

---

## 10. Personal Workflow Notes

- Combine **automated scans** (rg + regex packs) with **manual JS reading** for the best results, especially on critical targets.
- Save this methodology as `js_api_key_hunting.md` in your notes repo and adapt commands per engagement (e.g., different wordlists or regexes).
- Over time, maintain your own curated regex list, tooling wrappers, and script automation around this workflow.
```

[1](https://www.linkedin.com/posts/insha-j-38b822225_hunting-api-keys-in-javascript-files-a-bug-activity-7372637308849655808-I9dj)
[2](https://www.youtube.com/watch?v=x0oFj6vPUhU)
[3](https://infosecwriteups.com/how-i-found-100-api-keys-in-javascript-files-js-secrets-exposed-939cc1f22289)
[4](https://x.com/medusa_0xf/status/1967073500935713085)
[5](https://blog.stackademic.com/hunting-javascript-file-for-bug-hunters-e8b278a1306a)
[6](https://github.com/blackhatethicalhacking/Bug_Bounty_Tools_and_Methodology)
[7](https://benjitrapp.github.io/memories/2023-07-23-github-search-syntax/)
[8](https://systemweakness.com/advanced-techniques-for-identifying-leaked-api-keys-in-js-files-bb67845e5c0e)
[9](https://www.youtube.com/watch?v=zV6Uh9swTe4)
[10](https://github.com/System00-Security/API-Key-regex)
