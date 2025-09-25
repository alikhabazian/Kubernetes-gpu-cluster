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



# Download the install script
echo "Downloading Xray install script..."
curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh -o install-release.sh
if [ $? -ne 0 ]; then
    echo "Failed to download install-release.sh"
    exit 1
fi

# Make it executable
echo "Making script executable..."
chmod +x install-release.sh

# Run the install script with sudo
echo "Running the install script..."
sudo ./install-release.sh
if [ $? -ne 0 ]; then
    echo "Xray install failed!"
    exit 1
fi

# Check if Xray works
echo "Checking Xray version..."
if command -v xray >/dev/null 2>&1; then
    xray version
    if [ $? -eq 0 ]; then
        echo "Xray installed and working!"
    else
        echo "Xray binary exists but failed to run."
        exit 1
    fi
else
    echo "Xray is not installed or not in PATH."
    exit 1
fi
##########################
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

# Check if xray is installed
if [ -z "$XRAY_BIN" ]; then
    echo "Xray binary not found! Please install Xray first."
    exit 1
fi

# Run Xray in background
echo "Starting Xray..."
sudo "$XRAY_BIN" -config "$CONFIG_FILE" &
XRAY_PID=$!
sleep 10  # give it a few seconds to start

# Test the proxy
echo "Testing proxy with curl..."
curl --proxy "$PROXY" -s --head "$TEST_URL" >/dev/null
if [ $? -eq 0 ]; then
    echo "Xray is working! Proxy is reachable."
else
    echo "Error: Xray config does not work or proxy is unreachable."
fi

echo "Kill Xray running..."
sudo kill $XRAY_PID

XRAY_HOME="$HOME/xray"
CONFIG_FILE="$XRAY_HOME/config.json"
SYSTEMD_DIR="/etc/systemd/system/xray.service.d"
SYSTEMD_OVERRIDE="$SYSTEMD_DIR/99-custom.conf"
XRAY_BIN="/usr/local/bin/xray"

# Step 1: Set permissions
echo "Setting permissions..."
sudo chmod 755 "$HOME"
sudo chmod 755 "$XRAY_HOME"
sudo chmod 644 "$CONFIG_FILE"

# Step 2: Stop Xray if running
echo "Stopping Xray service if running..."
sudo systemctl stop xray 2>/dev/null

# Step 3: Create systemd override directory if not exist
echo "Creating systemd override directory..."
sudo mkdir -p "$SYSTEMD_DIR"

# Step 4: Write systemd override file
echo "Writing systemd override..."
sudo tee "$SYSTEMD_OVERRIDE" > /dev/null <<EOL
[Unit]
Description=Xray Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=
ExecStart=$XRAY_BIN -config $CONFIG_FILE
Restart=always
RestartSec=5
User=root
LimitNOFILE=65535
WorkingDirectory=$XRAY_HOME

[Install]
WantedBy=multi-user.target
EOL

# Step 5: Reload systemd and start service
echo "Reloading systemd..."
sudo systemctl daemon-reload

echo "Enabling and starting Xray service..."
sudo systemctl enable xray
sudo systemctl restart xray

sleep 10

echo "Testing proxy with curl..."
curl --proxy "$PROXY" -s --head "$TEST_URL" >/dev/null
if [ $? -eq 0 ]; then
    echo "Xray is working! Proxy is reachable."
else
    echo "Error: Xray config does not work or proxy is unreachable."
fi
