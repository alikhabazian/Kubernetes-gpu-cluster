#!/bin/bash
set -e

# Versions
CRIO_VERSION="v1.33"
VERSION="v1.33.0"
# Paths
KEYRING="/etc/apt/keyrings/cri-o-apt-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/cri-o.list"
APT_CONF="/etc/apt/apt.conf"

echo "[*] Updating apt and installing prerequisites..."
sudo apt-get update
sudo apt-get install -y software-properties-common curl gnupg

echo "[*] Setting up keyrings directory..."
sudo mkdir -p /etc/apt/keyrings

echo "[*] Importing CRI-O GPG key..."
curl -fsSL "https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor -o "$KEYRING"

echo "[*] Adding CRI-O repo..."
echo "deb [signed-by=$KEYRING] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/${CRIO_VERSION}/deb/ /" \
  | sudo tee "$SOURCE_LIST" > /dev/null

echo "[*] Configuring apt to use Privoxy proxy (127.0.0.1:8118) for OpenSUSE downloads..."
sudo tee -a "$APT_CONF" > /dev/null <<EOL
Acquire::http::Proxy::download.opensuse.org "http://127.0.0.1:8118";
Acquire::https::Proxy::download.opensuse.org "http://127.0.0.1:8118";
EOL

echo "[*] Updating apt with new repo..."
sudo apt-get update

echo "[*] Installing CRI-O..."
sudo apt-get install -y cri-o

echo "[*] Enabling and starting CRI-O service..."
sudo systemctl enable crio.service
sudo systemctl restart crio.service

echo "[*] Checking CRI-O status..."
crio --version

echo "[*] Install crictl..."
curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/${VERSION}/crictl-${VERSION}-linux-amd64.tar.gz -o crictl.tar.gz

# Extract and install
sudo tar zxvf crictl.tar.gz -C /usr/local/bin
rm crictl.tar.gz
echo "[*] Checking crictl status..."
# Verify
crictl --version
