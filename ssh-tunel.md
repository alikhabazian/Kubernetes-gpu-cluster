
## SSH-TUNEL-Service
### 🔧 1. Prerequisites

Install the required packages:
```
sudo apt update
sudo apt install -y ssh sshpass
```

### 🧩 2. Create .env file
Create a file anywhere (e.g. in your home directory):
```
nano ~/ssh-tunnel.env
```
Paste this and fill in your details:
```
# SSH Tunnel Configuration
PROXY_USER=myuser
PROXY_IP=1.2.3.4
SSH_PORT=22
PASS=mypassword
LOCAL_SOCKS_PORT=1111
SYS_USER=$(whoami)
```

### 3. Test SSH connection (to avoid fingerprint prompts)

```
sudosource ssh-tunnel.env
ssh $PROXY_USER@$PROXY_IP -p SSH_PORT
```
then say yes

### ⚙️ 4. Create the systemd service generator script
Create the setup script:
```
nano ~/setup-ssh-tunnel.sh
```
Paste the following:
```
#!/bin/bash
set -e

# Load environment variables
ENV_FILE="$HOME/ssh-tunnel.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Environment file not found: $ENV_FILE"
  exit 1
fi
source "$ENV_FILE"

SERVICE_PATH="/etc/systemd/system/ssh-tunnel.service"

echo "🛠️ Creating systemd service at $SERVICE_PATH ..."

sudo bash -c "cat > $SERVICE_PATH" <<EOF
[Unit]
Description=Persistent SSH Tunnel
After=network-online.target
Wants=network-online.target

[Service]
User=$TUNNEL_USER
ExecStart=/bin/bash -c '/usr/bin/sshpass -p "$PASS" /usr/bin/ssh \
    -o "ServerAliveInterval=30" \
    -o "ServerAliveCountMax=3" \
    -N -D $LOCAL_SOCKS_PORT $PROXY_USER@$PROXY_IP -p $SSH_PORT'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Service created successfully."

sudo systemctl daemon-reload
sudo systemctl enable ssh-tunnel.service
sudo systemctl start ssh-tunnel.service

echo "🚀 SSH tunnel started! Check with: sudo systemctl status ssh-tunnel.service"
```
  
### 🧾 5. Make it executable and run
```
chmod +x ~/setup-ssh-tunnel.sh
./setup-ssh-tunnel.sh
```


### 🧠 6. Verify

Check status:
```
sudo systemctl status ssh-tunnel.service
```

Test proxy:
```
curl --socks5 localhost:1111 https://api.ipify.org
```
