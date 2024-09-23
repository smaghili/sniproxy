#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Check if expect is installed
if ! command -v expect &> /dev/null
then
    echo "expect is not installed. Installing it now..."
    apt-get update
    apt-get install -y expect
fi

# Run the install script with expect
expect <<EOF
spawn bash -c "curl -L https://raw.githubusercontent.com/smaghili/sniproxy/master/install.sh | bash"
# Press Enter to use 9.9.9.9 as DNS
expect "Press Ctrl-C to abort or Enter to replace the DNS server with 9.9.9.9, otherwise enter your preffered DNS server and press Enter"
send "\r"
# Press Enter to proxy all HTTPS traffic
expect "sniproxy can proxy all HTTPS traffic or only specific domains, if you have a domain list URL, enter it below, otherwise press Enter to proxy all HTTPS traffic"
send "\r"
# Disable DNS over TCP
expect "Do you want to enable DNS over TCP? (y/n)"
send "n\r"
# Disable DNS over TLS
expect "Do you want to enable DNS over TLS? (y/n)"
send "n\r"
# Disable DNS over QUIC
expect "Do you want to enable DNS over QUIC? (y/n)"
send "n\r"
# Wait for the script to finish
expect eof
EOF

echo "Installation completed!"

# Copy required files
echo "Copying required files..."
cd /opt/sniproxy/
curl -O https://raw.githubusercontent.com/smaghili/sniproxy/master/web_panel.py
curl -O https://raw.githubusercontent.com/smaghili/sniproxy/master/domains.csv
curl -O https://raw.githubusercontent.com/smaghili/sniproxy/master/cidr.csv

# Create templates directory and copy HTML files
mkdir -p templates
cd templates
curl -O https://raw.githubusercontent.com/smaghili/sniproxy/master/templates/index.html
curl -O https://raw.githubusercontent.com/smaghili/sniproxy/master/templates/login.html
curl -O https://raw.githubusercontent.com/smaghili/sniproxy/master/templates/addip.html

echo "All required files have been copied to /opt/sniproxy/"

# Update sniproxy.yaml
cat > /opt/sniproxy/sniproxy.yaml <<EOL
acl:
  cidr:
    enabled: false
    path: /opt/sniproxy/cidr.csv
    priority: 30
    refresh_interval: 1h0m0s
  domain:
    enabled: false
    path: /opt/sniproxy/domains.csv
    priority: 20
    refresh_interval: 1h0m0s
  geoip:
    allowed: null
    blocked: null
    enabled: false
    path: null
    priority: 10
    refresh_interval: 24h0m0s
  override:
    doh_sni: myawesomedoh.example.com
    enabled: false
    priority: 40
    rules:
      google.com: 8.8.8.8:443
      one.one.one.one: 1.1.1.1:443
    tls_cert: null
    tls_key: null
general:
  bind_dns_over_quic: null
  bind_dns_over_tcp: null
  bind_dns_over_tls: null
  bind_dns_over_udp: 0.0.0.0:53
  bind_http: 0.0.0.0:80
  bind_https: 0.0.0.0:443
  bind_prometheus: null
  interface: null
  log_level: info
  public_ipv4: null
  public_ipv6: null
  tls_cert: null
  tls_key: null
  upstream_dns: udp://8.8.8.8:53
  upstream_dns_over_socks5: false
  upstream_socks5: null
EOL

echo "Updated sniproxy.yaml"

# Check if Python packages are already installed
if ! pip3 list | grep -q "Flask"; then
    echo "Installing required Python packages..."
    pip3 install flask PyYAML
else
    echo "Required Python packages are already installed."
fi

# Create systemd service file
cat > /etc/systemd/system/dnsproxy-web-panel.service <<EOL
[Unit]
Description=DNS Proxy Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/sniproxy/web_panel.py
Restart=always
User=root
Environment=FLASK_APP=/opt/sniproxy/web_panel.py

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd, enable and start the service
systemctl daemon-reload
systemctl enable dnsproxy-web-panel
systemctl start dnsproxy-web-panel

# Check the status of dnsproxy-web-panel service
if systemctl is-active --quiet dnsproxy-web-panel.service; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Web Panel Running on http://$SERVER_IP:5000"
else
    echo "Failed to start DNS Proxy Web Panel service."
fi

# Check the status of sniproxy service
if systemctl is-active --quiet sniproxy.service; then
    echo "DNS service is successfully running on port 53."
else
    echo "Failed to start DNS service."
fi

echo "Setup completed!"
