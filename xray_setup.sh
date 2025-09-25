#!/bin/bash

# Define installation directory
INSTALL_DIR="$HOME/xray"

# Check if directory exists, create if not
if [ ! -d "$INSTALL_DIR" ]; then
    echo "Creating directory $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
fi


# Move into the directory
cd "$INSTALL_DIR" || { echo "Failed to enter $INSTALL_DIR"; exit 1; }


CONFIG_URL="https://drive.google.com/uc?export=download&id=1WiPY7g7awEExGN_DaqQKvLRv5wY2z22V"
CONFIG_FILE="config.json"
XRAY_BIN=$(command -v xray)
PROXY="socks5://127.0.0.1:1080"
TEST_URL="https://www.facebook.com"
##########################

# Download the config
echo "Downloading Xray config..."
wget -O "$CONFIG_FILE" --no-check-certificate "$CONFIG_URL"
if [ $? -ne 0 ]; then
    echo "Failed to download config.json"
    exit 1
fi

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "config.json not found!"
    exit 1
fi










sudo systemctl restart xray

sleep 10

echo "Testing proxy with curl..."
curl --proxy "$PROXY" -s --head "$TEST_URL" >/dev/null
if [ $? -eq 0 ]; then
    echo "Xray is working! Proxy is reachable."
else
    echo "Error: Xray config does not work or proxy is unreachable."
fi
