#!/usr/bin/env bash

TARGET="$1"
OUT="results/$TARGET"
WORDLIST_DIR="/usr/share/wordlists"

mkdir -p "$OUT"

log() { echo "[$(date +'%H:%M:%S')] $*"; }

####################################### 
# 1. Subdomain enum
#######################################
log "[*] Subdomain enumeration for $TARGET"
sublist3r -d "$TARGET" -o "$OUT/sublist3r.txt"
amass enum -d "$TARGET" -o "$OUT/amass.txt"

cat "$OUT"/sublist3r.txt "$OUT"/amass.txt | sort -u > "$OUT/subdomains_all.txt"

#######################################
# 2. Live hosts & port scan
#######################################
log "[*] Probing HTTP/S on subdomains"
cat "$OUT/subdomains_all.txt" | httprobe > "$OUT/live_hosts.txt"

log "[*] Nmap scanning live hosts"
nmap -sC -sV -iL "$OUT/live_hosts.txt" -oA "$OUT/nmap"

#######################################
# 3. Tech fingerprinting
#######################################
log "[*] Tech fingerprinting with WhatWeb + Wappalyzer"
while read -r URL; do
  whatweb -v "$URL" | tee -a "$OUT/whatweb.txt"
  wappalyzer "$URL" 2>/dev/null | tee -a "$OUT/wappalyzer.json"
done < "$OUT/live_hosts.txt"

#######################################
# 4. Directory fuzzing
#######################################
log "[*] Directory fuzzing with ffuf + gobuster + dirsearch"
while read -r URL; do
  HOST=$(echo "$URL" | sed 's#https\?://##g' | cut -d/ -f1)

  ffuf -u "$URL/FUZZ" \
       -w "$WORDLIST_DIR/dirbuster/directory-list-2.3-medium.txt" \
       -of json -o "$OUT/ffuf_$HOST.json"

  gobuster dir -u "$URL" \
    -w "$WORDLIST_DIR/dirbuster/directory-list-2.3-medium.txt" \
    -o "$OUT/gobuster_$HOST.txt"

  python3 dirsearch.py -u "$URL" -e php,html,js \
    -o "$OUT/dirsearch_$HOST.txt"
done < "$OUT/live_hosts.txt"

#######################################
# 5. Quick vuln scanners (Nikto + nuclei)
#######################################
log "[*] Running Nikto and nuclei"
while read -r URL; do
  HOST=$(echo "$URL" | sed 's#https\?://##g' | cut -d/ -f1)

  nikto -host "$URL" -output "$OUT/nikto_$HOST.txt"

  nuclei -u "$URL" -t cves/ \
    -json -o "$OUT/nuclei_$HOST.json"
done < "$OUT/live_hosts.txt"

#######################################
# 6. XSS + SQLi helpers (XSStrike + sqlmap)
#######################################
log "[*] XSS and SQLi helpers (requires manual target URLs)"

# example usage file you fill from Burp/notes:
# each line: full URL with parameter
if [ -f "$OUT/params_sqli.txt" ]; then
  while read -r PURL; do
    sqlmap -u "$PURL" --risk=3 --level=5 --batch \
      --output-dir="$OUT/sqlmap"
  done < "$OUT/params_sqli.txt"
fi

if [ -f "$OUT/params_xss.txt" ]; then
  while read -r XURL; do
    python3 xsstrike.py -u "$XURL" \
      --crawl --crawl-depth 1 \
      | tee -a "$OUT/xsstrike.txt"
  done < "$OUT/params_xss.txt"
fi

#######################################
# 7. Advanced / optional (network & creds)
#######################################
log "[*] Optional: network tools (Hydra, CME, Metasploit) – manual targets"

# placeholders – you fill targets later:
# hydra -L users.txt -P passwords.txt ssh://1.2.3.4
# cme smb 10.0.0.0/24 -u users.txt -p passwords.txt
# msfconsole (manual use)

#######################################
# 8. Summary
#######################################
log "[*] Recon finished for $TARGET"
log "  Subdomains:    $OUT/subdomains_all.txt"
log "  Live hosts:    $OUT/live_hosts.txt"
log "  Nmap:          $OUT/nmap.*"
log "  Web dirs:      $OUT/ffuf_*, gobuster_*, dirsearch_*"
log "  Vulns:         $OUT/nikto_*, nuclei_*"
log "  SQLi results:  $OUT/sqlmap/"
log "  XSS results:   $OUT/xsstrike.txt"
