#!/usr/bin/env bash
set -euo pipefail

# ---
# Docker + KinD installer for Ubuntu
# Tested on Ubuntu 20.04/22.04/24.04
# This script:
#  1) updates apt and installs prerequisites
#  2) adds Docker's official APT repo
#  3) installs Docker Engine (docker-ce, docker-ce-cli, containerd.io)
#  4) enables & starts Docker
#  5) adds current user to the docker group (optional)
#  6) installs KinD (latest) to /usr/local/bin
#  7) verifies installation
# ---

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command '$1' not found. Please install it and re-run."; exit 1
  fi
}

install_kubectl() {
  log "Installing kubectl (latest stable)..."
  sudo apt update
  sudo apt install -y curl
  KUBECTL_VERSION=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  log "kubectl installed. Version:"
  kubectl version --client || true
}

install_helm() {
  log "Installing Helm (latest)..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  log "Helm installed. Version:"
  helm version || true
}

add_helm_repos() {
  log "Adding Black Duck Helm repo and updating..."
  helm repo add bd-repo https://repo.blackduck.com/cloudnative
  helm repo update
  helm search repo bd-repo/cnc
}

main() {
  check_ubuntu
  setup_arch_and_codename
  update_and_install_prereqs
  add_docker_repo
  install_docker
  enable_and_start_docker
  verify_docker_active
  show_docker_version
  add_user_to_docker_group
  install_kind
  show_kind_version
  install_kubectl
  install_helm
  add_helm_repos
  verify_docker_run
  show_next_steps
  log "All done."
}

check_ubuntu() {
  if ! grep -qi "ubuntu" /etc/os-release; then
    err "This script is intended for Ubuntu. Aborting."; exit 1
  fi
}

setup_arch_and_codename() {
  ARCH=$(dpkg --print-architecture)
  CODENAME=$(lsb_release -cs)
  log "Using architecture: ${ARCH}, codename: ${CODENAME}"
}

update_and_install_prereqs() {
  log "Updating system and installing prerequisites..."
  sudo apt update
  sudo apt install -y ca-certificates curl gnupg lsb-release
}

add_docker_repo() {
  log "Configuring Docker's official GPG key and APT repository..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" |
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
}

install_docker() {
  log "Installing Docker Engine packages..."
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
}

enable_and_start_docker() {
  log "Enabling and starting Docker service..."
  sudo systemctl enable docker
  sudo systemctl start docker
}

verify_docker_active() {
  if ! sudo systemctl is-active --quiet docker; then
    err "Docker service is not active. Check 'systemctl status docker'"; exit 1
  fi
}

show_docker_version() {
  log "Docker is active. Version:"
  docker --version || true
}

add_user_to_docker_group() {
  CURRENT_USER=${SUDO_USER:-$USER}
  if id -nG "$CURRENT_USER" 2>/dev/null | grep -qw docker; then
    warn "User '$CURRENT_USER' is already in the 'docker' group."
  else
    log "Adding user '$CURRENT_USER' to 'docker' group (you'll need to log out/in)..."
    sudo usermod -aG docker "$CURRENT_USER"
  fi
}

install_kind() {
  log "Installing KinD (latest) for Linux ${ARCH}..."
  KIND_URL_ARCH="amd64"
  case "${ARCH}" in
    amd64) KIND_URL_ARCH="amd64" ;;
    arm64) KIND_URL_ARCH="arm64" ;;
    armhf|arm) KIND_URL_ARCH="arm" ;;
    *) warn "Unknown arch '${ARCH}', defaulting to amd64"; KIND_URL_ARCH="amd64" ;;
  esac
  TMP_KIND=$(mktemp)
  curl -L -o "$TMP_KIND" "https://kind.sigs.k8s.io/dl/latest/kind-linux-${KIND_URL_ARCH}"
  chmod +x "$TMP_KIND"
  sudo mv "$TMP_KIND" /usr/local/bin/kind
}

show_kind_version() {
  log "KinD installed. Version:"
  kind version || true
}

verify_docker_run() {
  log "Verifying Docker can run containers..."
  if docker run --rm hello-world >/dev/null 2>&1; then
    log "Docker container run check: OK"
  else
    warn "Could not run hello-world. This can be due to needing to re-login after docker group change."
  fi
}

show_next_steps() {
  cat << 'EOT'

Next steps:
  1) If you were just added to the 'docker' group, please log out and log back in (or run: newgrp docker) so 'docker' works without sudo.
  2) Create a KinD cluster:
       kind create cluster
     To delete:
       kind delete cluster

Optional: Multi-node cluster example (save as kind-cluster.yaml):
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  nodes:
    - role: control-plane
    - role: worker
    - role: worker
Then run:
  kind create cluster --name dev --config kind-cluster.yaml

EOT
}

main "$@"
