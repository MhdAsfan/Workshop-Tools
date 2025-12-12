
```bash
#!/usr/bin/env bash
set -euo pipefail

################################
# Config / defaults
################################
DOMAIN="${1:-}"

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 target.com"
  exit 1
fi

OUTDIR="recon_$DOMAIN"
mkdir -p "$OUTDIR"

LOGFILE="$OUTDIR/recon.log"

ALL_SUBS="$OUTDIR/all_subdomains.txt"
ALIVE_OUT="$OUTDIR/alive_with_status.txt"

# Wordlists
SUB_WORDLIST="${SUB_WORDLIST:-wordlists/subdomains.txt}"
PERM_WORDLIST="${PERM_WORDLIST:-wordlists/permutations.txt}"
HIDDEN_PERM_WORDLIST="${HIDDEN_PERM_WORDLIST:-wordlists/hidden_permutations.txt}"  # more aggressive

# Threads
DNSX_THREADS="${DNSX_THREADS:-100}"
HTTPX_THREADS="${HTTPX_THREADS:-100}"

################################
# Helpers
################################
log() {
  echo "[$(date +'%F %T')] $*" | tee -a "$LOGFILE"
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "[!] Required command '$1' not found in PATH"
    exit 1
  fi
}

safe_run() {
  local name="$1"; shift
  log "[+] Running module: $name"
  if ! "$@" 2>>"$LOGFILE"; then
    log "[!] Module failed (continuing): $name"
  fi
}

################################
# Tool list (for display)
################################
TOOLS=(
  "amass      – passive/active subdomain enumeration"
  "subfinder  – passive multi-source subdomain enumeration"
  "dnsx       – DNS brute-force and resolution"
  "dnsgen     – subdomain permutations/mutations (normal + hidden)"
  "httpx      – HTTP probing (status code, title, tech)"
  "ffuf       – optional vhost fuzzing for hidden virtual hosts"
  "customOSINT – placeholder for GitHub/Medium/LinkedIn/search collectors"
)

echo "========== OneClick Recon =========="
echo "Target domain : $DOMAIN"
echo "Output folder : $OUTDIR"
echo
echo "Modules / tools used:"
for t in "${TOOLS[@]}"; do
  echo "  - $t"
done
echo
echo "Wordlists:"
echo "  - Subdomains wordlist        : $SUB_WORDLIST"
echo "  - Permutations wordlist      : $PERM_WORDLIST"
echo "  - Hidden permutations wordlist: $HIDDEN_PERM_WORDLIST"
echo
echo "Threading:"
echo "  - dnsx threads  : $DNSX_THREADS"
echo "  - httpx threads : $HTTPX_THREADS"
echo "===================================="
echo

################################
# Pre-flight: check core tools
################################
for bin in amass subfinder dnsx dnsgen httpx; do
  need_cmd "$bin"
done
# ffuf is optional; only warn if missing
if ! command -v ffuf >/dev/null 2>&1; then
  log "[!] ffuf not found; Host-header vhost fuzzing will be skipped"
fi

log "[+] Starting OneClick Recon for: $DOMAIN"

################################
# 1) Subdomain enumeration module
################################
enum_module() {
  local d="$1"

  amass enum -passive -d "$d" -o "$OUTDIR/amass_passive.txt" || true
  amass enum -active  -d "$d" -o "$OUTDIR/amass_active.txt"  || true

  subfinder -all -d "$d" -o "$OUTDIR/subfinder.txt" || true

  if [ -f "$SUB_WORDLIST" ]; then
    dnsx -d "$d" -w "$SUB_WORDLIST" -t "$DNSX_THREADS" -o "$OUTDIR/dnsx_bruteforce.txt" || true
  else
    log "[!] No sub wordlist at $SUB_WORDLIST, skipping brute-force"
    : > "$OUTDIR/dnsx_bruteforce.txt"
  fi

  cat "$OUTDIR"/amass_*.txt "$OUTDIR"/subfinder.txt "$OUTDIR"/dnsx_bruteforce.txt 2>/dev/null \
    | grep -v '^$' | sort -u > "$OUTDIR/seed_subs.txt"

  local seed_count
  seed_count=$(wc -l < "$OUTDIR/seed_subs.txt" || echo 0)
  log "[+] Seed subdomains: $seed_count"

  cp "$OUTDIR/seed_subs.txt" "$ALL_SUBS"
}

safe_run "Subdomain enumeration" enum_module "$DOMAIN"

################################
# 2) Normal permutation module
################################
perm_module() {
  if [ ! -f "$PERM_WORDLIST" ]; then
    log "[!] No perm wordlist at $PERM_WORDLIST, skipping permutations"
    return 0
  fi

  dnsgen "$OUTDIR/seed_subs.txt" -w "$PERM_WORDLIST" > "$OUTDIR/perms_raw.txt" || true
  dnsx -l "$OUTDIR/perms_raw.txt" -t "$DNSX_THREADS" -o "$OUTDIR/perms_resolved.txt" || true

  cat "$OUTDIR/perms_resolved.txt" >> "$ALL_SUBS"
  sort -u "$ALL_SUBS" -o "$ALL_SUBS"
}

safe_run "Permutations" perm_module

################################
# 3) Hidden subdomains module
################################
hidden_module() {
  # 3.1 Aggressive permutations with a hidden wordlist
  if [ -f "$HIDDEN_PERM_WORDLIST" ]; then
    log "[+] Hidden permutations with dnsgen..."
    dnsgen "$ALL_SUBS" -w "$HIDDEN_PERM_WORDLIST" > "$OUTDIR/hidden_perms_raw.txt" || true

    log "[+] Resolving hidden permutations with dnsx..."
    dnsx -l "$OUTDIR/hidden_perms_raw.txt" -t "$DNSX_THREADS" -o "$OUTDIR/hidden_perms_resolved.txt" || true

    cat "$OUTDIR/hidden_perms_resolved.txt" >> "$ALL_SUBS"
    sort -u "$ALL_SUBS" -o "$ALL_SUBS"
  else
    log "[!] No hidden perm wordlist at $HIDDEN_PERM_WORDLIST, skipping hidden permutations"
  fi

  # 3.2 Optional vhost fuzzing (virtual hosts on same IP)
  if command -v ffuf >/dev/null 2>&1; then
    # Take a few alive hosts later for vhost fuzzing after httpx, so only prepare here.
    log "[+] Hidden vhosts: will use ffuf after first httpx run on top IPs (if any)"
  fi
}

safe_run "Hidden subdomains" hidden_module

TOTAL_SUBS=$(wc -l < "$ALL_SUBS" || echo 0)
log "[+] Total unique subdomains (after hidden module): $TOTAL_SUBS"

################################
# 4) HTTP probe module (first pass)
################################
probe_module() {
  httpx -silent -l "$ALL_SUBS" \
    -status-code -title -follow-redirects -threads "$HTTPX_THREADS" \
    -o "$ALIVE_OUT"
}

safe_run "HTTP probing (pass 1)" probe_module

ALIVE_COUNT=$(wc -l < "$ALIVE_OUT" || echo 0)
log "[+] Alive hosts after pass 1: $ALIVE_COUNT"

################################
# 5) Optional vhost fuzzing for hidden virtual hosts
################################
vhost_module() {
  if ! command -v ffuf >/dev/null 2>&1; then
    log "[!] Skipping vhost fuzzing (ffuf not installed)"
    return 0
  fi

  # Extract top few IPs from alive hosts (simple example, tune as needed)
  cut -d' ' -f1 "$ALIVE_OUT" | sed 's#https\?://##' | cut -d'/' -f1 | sort -u > "$OUTDIR/alive_hosts_only.txt"

  # Resolve hosts to IPs
  : > "$OUTDIR/ip_list.txt"
  while read -r h; do
    ip=$(dig +short "$h" | head -n1 || true)
    [ -n "$ip" ] && echo "$ip" >> "$OUTDIR/ip_list.txt"
  done < "$OUTDIR/alive_hosts_only.txt"
  sort -u "$OUTDIR/ip_list.txt" -o "$OUTDIR/ip_list.txt"

  if [ ! -s "$OUTDIR/ip_list.txt" ]; then
    log "[!] No IPs resolved from alive hosts; skipping vhost fuzzing"
    return 0
  fi

  if [ ! -f "$SUB_WORDLIST" ]; then
    log "[!] No sub wordlist for vhost fuzzing; skipping"
    return 0
  fi

  log "[+] Starting vhost fuzzing (hidden virtual hosts)..."
  VHOST_OUT="$OUTDIR/hidden_vhosts.txt"
  : > "$VHOST_OUT"

  while read -r ip; do
    ffuf -u "http://$ip" -H "Host: FUZZ.$DOMAIN" -w "$SUB_WORDLIST" -mc 200,301,302,403 -t 50 \
      -of csv -o "$OUTDIR/ffuf_vhost_$ip.csv" 2>>"$LOGFILE" || true

    # Extract hosts from ffuf output
    tail -n +2 "$OUTDIR/ffuf_vhost_$ip.csv" | cut -d',' -f1 | sed "s#^#http://#g" >> "$VHOST_OUT" || true
  done < "$OUTDIR/ip_list.txt"

  if [ -s "$VHOST_OUT" ]; then
    log "[+] Hidden vhosts discovered, adding to ALL_SUBS and re-probing..."
    sed 's#https\?://##' "$VHOST_OUT" | cut -d'/' -f1 >> "$ALL_SUBS"
    sort -u "$ALL_SUBS" -o "$ALL_SUBS"

    httpx -silent -l "$ALL_SUBS" \
      -status-code -title -follow-redirects -threads "$HTTPX_THREADS" \
      -o "$ALIVE_OUT" 2>>"$LOGFILE"

  else
    log "[!] No hidden vhosts discovered via ffuf"
  fi
}

safe_run "Hidden vhosts (ffuf)" vhost_module

ALIVE_COUNT=$(wc -l < "$ALIVE_OUT" || echo 0)
log "[+] Final alive hosts: $ALIVE_COUNT"

################################
# 6) OSINT/code intel module (placeholder)
################################
osint_module() {
  log "[!] OSINT module not yet implemented (GitHub/Medium/LinkedIn/search)."
}

safe_run "OSINT / code intel" osint_module

################################
# Final summary
################################
log "[+] Recon complete for $DOMAIN"
log "[+] All subdomains file           : $ALL_SUBS"
log "[+] Alive hosts + status code file: $ALIVE_OUT"
log "[+] Total unique subdomains       : $TOTAL_SUBS"
log "[+] Final alive hosts             : $ALIVE_COUNT"

echo
echo "============ Summary ============"
echo "All subdomains           : $ALL_SUBS"
echo "Alive + status codes     : $ALIVE_OUT"
echo "Log file                 : $LOGFILE"
echo "Total unique subdomains  : $TOTAL_SUBS"
echo "Total alive hosts        : $ALIVE_COUNT"
echo "================================="
```
