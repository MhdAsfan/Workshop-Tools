
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

ALL_SUBS="$OUTDIR/all_subdomains.txt"
ALIVE_OUT="$OUTDIR/alive_with_status.txt"
LOGFILE="$OUTDIR/recon.log"

# Wordlists (override via env if you want)
SUB_WORDLIST="${SUB_WORDLIST:-wordlists/subdomains.txt}"
PERM_WORDLIST="${PERM_WORDLIST:-wordlists/permutations.txt}"

# Concurrency (override via env if needed)
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
    echo "[!] Required command '$1' not found in PATH"
    exit 1
  fi
}

################################
# Pre‑flight
################################
for bin in amass subfinder dnsx dnsgen httpx; do
  need_cmd "$bin"
done

log "[+] Domain          : $DOMAIN"
log "[+] Output dir      : $OUTDIR"
log "[+] Sub wordlist    : $SUB_WORDLIST"
log "[+] Perm wordlist   : $PERM_WORDLIST"
log "[+] DNSX threads    : $DNSX_THREADS"
log "[+] HTTPX threads   : $HTTPX_THREADS"
echo

#####################################
# 1) Passive + active enum (Amass & Subfinder)
#####################################
log "[+] Amass passive..."
amass enum -passive -d "$DOMAIN" -o "$OUTDIR/amass_passive.txt" 2>>"$LOGFILE" || true

log "[+] Amass active..."
amass enum -active -d "$DOMAIN" -o "$OUTDIR/amass_active.txt" 2>>"$LOGFILE" || true

log "[+] Subfinder (all sources)..."
subfinder -all -d "$DOMAIN" -o "$OUTDIR/subfinder.txt" 2>>"$LOGFILE" || true

#####################################
# 2) Brute‑force DNS with dnsx (optional)
#####################################
if [ -f "$SUB_WORDLIST" ]; then
  log "[+] dnsx brute‑force with wordlist..."
  dnsx -d "$DOMAIN" -w "$SUB_WORDLIST" -t "$DNSX_THREADS" -o "$OUTDIR/dnsx_bruteforce.txt" 2>>"$LOGFILE" || true
else
  log "[!] Skipping dnsx brute‑force (no sub wordlist at $SUB_WORDLIST)"
  : > "$OUTDIR/dnsx_bruteforce.txt"
fi

#####################################
# 3) Merge & dedupe initial subdomains
#####################################
log "[+] Merging and deduping initial subdomains..."
cat "$OUTDIR"/amass_*.txt "$OUTDIR"/subfinder.txt "$OUTDIR"/dnsx_bruteforce.txt 2>/dev/null | \
  grep -v '^$' | sort -u > "$OUTDIR/seed_subs.txt"

SEED_COUNT=$(wc -l < "$OUTDIR/seed_subs.txt" || echo 0)
log "[+] Seed subdomains: $SEED_COUNT"

cp "$OUTDIR/seed_subs.txt" "$ALL_SUBS"

#####################################
# 4) Permutations with dnsgen (optional)
#####################################
if [ -f "$PERM_WORDLIST" ]; then
  log "[+] Generating permutations with dnsgen..."
  dnsgen "$OUTDIR/seed_subs.txt" -w "$PERM_WORDLIST" > "$OUTDIR/perms_raw.txt" 2>>"$LOGFILE" || true

  log "[+] Resolving permutations with dnsx..."
  dnsx -l "$OUTDIR/perms_raw.txt" -t "$DNSX_THREADS" -o "$OUTDIR/perms_resolved.txt" 2>>"$LOGFILE" || true

  log "[+] Adding resolved permutations to all_subdomains..."
  cat "$OUTDIR/perms_resolved.txt" >> "$ALL_SUBS"
  sort -u "$ALL_SUBS" -o "$ALL_SUBS"
else
  log "[!] Skipping permutations (no perm wordlist at $PERM_WORDLIST)"
fi

TOTAL_SUBS=$(wc -l < "$ALL_SUBS" || echo 0)
log "[+] Total unique subdomains (after perms): $TOTAL_SUBS"

#####################################
# 5) HTTP probing with httpx (final status codes)
#####################################
log "[+] Probing with httpx (status‑code, title, follows redirects)..."
httpx -silent -l "$ALL_SUBS" \
  -status-code -title -follow-redirects -threads "$HTTPX_THREADS" \
  -o "$ALIVE_OUT" 2>>"$LOGFILE"

ALIVE_COUNT=$(wc -l < "$ALIVE_OUT" || echo 0)

log "[+] Recon complete for $DOMAIN"
log "[+] All subdomains file           : $ALL_SUBS"
log "[+] Alive hosts + status code file: $ALIVE_OUT"
log "[+] Alive count                    : $ALIVE_COUNT"

echo "[+] Done. Check:"
echo "    $ALL_SUBS"
echo "    $ALIVE_OUT"
echo "    $LOGFILE"

