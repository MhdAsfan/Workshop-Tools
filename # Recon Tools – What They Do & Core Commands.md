``markdown
# Recon Tools – What They Do & Core Commands

## 1. BBOT

**What it does**

- Passive and active recon framework.
- Combines subdomain enumeration, DNS, port scan, HTTP checks in one run.

**Core command**

```
bbot -t example.com --modules subdomain-enum,dns,portscan,http
```

---

## 2. Katana

**What it does**

- Fast web crawler aware of JavaScript.
- Finds hidden paths, endpoints, and parameters.

**Core commands**

```
# Basic crawl
katana -u https://example.com -jc -o katana_output.txt

# Stealthier, deeper crawl through proxy with JS heuristics
katana -u https://example.com -jc -d 5 -f qurl -c 10 \
  -proxy http://127.0.0.1:8080 -em "logout,reset-password"

# Authenticated + direct pipe into nuclei
katana -u https://example.com -silent \
  | nuclei -t ~/nuclei-templates/ -rate-limit 100
```

---

## 3. httpx

**What it does**

- Probes domains/hosts to see which are alive.
- Collects status codes, titles, and tech fingerprints.

**Core commands**

```
# Basic live host + tech/title detection
cat domains.txt | httpx -status-code -tech-detect -title -o live_hosts.txt

# Multi-field JSON output with richer fingerprinting
cat domains.txt | httpx -sc -td -title -favicon -jarm -tls-grab \
  -match-string "admin" -match-code 200 -o live_hosts.json
```

---

## 4. GoWitness

**What it does**

- Takes screenshots of web targets.
- Helps visually triage panels and dashboards.

**Core commands**

```
# Simple screenshot run
gowitness file -f live_hosts.txt -P screenshots/

# Screenshot with DB + headless Chrome options
gowitness file -f live_hosts.txt -P screenshots/ \
  --chrome-options "--headless --disable-gpu" \
  --db gowitness.sqlite3
```

---

## 5. JSFinder (workflow)

**What it does**

- Finds JavaScript file URLs for a target.
- Helps locate endpoints, parameters, and possible secrets.

**Core commands**

```
# Discover JS URLs
jsfinder -u https://example.com -o js_urls.txt

# Fetch JS and grep for secrets
cat js_urls.txt | xargs -n1 curl -s | grep -Ei "apikey|token|secret"

# Enrich JS URLs with further URL extraction
cat js_urls.txt | waymore -i - -o js_waymore.txt

# Extract endpoints from a JS file (LinkFinder)
python3 linkfinder.py -i https://example.com/static.js -o cli

# Extract secrets (SecretFinder)
python3 secretfinder.py -i js_waymore.txt -o secrets.json
```

---

## 6. Subzy

**What it does**

- Checks for subdomain takeover possibilities.
- Detects dangling DNS records and misconfigured third-party services.

**Core commands**

```
# Simple takeover check
subzy run --targets live_hosts.txt

# Continuous-style, verified scan with output
subzy run --targets live_hosts.txt --verify --https \
  --concurrency 50 --output takeovers.json
```

---

## 7. dnsx

**What it does**

- Fast DNS resolver and analyzer.
- Retrieves multiple record types and detects wildcards/misconfigs.

**Core commands**

```
# Basic DNS resolution with response
cat subdomains.txt | dnsx -a -resp -o resolved.txt

# Multi-record DNS analysis in JSON
dnsx -l subdomains.txt -a -aaaa -cname -mx -ptr -soa \
  -wd "*" -r 8.8.8.8 -resp -json -o dns_analysis.json

# With bruteforcing (via puredns → dnsx)
puredns bruteforce all.txt example.com -r resolvers.txt \
  | dnsx -silent
```

---

## 8. nuclei

**What it does**

- Template-based vulnerability scanner.
- Detects CVEs, misconfigurations, exposures, and more.

**Core commands**

```
# Scan live hosts against CVE templates
nuclei -l live_hosts.txt -t cves/ -o nuclei_output.txt

# Update templates
nuclei -update-templates

# Higher-intensity, filtered scan
nuclei -l live_hosts.txt -tags cve,misconfig -etags noisy \
  -stats -si 100 -rl 150 -me critical_findings \
  -headless -proxy-url http://tor:9150
```

---

## 9. gau + waybackurls

**What they do**

- `gau`: collects URLs from multiple sources (CommonCrawl, Wayback, etc.).
- `waybackurls`: pulls URLs from the Wayback Machine.

**Core commands**

```
# Simple URL collection
gau example.com >> urls.txt
waybackurls example.com >> urls.txt

# Time-scoped URL harvesting with filtering
gau example.com --threads 20 --blacklist png,jpg,css \
  --from 20220101 --to 20231231 | uro > urls.txt
```

---

## 10. GF (gf-patterns)

**What it does**

- Filters URL lists for interesting/vulnerable patterns.
- Helps create shortlists for targeted testing (XSS, SSTI, SSRF, etc.).

**Core commands**

```
# Find XSS candidates
cat urls.txt | gf xss > xss_candidates.txt

# SSTI quick confirm pipeline
cat urls.txt | gf ssti | qsreplace "{{7*7}}" \
  | httpx -match-string "49" -ms "SSTI Confirmed"
