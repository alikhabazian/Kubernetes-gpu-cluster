#!/usr/bin/env bash
# Safer GPU + CRI-O setup: skip apt on failure, keep going on config steps.
# Usage:
#   sudo SKIP_APT=1 bash gpu-crio-setup.sh     # force-skip apt work
#   sudo bash gpu-crio-setup.sh                 # auto-skip if apt fails

set -uo pipefail

log()   { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error() { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
have_cmd(){ command -v "$1" >/dev/null 2>&1; }

require_root(){
  if [[ "$(id -u)" -ne 0 ]]; then error "Run as root (sudo)."; exit 1; fi
}

apt_update_safe(){
  [[ "${SKIP_APT:-0}" == "1" ]] && { warn "SKIP_APT=1 set; skipping apt."; return 1; }
  log "Running apt-get update (with retries)..."
  local ok=0
  for i in 1 2 3; do
    if apt-get -o Acquire::Retries=3 update -y; then ok=1; break; fi
    warn "apt-get update attempt $i failed; retrying..."
    sleep 2
  done
  if [[ "$ok" -ne 1 ]]; then
    warn "apt-get update failed; continuing without apt installs."
    return 1
  fi
  return 0
}

install_conmon(){
  if have_cmd conmon; then log "conmon present: $(conmon --version 2>/dev/null | head -n1)"; return; fi
  if apt_update_safe && apt-get install -y conmon; then
    log "Installed conmon."
  else
    warn "Could not install conmon (apt unavailable). Skipping."
  fi
}

install_crun(){
  if have_cmd crun; then log "crun present: $(crun --version 2>/dev/null | head -n1)"; return; fi
  # Fallback: fetch official Debian crun .deb directly (no external apt repos).
  apt_update_safe
  sudo apt install -y libseccomp-dev build-essential git autotools-dev libtool pkg-config libsystemd-dev libcap-dev libseccomp-dev libyajl-dev go-md2man
  git clone https://github.com/containers/crun.git
  cd crun
  git checkout 1.21
  ./autogen.sh
  ./configure
  make
  sudo make install
  have_cmd crun && crun --version || warn "crun install may have failed."
}

install_nvidia_toolkit(){
  if have_cmd nvidia-ctk && have_cmd nvidia-container-toolkit; then
    log "NVIDIA toolkit present: $(nvidia-ctk --version 2>/dev/null | head -n1)"
    return
  fi
  log "Add nvidia key:"
  curl --proxy http://127.0.0.1:8118 -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit.gpg
  
  #distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
  distribution="ubuntu20.04"
  curl --proxy http://127.0.0.1:8118 -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  # Try to install via apt ONLY if apt update succeeded.
  if apt_update_safe; then
    apt-get install -y nvidia-container-toolkit || warn "Failed to install nvidia-container-toolkit."
  else
    warn "Skipping NVIDIA toolkit install due to apt failure. If device plugin still shows NVML errors, install later:"
    warn "  https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/"
  fi
  sudo add-apt-repository ppa:graphics-drivers/ppa
  apt_update_safe
  sudo apt install -y nvidia-driver-550 nvidia-utils-550

}

configure_nvidia_ctk_for_crio(){
  if ! have_cmd nvidia-ctk; then warn "nvidia-ctk not found; skipping runtime configure."; return; fi
  if ! systemctl list-unit-files | grep '^crio\.service'; then warn "crio.service not found; skipping."; return; fi
  log "Configuring NVIDIA runtime hooks for CRI-O and setting default."
  mkdir -p /etc/crio/crio.conf.d
  nvidia-ctk runtime configure --runtime=crio --set-as-default --config=/etc/crio/crio.conf.d/99-nvidia.conf || warn "nvidia-ctk runtime configure failed."
  log "Enabling CDI and generating spec."
  nvidia-ctk runtime configure --runtime=crio --cdi.enabled=true || true
  mkdir -p /etc/cdi
  nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml || true
  systemctl daemon-reload
  systemctl restart crio || warn "Failed to restart crio."
  systemctl restart kubelet || true
}

configure_crio_hooks_dir(){
  log "Ensuring CRI-O hooks_dir is set."
  mkdir -p /etc/crio/crio.conf.d
  cat >/etc/crio/crio.conf.d/99-nvidia-hooks.conf <<'EOF'
[crio.runtime]
hooks_dir = ["/usr/share/containers/oci/hooks.d", "/etc/containers/oci/hooks.d"]
EOF
  systemctl daemon-reload
  systemctl restart crio || warn "crio restart failed after hooks_dir."
}

configure_nvidia_hook(){
  log "Placing NVIDIA OCI hook (best-effort)."
  mkdir -p /usr/share/containers/oci/hooks.d
  cat >/usr/share/containers/oci/hooks.d/oci-nvidia-hook.json <<'JSON'
{
  "version": "1.0.0",
  "hook": { "path": "/usr/bin/nvidia-container-toolkit", "args": ["nvidia-container-toolkit", "prestart"] },
  "when": { "always": true },
  "stages": ["prestart"]
}
JSON
  [[ -x /usr/bin/nvidia-container-toolkit ]] || warn "nvidia-container-toolkit binary missing; hook may be inert."
}

verify(){
  log "Verification:"
  have_cmd conmon && conmon --version || true
  have_cmd crun && crun --version || true
  have_cmd nvidia-ctk && nvidia-ctk --version || true
  have_cmd crio && crio --version || true
  ls -l /etc/crio/crio.conf.d/ 2>/dev/null || true
  [[ -f /etc/cdi/nvidia.yaml ]] && sed -n '1,25p' /etc/cdi/nvidia.yaml || log "No /etc/cdi/nvidia.yaml (ok if toolkit not installed)."
}

main(){
  require_root
  install_conmon
  install_crun
  install_nvidia_toolkit
  configure_nvidia_ctk_for_crio
  configure_crio_hooks_dir
  configure_nvidia_hook
  sudo ln -s /usr/libexec/crio/conmon /usr/local/bin/conmon
  systemctl daemon-reload
  systemctl restart crio || warn "crio restart failed after hooks_dir."
  verify
  log "Done. If NVIDIA plugin still shows 'NVML: Unknown Error', ensure nvidia-ctk is installed and CRI-O restarted."
}
main "$@"
