#!/usr/bin/env python3
import subprocess
import argparse
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed

def run_subfinder(domain):
    cmd = f"subfinder -silent -d {domain}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    subs = [l.strip() for l in result.stdout.splitlines() if l.strip()]
    return subs

def check_host(host):
    urls = [f"http://{host}", f"https://{host}"]
    for url in urls:
        try:
            r = requests.get(url, timeout=5, allow_redirects=True)
            return host, r.status_code
        except Exception:
            continue
    return host, None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-d", "--domain", required=True, help="Target domain")
    parser.add_argument("-t", "--threads", type=int, default=50, help="Concurrency")
    args = parser.parse_args()

    print(f"[+] Enumerating subdomains for {args.domain}...")
    subs = run_subfinder(args.domain)
    print(f"[+] Found {len(subs)} subdomains. Checking status codes...")

    live = []
    with ThreadPoolExecutor(max_workers=args.threads) as executor:
        futures = {executor.submit(check_host, s): s for s in subs}
        for fut in as_completed(futures):
            host, code = fut.result()
            if code is not None:
                live.append((host, code))
                print(f"{host} {code}")

    print(f"\n[+] Alive: {len(live)}")
    # Optional: write to file
    with open("alive_with_status.txt", "w") as f:
        for host, code in live:
            f.write(f"{host},{code}\n")

if __name__ == "__main__":
    main()
