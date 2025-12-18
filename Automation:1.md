# Automation: From Zero to Hero 



# Update system & install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl wget python3 python3-pip golang-go postgresql postgresql-contrib jq dnsutils massdns

# Setup Go environment
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.bashrc
source ~/.bashrc


## Step 1: Install Core Recon Tools

# Subdomain enumeration (parallel install)
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/owasp-amass/amass/v2@master  
go install github.com/tomnomnom/assetfinder@latest
go install github.com/projectdiscovery/chaos-client@latest

# Probing, crawling, URL discovery
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/lc/gau/v2/cmd/gau@latest

# Scanning & fuzzing
go install github.com/Threezh1/JSFinder@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install github.com/ffuf/ffuf/v2@latest
go install github.com/projectdiscovery/dnsx/cmd/dnsx@latest

# Update Nuclei templates
nuclei -update-templates
 

**Configure Subfinder APIs** (free tiers):
mkdir -p ~/.config/subfinder
cat > ~/.config/subfinder/provider-config.yaml << EOF
virustotal: YOUR_VT_KEY
github: YOUR_GH_TOKEN  
securitytrails: YOUR_ST_KEY
EOF
 

## Step 2: Program Scope Management

 
# Clone hourly-updated bounty programs
git clone https://github.com/arkadiyt/bounty-targets-data.git
cd bounty-targets-data

# Extract paying HackerOne programs with wildcards
cat data/hackerone_data.json | jq -r '.[] | select(.offers_bounties==true) | .target' | grep -E '\*\.' > scopes.txt

# View first 20 targets
head -20 scopes.txt
 

## Step 3: PostgreSQL Database Setup

 
# Create bug bounty database
sudo -u postgres psql -c "CREATE DATABASE bugbounty;"
sudo -u postgres psql -c "CREATE USER hunter WITH PASSWORD 'password123';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE bugbounty TO hunter;"

# Connect & create tables
psql bugbounty -h localhost -U hunter -c "
CREATE TABLE programs (
    id SERIAL PRIMARY KEY, 
    name VARCHAR(255), 
    scope TEXT, 
    last_updated TIMESTAMP
);
CREATE TABLE subdomains (
    id SERIAL PRIMARY KEY, 
    program_id INT, 
    subdomain VARCHAR(255), 
    discovered_date TIMESTAMP
);
CREATE TABLE findings (
    id SERIAL PRIMARY KEY, 
    subdomain_id INT, 
    vuln_type VARCHAR(100), 
    severity VARCHAR(20), 
    url TEXT, 
    created_at TIMESTAMP
);"
 

## Step 4: Master Recon Script (`recon.sh`)

 
#!/bin/bash
# Save as: nano recon.sh && chmod +x recon.sh

domain=$1
output_dir="recon_${domain}_$(date +%Y%m%d_%H%M)"
mkdir -p $output_dir

echo "[*] Phase 1: Subdomain Enumeration"
subfinder -d $domain -all -silent -o $output_dir/subfinder.txt &
amass enum -passive -d $domain -o $output_dir/amass.txt &
assetfinder --subs-only $domain > $output_dir/assetfinder.txt &
chaos -d $domain -o $output_dir/chaos.txt &
wait

