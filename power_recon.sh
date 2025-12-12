#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-}"

if [ -z "$DOMAIN" ]; then
  echo "Usage: $0 target.com"
  exit 1
fi

OUTDIR="recon_$DOMAIN"
mkdir -p "$OUTDIR"

ALL_SUBS="$OUTDIR/all_subdomains.txt"
ALIVE_OUT="$OUTDIR/alive_with_status.txt"

SUB_WORDLIST="wordlists/subdomains.txt"      # edit path
PERM_WORDLIST="wordlists/permutations.txt"   # edit path

echo "[+] Domain       : $DOMAIN"
echo "[+] Output dir   : $OUTDIR"
echo "[+] Sub wordlist : $SUB_WORDLIST"
echo "[+] Perm wordlist: $PERM_WORDLIST"
echo

#####################################
# 1) Passive + active enum (Amass & Subfinder)
#####################################
echo "[+] Amass passive..."
amass enum -passive -d "$DOMAIN" -o "$OUTDIR/amass_passive.txt" || true

echo "[+] Amass active (if resolvers & configs set)..."
amass enum -active -d "$DOMAIN" -o "$OUTDIR/amass_active.txt" || true

echo "[+] Subfinder (all sources)..."
subfinder -all -d "$DOMAIN" -o "$OUTDIR/subfinder.txt" || true

#####################################
# 2) Brute-force DNS with dnsx (optional)
#####################################
if [ -f "$SUB_WORDLIST" ]; then
  echo "[+] dnsx brute-force with wordlist..."
  dnsx -d "$DOMAIN" -w "$SUB_WORDLIST" -o "$OUTDIR/dnsx_bruteforce.txt" || true
else
  echo "[!] Skipping dnsx brute-force (no sub wordlist found at $SUB_WORDLIST)"
fi

#####################################
# 3) Merge & dedupe initial subdomains
#####################################
echo "[+] Merging and deduping initial subdomains..."
cat "$OUTDIR"/amass_*.txt "$OUTDIR"/subfinder.txt "$OUTDIR"/dnsx_bruteforce.txt 2>/dev/null | \
  grep -v '^$' | sort -u > "$OUTDIR/seed_subs.txt"

SEED_COUNT=$(wc -l < "$OUTDIR/seed_subs.txt" || echo 0)
echo "[+] Seed subdomains: $SEED_COUNT"

cp "$OUTDIR/seed_subs.txt" "$ALL_SUBS"

#####################################
# 4) Permutations with dnsgen (optional)
#####################################
if [ -f "$PERM_WORDLIST" ]; then
  echo "[+] Generating permutations with dnsgen..."
  dnsgen "$OUTDIR/seed_subs.txt" -w "$PERM_WORDLIST" > "$OUTDIR/perms_raw.txt" || true

  echo "[+] Resolving permutations with dnsx..."
  dnsx -l "$OUTDIR/perms_raw.txt" -o "$OUTDIR/perms_resolved.txt" || true

  echo "[+] Adding resolved permutations to all_subdomains..."
  cat "$OUTDIR/perms_resolved.txt" >> "$ALL_SUBS"
  sort -u "$ALL_SUBS" -o "$ALL_SUBS"
else
  echo "[!] Skipping permutations (no perm wordlist found at $PERM_WORDLIST)"
fi

TOTAL_SUBS=$(wc -l < "$ALL_SUBS" || echo 0)
echo "[+] Total unique subdomains (after perms): $TOTAL_SUBS"

#####################################
# 5) HTTP probing with httpx (final status codes)
#####################################
echo "[+] Probing with httpx (status-code, title, follows redirects)..."
httpx -silent -l "$ALL_SUBS" \
  -status-code -title -follow-redirects \
  -o "$ALIVE_OUT"

ALIVE_COUNT=$(wc -l < "$ALIVE_OUT" || echo 0)

echo
echo "[+] Recon complete for $DOMAIN"
echo "[+] All subdomains           : $ALL_SUBS"
echo "[+] Alive hosts + status code: $ALIVE_OUT"
echo "[+] Alive count              : $ALIVE_COUNT"
