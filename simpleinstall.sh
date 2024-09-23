#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Uninstall previous installation
echo "Removing previous installation..."
systemctl stop sniproxy
systemctl disable sniproxy
systemctl stop dnsproxy-web-panel.service
systemctl disable dnsproxy-web-panel.service
rm -rf /opt/sniproxy
rm -f /etc/systemd/system/sniproxy.service
rm -f /etc/systemd/system/dnsproxy-web-panel.service
rm -rf /var/log/sniproxy
systemctl daemon-reload

echo "Previous installation removed."

# Check if expect is installed
if ! command -v expect &> /dev/null; then
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

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')

# Check if sniproxy is running
if systemctl is-active --quiet sniproxy; then
    echo "sniproxy is running. sniproxy is now running, you can set up DNS in your clients to $SERVER_IP"
else
    echo "Failed to start sniproxy. Please check the logs for more information."
fi