# Merge & deduplicate
cat $output_dir/*.txt | sort -u > $output_dir/all_subdomains.txt
echo "[+] $(wc -l < $output_dir/all_subdomains.txt) unique subdomains"

echo "[*] Phase 2: Resolve & HTTP Probe"
cat $output_dir/all_subdomains.txt | dnsx -silent -o $output_dir/resolved_subs.txt
cat $output_dir/resolved_subs.txt | httpx -silent -title -status-code -tech-detect -o $output_dir/live_hosts.txt

echo "[*] Phase 3: URL Discovery (Wayback + Gau + Katana)"
cat $output_dir/live_hosts.txt | awk '{print $1}' | waybackurls > $output_dir/wayback.txt
cat $output_dir/live_hosts.txt | awk '{print $1}' | gau --blacklist png,jpg,gif,css > $output_dir/gau.txt
cat $output_dir/live_hosts.txt | katana -d 3 -jc -silent -o $output_dir/katana.txt

# Merge all URLs
cat $output_dir/*.txt | sort -u > $output_dir/all_urls.txt
echo "[+] $(wc -l < $output_dir/all_urls.txt) URLs collected"

echo "[*] Phase 4: Nuclei Critical/High Scan"
nuclei -l $output_dir/all_urls.txt -severity critical,high -o $output_dir/nuclei_critical.txt -silent

if [ -s "$output_dir/nuclei_critical.txt" ]; then
    echo " CRITICAL/HIGH findings → $output_dir/nuclei_critical.txt"
    # Store in database
    while IFS= read -r line; do
        psql bugbounty -h localhost -U hunter -c "INSERT INTO findings (subdomain_id, vuln_type, severity, url, created_at) VALUES (1, 'nuclei', 'high', '$line', NOW());"
    done < "$output_dir/nuclei_critical.txt"
fi

echo "[+] Complete → $output_dir/"
 

**Test it**:
 
./recon.sh hackerone.com
 

## Step 5: Continuous Monitoring (`monitor.sh`)

 
#!/bin/bash
# Save as: nano monitor.sh && chmod +x monitor.sh
mkdir -p previous_results

while true; do
    for domain in $(head -5 bounty-targets-data/scopes.txt); do
        echo "[*] $(date): Scanning $domain"
        ./recon.sh $domain
        
        # Detect NEW URLs only
        current_urls="recon_${domain}_*/all_urls.txt"
        prev_urls="previous_results/${domain}_urls.txt"
        
        if [ -f "$prev_urls" ] && [ -f "$current_urls" ]; then
            comm -13 <(sort $prev_urls) <(sort $current_urls) > new_urls_${domain}.txt
            if [ -s "new_urls_${domain}.txt" ]; then
                echo "🔥 NEW URLs: $(wc -l < new_urls_${domain}.txt)"
                nuclei -l new_urls_${domain}.txt -severity critical,high -o new_findings_${domain}.txt
            fi
        fi
        
        # Backup current results
        cp $current_urls $prev_urls 2>/dev/null || true
    done
    echo "[*] Sleeping 24h..."
    sleep 86400
done
 

**Run in background**:
 
nohup ./monitor.sh > monitor.log 2>&1 &
 

## Step 6: Slack/Telegram Notifications (`notify.py`)

 python
#!/usr/bin/env python3
# Save as: nano notify.py && chmod +x notify.py
import sys, requests, json

SLACK_WEBHOOK = "YOUR_SLACK_WEBHOOK_URL_HERE"

def send_slack(file_path, domain):
    with open(file_path) as f:
        for line in f:
            payload = {
                "text": f"🚨 HIGH/CRITICAL on {domain}",
                "attachments": [{"color": "danger", "text": line.strip()}]
            }
            requests.post(SLACK_WEBHOOK, json=payload)

if __name__ == "__main__":
    send_slack(sys.argv[1], sys.argv[2])
 

**Add to recon.sh** (after Nuclei scan):
 
python3 notify.py "$output_dir/nuclei_critical.txt" $domain
 

## Step 7: Cron Automation

 
# Edit crontab
crontab -e

# Add these lines:
0 2 * * * cd /home/hunter/bugbounty && ./monitor.sh >> /var/log/recon.log 2>&1
0 * * * * cd /home/hunter/bugbounty/bounty-targets-data && git pull
 

## Step 8: Scale with Axiom (Optional - $20/month)

 
# Distributed scanning (10 instances)
curl -s https://raw.githubusercontent.com/axiom-org/axiom/master/interact/axiom-install | bash
axiom-configure  # Setup DigitalOcean API
axiom-init recon 10
axiom-scan bounty-targets-data/scopes.txt -m "bash recon.sh" -o results/
 

## Hero Workflow (Daily Routine)

 
1. Check alerts: tail -f /var/log/recon.log
2. Validate Nuclei hits: burp → manual testing  
3. Submit reports → 💰 $100-10K bounties
4. Refine: custom Nuclei templates for tech stacks
5. Scale: add 5 new programs weekly
 



