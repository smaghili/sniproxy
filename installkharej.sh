#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Prompt for user input with improved formatting
echo
echo "Please enter the following information:"
echo
read -p "Enter the desired panel port: " PANEL_PORT
echo
read -p "Enter the admin username: " ADMIN_USERNAME
echo
read -s -p "Enter the admin password: " ADMIN_PASSWORD
echo
echo

# Uninstall previous installation
echo "Removing previous installation..."
systemctl stop sniproxy
systemctl disable sniproxy
systemctl stop dnsproxy-web-panel.service
systemctl disable dnsproxy-web-panel.service
rm -rf /opt/sniproxy
rm -f /etc/systemd/system/sniproxy.service
rm -f /etc/systemd/system/dnsproxy-web-panel.service
systemctl daemon-reload

# Function to install package if not already installed
install_if_not_exists() {
    if ! command -v $1 &> /dev/null; then
        echo "$1 is not installed. Installing it now..."
        apt-get update
        apt-get install -y $1
    else
        echo "$1 is already installed."
    fi
}

# Install necessary packages
install_if_not_exists expect
install_if_not_exists python3-pip

# Install required Python packages
echo "Installing required Python packages..."
pip3 install flask PyYAML requests

# Verify Python packages are installed
for package in flask PyYAML requests; do
    if ! pip3 show $package > /dev/null 2>&1; then
        echo "Error: $package is not installed. Trying to install..."
        pip3 install $package
        if [ $? -ne 0 ]; then
            echo "Failed to install $package. Please install it manually and run the script again."
            exit 1
        fi
    fi
done

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
mkdir -p /opt/sniproxy
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

# Create systemd service file for sniproxy
cat > /etc/systemd/system/sniproxy.service <<EOL
[Unit]
Description=SNI Proxy
After=network.target

[Service]
ExecStart=/opt/sniproxy/sniproxy --config /opt/sniproxy/sniproxy.yaml
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOL

# Create systemd service file for web panel
cat > /etc/systemd/system/dnsproxy-web-panel.service <<EOL
[Unit]
Description=DNS Proxy Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/sniproxy/web_panel.py
Restart=always
User=root
Environment=FLASK_APP=/opt/sniproxy/web_panel.py
Environment=PANEL_PORT=$PANEL_PORT
Environment=ADMIN_USERNAME=$ADMIN_USERNAME
Environment=ADMIN_PASSWORD=$ADMIN_PASSWORD

[Install]
WantedBy=multi-user.target
EOL

# Modify web_panel.py to use environment variables
sed -i '1i import os' /opt/sniproxy/web_panel.py
sed -i 's/app.secret_key = .*/app.secret_key = os.urandom(24)/' /opt/sniproxy/web_panel.py
sed -i "s/ADMIN_USERNAME = .*/ADMIN_USERNAME = os.environ['ADMIN_USERNAME']/" /opt/sniproxy/web_panel.py
sed -i "s/ADMIN_PASSWORD = .*/ADMIN_PASSWORD = os.environ['ADMIN_PASSWORD']/" /opt/sniproxy/web_panel.py
sed -i "s/app.run(host='0.0.0.0', port=5000)/app.run(host='0.0.0.0', port=int(os.environ['PANEL_PORT']))/" /opt/sniproxy/web_panel.py

# Reload systemd, enable and start the services
systemctl daemon-reload
systemctl enable sniproxy
systemctl start sniproxy
systemctl enable dnsproxy-web-panel
systemctl start dnsproxy-web-panel

# Function to check service status
check_service_status() {
    if systemctl is-active --quiet $1; then
        return 0
    else
        echo "$2 failed to start or is not running."
        journalctl -u $1 --no-pager -n 10
        return 1
    fi
}

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Check the status of services
if check_service_status sniproxy.service "SNI Proxy"; then
    echo "sniproxy is now running, you can set up DNS in your clients to $SERVER_IP"
else
    echo "Failed to start SNI Proxy. Check the logs above for more information."
fi

if check_service_status dnsproxy-web-panel.service "Web Panel"; then
    echo "Web Panel Running on http://$SERVER_IP:$PANEL_PORT"
else
    echo "Failed to start Web Panel. Check the logs above for more information."
fi

echo "Setup completed!"

(crontab -l 2>/dev/null; echo "*/5 * * * * /bin/systemctl restart sniproxy.service") | crontab -

echo "Added cron job to restart sniproxy every 5 minutes."
