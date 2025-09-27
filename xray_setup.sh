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
CONFIG_FILE="$INSTALL_DIR/config.json"
XRAY_BIN=$(command -v xray)
PROXY="socks5://127.0.0.1:1080"
TEST_URL="https://www.facebook.com"

##########################
# Ensure curl is installed
if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found. Installing..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update && sudo apt-get install -y curl
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y curl
    else
        echo "Unsupported OS. Please install curl manually."
        exit 1
    fi
fi

##########################
# Ensure wget is installed
if ! command -v wget >/dev/null 2>&1; then
    echo "wget not found. Installing..."
    if [ -f /etc/debian_version ]; then
        sudo apt-get update && sudo apt-get install -y wget
    elif [ -f /etc/redhat-release ]; then
        sudo yum install -y wget
    else
        echo "Unsupported OS. Please install wget manually."
        exit 1
    fi
fi

##########################
# Download and install Xray
echo "Installing Xray..."
curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o install-release.sh
chmod +x install-release.sh
sudo ./install-release.sh

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

##########################
# Copy config into system path
echo "Copying config.json to /usr/local/etc/xray/"
sudo mkdir -p /usr/local/etc/xray
sudo cp "$CONFIG_FILE" /usr/local/etc/xray/config.json

##########################
# Restart Xray service
echo "Restarting Xray service..."
sudo systemctl restart xray

sleep 10

# Test proxy
echo "Testing proxy with curl..."
curl --proxy "$PROXY" -s --head "$TEST_URL" >/dev/null
if [ $? -eq 0 ]; then
    echo "Xray is working! Proxy is reachable."
else
    echo "Error: Xray config does not work or proxy is unreachable."
fi
