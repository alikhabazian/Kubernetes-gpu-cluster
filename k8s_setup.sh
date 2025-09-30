#!/bin/bash

# reset-k8s.sh — cleanup Kubernetes bits and disable swap
# Usage: sudo bash reset-k8s.sh [--yes]
#   --yes  run non-interactively (assume "yes" to deletions/changes)
# sudo bash k8s_setup.sh --yes --role=node --join="$(ssh ths-4@192.168.41.104 'kubeadm token create --print-join-command')"
export http_proxy="http://127.0.0.1:8118"
export https_proxy="http://127.0.0.1:8118"
export no_proxy="localhost,127.0.0.1,::1"

set -euo pipefail

ASK_CONFIRM=true
[[ "${1:-}" == "--yes" ]] && ASK_CONFIRM=false

# Defaults
ROLE=""                     # control_plane | node
KUBE_VERSION="v1.33.3"
CRI_SOCKET="unix:///var/run/crio/crio.sock"
JOIN_CMD=""

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --role=*|--role)
        val="${arg#*=}"; [[ "$val" == "$arg" ]] && { shift; val="${1:-}"; }
        case "${val//-/_}" in
          control_plane|control*|cp) ROLE="control_plane" ;;
          node|worker) ROLE="node" ;;
          *) warn "Unknown role '$val' (expected control_plane|node)";;
        esac
        ;;
      --kube-version=*|--kube-version)
        val="${arg#*=}"; [[ "$val" == "$arg" ]] && { shift; val="${1:-}"; }
        [[ -n "$val" ]] && KUBE_VERSION="$val"
        ;;
      --cri-socket=*|--cri-socket)
        val="${arg#*=}"; [[ "$val" == "$arg" ]] && { shift; val="${1:-}"; }
        [[ -n "$val" ]] && CRI_SOCKET="$val"
        ;;
      --join=*|--join)
        val="${arg#*=}"; [[ "$val" == "$arg" ]] && { shift; val="${1:-}"; }
        JOIN_CMD="$val --cri-socket unix:///var/run/crio/crio.sock"
        ;;
    esac
  done
}

log()   { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "Please run as root (e.g.,: sudo bash $0)"; exit 1
  fi
}

