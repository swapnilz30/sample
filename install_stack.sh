#!/usr/bin/env bash
set -euo pipefail

# =============================
# Config (override via env)
# =============================
: "${JAVA_PACKAGE:=openjdk-17-jdk}"          # e.g., openjdk-11-jdk / openjdk-17-jdk
: "${APT_RETRY:=3}"

log()   { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }
fail()  { log "ERROR: $*"; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      log "Re-executing with sudo..."
      exec sudo --preserve-env=JAVA_PACKAGE,APT_RETRY bash "$0" "$@"
    else
      fail "Run as root or ensure sudo is available."
    fi
  fi
}

apt_update_safe() {
  export DEBIAN_FRONTEND=noninteractive
  for i in $(seq 1 "${APT_RETRY}"); do
    log "apt-get update (attempt $i/${APT_RETRY})"
    if apt-get update -y; then
      return 0
    fi
    sleep 5
  done
  fail "apt-get update failed after ${APT_RETRY} attempts."
}

apt_install_safe() {
  export DEBIAN_FRONTEND=noninteractive
  local pkgs=("$@")
  for i in $(seq 1 "${APT_RETRY}"); do
    log "apt-get install -y ${pkgs[*]} (attempt $i/${APT_RETRY})"
    if apt-get install -y --no-install-recommends "${pkgs[@]}"; then
      return 0
    fi
    sleep 5
  done
  fail "apt-get install failed for: ${pkgs[*]}"
}

enable_start() {
  local svc="$1"
  systemctl enable "${svc}" >/dev/null 2>&1 || true
  systemctl restart "${svc}"
  systemctl --no-pager --full status "${svc}" | sed -n '1,12p' || true
}

verify_cmd() {
  local cmd="$1" msg="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    fail "Command '${cmd}' not found after installation: ${msg}"
  fi
}

main() {
  require_root "$@"

  log "Updating apt metadata..."
  apt_update_safe

  log "Installing prerequisites..."
  apt_install_safe apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common

  log "Installing packages: ${JAVA_PACKAGE}, net-tools, nginx"
  apt_install_safe "${JAVA_PACKAGE}" net-tools nginx

  log "Enabling & starting services (nginx)..."
  enable_start nginx

  log "Verifying installations..."
  verify_cmd java    "OpenJDK not installed?"
  verify_cmd nginx   "NGINX not installed?"
  verify_cmd netstat "net-tools not installed?"

  log "Java version:"
  java -version || true

  log "NGINX version:"
  nginx -v || true

  log "Checking listening port (80 for nginx):"
  (netstat -tulpen 2>/dev/null | grep -E '(:80\\b)') || log "Note: Port 80 may not show if restricted by environment."

  log "All done ✅"
}

main "$@"
