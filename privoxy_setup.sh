#!/bin/bash

# Variables
PROXY="127.0.0.1:1111"
PRIVOXY_CONFIG="/etc/privoxy/config"

# Step 1: Install Privoxy
echo "Installing Privoxy..."
sudo apt update
sudo apt install -y privoxy

# Step 2: Backup original config
if [ ! -f "$PRIVOXY_CONFIG.bak" ]; then
    echo "Backing up original Privoxy config..."
    sudo cp "$PRIVOXY_CONFIG" "$PRIVOXY_CONFIG.bak"
fi

# Step 3: Configure Privoxy to forward traffic through SOCKS5
echo "Configuring Privoxy to use SOCKS5 proxy $PROXY..."
sudo sed -i '/^forward-socks5/ d' "$PRIVOXY_CONFIG"   # remove existing lines
echo "forward-socks5 / $PROXY ." | sudo tee -a "$PRIVOXY_CONFIG" > /dev/null

# Step 4: Restart Privoxy
echo "Restarting Privoxy..."
sudo systemctl restart privoxy

# Step 5: Check status
echo "Privoxy status:"
sudo systemctl status privoxy --no-pager

# Step 6: Test Privoxy
echo "Testing Privoxy via curl..."
curl --proxy http://127.0.0.1:8118 -s --head https://www.facebook.com >/dev/null
if [ $? -eq 0 ]; then
    echo "Privoxy is working! on http://127.0.0.1:8118"
else
    echo "Error: Privoxy is not working correctly."
fi