confirm() {
  $ASK_CONFIRM || return 0
  read -r -p "$1 [y/N]: " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

stop_disable_service() {
  local svc="$1"
  if have_cmd systemctl && systemctl list-unit-files | grep -q "^${svc}\.service"; then
    if systemctl is-active --quiet "$svc"; then
      log "Stopping $svc.service"
      systemctl stop "$svc" || warn "Failed to stop $svc (continuing)"
    else
      log "$svc.service is not active"
    fi
    if systemctl is-enabled --quiet "$svc"; then
      log "Disabling $svc.service"
      systemctl disable "$svc" || warn "Failed to disable $svc"
    else
      log "$svc.service is already disabled"
    fi
  else
    log "$svc.service not found (skipping)"
  fi
}

remove_paths() {
  local paths=("$@")
  log "About to remove the following paths:"
  printf '  - %s\n' "${paths[@]}"
  if confirm "Proceed with deletion?"; then
    for p in "${paths[@]}"; do
      if [[ -e "$p" || -L "$p" ]]; then
        log "Removing $p"
        rm -rf --one-file-system "$p" || warn "Failed to remove $p"
      else
        log "Path not found: $p (skipping)"
      fi
    done
  else
    warn "Deletion skipped by user"
  fi
}

pids_on_port() {
  local port="$1"
  # Try ss first
  if have_cmd ss; then
    ss -ltnp 2>/dev/null | awk -v p=":$port" '
      $4 ~ p {
        for (i=1;i<=NF;i++) if ($i ~ /pid=/) { sub("pid=","",$i); sub(",.*","",$i); print $i }
      }' | sort -u
  elif have_cmd lsof; then
    lsof -i TCP:"$port" -sTCP:LISTEN -Fp 2>/dev/null | sed 's/^p//'
  else
    return 0
  fi
}

kill_pids() {
  local pids=("$@")
  [[ ${#pids[@]} -eq 0 ]] && return 0
  log "Killing PIDs: ${pids[*]}"
  kill "${pids[@]}" 2>/dev/null || true
  sleep 1
  # SIGKILL if still alive
  local still=()
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then still+=("$pid"); fi
  done
  if [[ ${#still[@]} -gt 0 ]]; then
    warn "PIDs still alive, sending SIGKILL: ${still[*]}"
    kill -9 "${still[@]}" 2>/dev/null || true
  fi
}
free_port_6443() {
  log "Checking for listeners on TCP 6443 (kube-apiserver)"
  mapfile -t pids < <(pids_on_port 6443 || true)
  if [[ ${#pids[@]} -gt 0 ]]; then
    printf "  Found PIDs on :6443: %s\n" "${pids[*]}"
    if confirm "Kill these processes?"; then
      kill_pids "${pids[@]}"
    else
      warn "Leaving :6443 listeners running"
    fi
  else
    log "No listeners on :6443"
  fi
}

pkill_apiserver() {
  if pgrep -fa kube-apiserver >/dev/null 2>&1; then
    log "Found kube-apiserver processes"
    pgrep -fa kube-apiserver | sed 's/^/  /'
    if confirm "pkill -f kube-apiserver ?"; then
      pkill -f "kube-apiserver" || true
    else
      warn "Skipped pkill for kube-apiserver"
    fi
  else
    log "No kube-apiserver processes found"
  fi
}

swap_show() {
  log "Swap status:"
  if have_cmd free; then free -h; fi
  if have_cmd swapon; then
    echo
    swapon --show || true
  fi
}

swap_disable_temp() {
  if have_cmd swapon && swapon --noheadings --show=NAME | grep -q .; then
    if confirm "Temporarily disable swap now (swapoff -a)?"; then
      log "Running swapoff -a"
      swapoff -a || warn "swapoff failed"
    else
      warn "Temporary swapoff skipped"
    fi
  else
    log "No active swap devices detected"
  fi
}

fstab_disable_swap() {
  local fstab="/etc/fstab"
  if [[ -r "$fstab" ]]; then
    # detect uncommented swap lines
    if awk '$0 !~ /^#/ && $3 == "swap" {found=1} END{exit !found}' "$fstab"; then
      log "Swap entries found in $fstab"
      if confirm "Comment out swap entries in $fstab to persistently disable swap?"; then
        local backup="${fstab}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$fstab" "$backup"
        log "Backup saved: $backup"
        # Comment non-commented lines where fs_vfstype == swap
        awk '
          BEGIN{changed=0}
          /^\s*#/ {print; next}
          {
            if ($3 == "swap") { print "# " $0; changed=1 }
            else { print }
          }
          END{ if (!changed) exit 1 }
        ' "$backup" > "$fstab" || { error "Failed editing fstab; restoring backup"; cp -a "$backup" "$fstab"; }
      else
        warn "Persistent swap disable (fstab) skipped"
      fi
    else
      log "No active (uncommented) swap entries in $fstab"
    fi
  else
    warn "Cannot read $fstab — skipping persistent swap change"
  fi
}

systemd_swap_disable() {
  if have_cmd systemctl; then
    mapfile -t units < <(systemctl list-unit-files --type=swap --state=enabled --no-legend 2>/dev/null | awk '{print $1}')
    if [[ ${#units[@]} -gt 0 ]]; then
      log "Disabling/masking enabled swap units: ${units[*]}"
      for u in "${units[@]}"; do
        systemctl disable "$u" || true
        systemctl mask "$u" || true
      done
    else
      log "No enabled *.swap units"
    fi
  fi
}

setup_netfilters() {
  log "Ensuring br_netfilter module and IP forwarding"
  if ! lsmod | grep -q '^br_netfilter'; then
    modprobe br_netfilter || warn "Failed to load br_netfilter"
  else
    log "br_netfilter already loaded"
  fi

  # Make it persistent
  mkdir -p /etc/modules-load.d
  if ! grep -q '^br_netfilter$' /etc/modules-load.d/k8s.conf 2>/dev/null; then
    echo "br_netfilter" >> /etc/modules-load.d/k8s.conf
    log "Persisted br_netfilter in /etc/modules-load.d/k8s.conf"
  fi

  # Runtime settings
  sysctl -w net.ipv4.ip_forward=1 || warn "Failed to set net.ipv4.ip_forward=1"
  sysctl -w net.bridge.bridge-nf-call-iptables=1 2>/dev/null || true
  sysctl -w net.bridge.bridge-nf-call-ip6tables=1 2>/dev/null || true

  # Persist sysctls
  mkdir -p /etc/sysctl.d
  cat >/etc/sysctl.d/99-kubernetes-cri.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
  sysctl --system >/dev/null || warn "sysctl --system reported issues"
}

install_k8s_apt() {
  if ! have_cmd apt-get; then
    warn "apt-get not available; skipping Kubernetes apt install"
    return 0
  fi

  log "Installing Kubernetes via official apt repo"
  apt-get update -y || warn "apt-get update failed (continuing)"
  apt-get install -y apt-transport-https ca-certificates curl gpg || {
    warn "Failed installing prerequisites"; return 0; }

  install -d -m 0755 /etc/apt/keyrings

  
  sudo -E curl --proxy http://127.0.0.1:8118 -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg


  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /" \
    >/etc/apt/sources.list.d/kubernetes.list

  apt-get update -y
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl || true

  systemctl enable --now kubelet || warn "Failed to enable/start kubelet"
}

setup_crio_proxy() {
  log "Configuring proxy environment for CRI-O service"

  mkdir -p /etc/systemd/system/crio.service.d

  cat >/etc/systemd/system/crio.service.d/proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:8118"
Environment="HTTPS_PROXY=http://127.0.0.1:8118"
Environment="NO_PROXY=localhost,127.0.0.1,::1,.svc,.svc.cluster.local,.cluster.local,10.96.0.0/12,10.244.0.0/16,192.168.0.0/16,169.254.0.0/16"
Environment="http_proxy=http://127.0.0.1:8118"
Environment="https_proxy=http://127.0.0.1:8118"
Environment="no_proxy=localhost,127.0.0.1,::1,.svc,.svc.cluster.local,.cluster.local,10.96.0.0/12,10.244.0.0/16,192.168.0.0/16,169.254.0.0/16"
Environment="ALL_PROXY=http://127.0.0.1:8118"
Environment="all_proxy=http://127.0.0.1:8118"
EOF

  systemctl daemon-reload
  if systemctl list-unit-files | grep -q '^crio.service'; then
    systemctl restart crio || warn "Failed to restart crio"
    log "CRI-O proxy env:"
    systemctl show crio -p Environment || true
  else
    warn "crio.service not found; skipped restart"
  fi
}



post_init_kubeconfig() {
  # If script ran under sudo, set up for that user; else for root
  local target_user="${SUDO_USER:-root}"
  local home_dir
  home_dir="$(getent passwd "$target_user" | cut -d: -f6)"
  if [[ -d "$home_dir" ]]; then
    log "Configuring kubeconfig for user '$target_user' ($home_dir)"
    install -d -m 0700 "$home_dir/.kube"
    cp -f /etc/kubernetes/admin.conf "$home_dir/.kube/config"
    chown "$(id -u "$target_user")":"$(id -g "$target_user")" "$home_dir/.kube/config"
  else
    warn "Home dir for $target_user not found; exporting KUBECONFIG for root"
    export KUBECONFIG=/etc/kubernetes/admin.conf
  fi
}

init_control_plane() {
  log "Initializing control plane with kubeadm ($KUBE_VERSION, $CRI_SOCKET)"
  local ts logf rc
  ts="$(date +%Y%m%d%H%M%S)"
  logf="/var/log/kubeadm-init-$ts.log"

  set +e
  kubeadm init \
    --cri-socket="$CRI_SOCKET" \
    --kubernetes-version="$KUBE_VERSION" | tee "$logf"
  rc="${PIPESTATUS[0]}"
  set -e

  if [[ "$rc" -ne 0 ]]; then
    error "kubeadm init failed (exit $rc). See $logf"
    return "$rc"
  fi

  # Simple success heuristic: kubeadm prints 'kubeadm join' hints
  if grep -qE 'kubeadm join *.*.*.* --token' "$logf"; then
    log "kubeadm init appears successful; setting up kubeconfig"
    post_init_kubeconfig
  else
    warn "Did not detect 'kubeadm join' in logs; double-check $logf"
  fi
}

join_node() {
  if [[ -z "$JOIN_CMD" ]]; then
    error "No join command provided. Pass with: --join 'kubeadm join <api:port> --token ... --discovery-token-ca-cert-hash sha256:...'"
    return 1
  fi
  log "Joining node with provided kubeadm command"
  # shellcheck disable=SC2086
  echo "$JOIN_CMD"
  bash -c "$JOIN_CMD"
}


main() {
  require_root

  log "Stopping/Disabling kubelet service (if present)"
  stop_disable_service kubelet

  log "Killing kube-apiserver (if running)"
  pkill_apiserver

  log "Freeing port 6443 (if in use)"
  free_port_6443

  log "Removing Kubernetes data directories"
  remove_paths \
    /etc/kubernetes/ \
    /var/lib/kubelet/ \
    /var/lib/etcd/ \
    "$HOME/.kube/"

  echo
  log "Swap configuration — current status:"
  swap_show
  echo
  swap_disable_temp
  systemd_swap_disable
  fstab_disable_swap

  echo
  log "Final status:"
  swap_show
  
  log "Networking prerequisites for Kubernetes"
  setup_netfilters

  log "Install/enable Kubernetes components (Debian/Ubuntu)"
  install_k8s_apt
    
  log "Configuring CRI-O proxy drop-in"
  setup_crio_proxy

  parse_args "$@"

  if [[ "$ROLE" == "control_plane" ]]; then
    init_control_plane
    curl -fsSL -o calico.yaml https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml
    kubectl apply -f calico.yaml
  elif [[ "$ROLE" == "node" ]]; then
    join_node
  else
    log "No role specified; skip kubeadm init/join. Use --role=control_plane or --role=node"
  fi

}

main "$@"





