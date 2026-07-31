#!/usr/bin/env bash
# Freebuff Desktop — Professional NixOS AppImage Wrapper
#
# Features:
#   - Automatic updates with 24h throttle
#   - Robust extraction (appimage-extract → 7z fallback)
#   - NVIDIA GPU library injection via LD_PRELOAD (bypasses $ORIGIN RPATH)
#   - Full Wayland/Ozone display support
#   - --health self-diagnostic
#   - Declarative-friendly: installed via freebuff-flake
#
set -euo pipefail

# ── Configuration ───────────────────────────────────────────────────
readonly APP_DIR="${HOME}/.local/share/freebuff"
readonly APP_IMAGE="${APP_DIR}/Freebuff-x86_64.AppImage"
readonly EXTRACTED_DIR="${APP_DIR}/extracted"
readonly UPDATE_FILE="${APP_DIR}/.last-update-check"
readonly UPDATE_INTERVAL=$((24 * 60 * 60))
readonly API_URL="https://freebuff.com/api/desktop/download/linux"
readonly FALLBACK_URL="https://github.com/CodebuffAI/codebuff-community/releases/latest/download/Freebuff-0.0.18-linux-x86_64.AppImage"
readonly VERSION="@version@"  # replaced by Nix build

# ── I/O helpers ─────────────────────────────────────────────────────
log()  { echo "[freebuff] $*"; }
warn() { echo "[freebuff] ⚠ $*" >&2; }
err()  { echo "[freebuff] ✗ $*" >&2; exit 1; }

cleanup() {
  local ec=$?
  [ $ec -ne 0 ] && [ $ec -ne 143 ] && err "exited with status $ec"
  exit $ec
}
trap cleanup EXIT

# ── Health diagnostic ───────────────────────────────────────────────
health_check() {
  local status=0
  local version_detected=""
  local extracted_date=""
  local gpu_driver=""
  local gpu_status=""
  local nvidia_ver=""

  # AppImage version
  if [ -f "$APP_IMAGE" ]; then
    local appimage_mtime
    appimage_mtime=$(stat -c '%y' "$APP_IMAGE" 2>/dev/null || echo "unknown")
    version_detected=$(strings "$APP_IMAGE" 2>/dev/null | grep -Eo 'Freebuff [0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
  fi

  # Extraction status
  if [ -x "${EXTRACTED_DIR}/AppRun" ]; then
    extracted_date=$(stat -c '%y' "${EXTRACTED_DIR}/.appimage-mtime" 2>/dev/null || echo "unknown")
  fi

  # GPU driver
  if [ -L "/run/opengl-driver" ]; then
    local drv
    drv=$(readlink -f /run/opengl-driver)
    if [ -d "$drv/lib" ]; then
      nvidia_ver=$(find "$drv/lib" -maxdepth 1 -name 'libEGL_nvidia*' -exec basename {} \; 2>/dev/null | head -1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    fi
  fi

  # LD_PRELOAD status
  if [ -n "${LD_PRELOAD:-}" ]; then
    gpu_status="LD_PRELOAD active"
  elif [ -f /run/opengl-driver/lib/libEGL.so ]; then
    gpu_status="system libs available (no LD_PRELOAD)"
  else
    gpu_status="bundled libEGL only (may fail)"
    status=1
  fi

  # Stylix
  local stylix_file="${HOME}/.config/freebuff-desktop/STYLIX-LIMITATION.md"
  local stylix_status="not applicable"
  [ -f "$stylix_file" ] && stylix_status="limitation documented"

  # Last crash
  local crash_log="${APP_DIR}/crash-reports"
  local crash_status="none"
  [ -d "$crash_log" ] && [ "$(ls -A "$crash_log" 2>/dev/null)" ] && crash_status="present ($(ls "$crash_log" | wc -l) reports)"

  cat <<HEALTH
Freebuff Desktop Health
  Package version:  ${VERSION}
  AppImage runtime: ${version_detected:-not downloaded}
  Extracted:        ${extracted_date:-not extracted}
  GPU driver:       NVIDIA ${nvidia_ver:-unknown}
  GPU resolution:   ${gpu_status}
  Stylix:           ${stylix_status}
  Last crash:       ${crash_status}
  Update throttle:  $(( (UPDATE_INTERVAL - ($(date +%s) - $(stat -c %Y "$UPDATE_FILE" 2>/dev/null || echo 0))) / 3600 ))h until next check
HEALTH
  exit $status
}

# ── Update / download ───────────────────────────────────────────────
handle_update() {
  [ ! -f "$APP_IMAGE" ] && return 0

  local force=${1:-false}
  if ! $force && [ -f "$UPDATE_FILE" ]; then
    local last_check
    last_check=$(stat -c %Y "$UPDATE_FILE" 2>/dev/null || echo 0)
    [ $(( $(date +%s) - last_check )) -lt $UPDATE_INTERVAL ] && return 0
  fi

  log "checking for updates …"
  chmod +x "$APP_IMAGE" 2>/dev/null || true
  if "$APP_IMAGE" --appimage-update 2>/dev/null; then
    log "update applied"
    # Touch the AppImage mtime so extraction detects it
    touch "$APP_IMAGE"
  else
    warn "update check failed (non-fatal)"
  fi
  touch "$UPDATE_FILE"
}

download_appimage() {
  [ -f "$APP_IMAGE" ] && return 0

  log "downloading Freebuff …"
  mkdir -p "$APP_DIR"

  local redirect_url
  redirect_url=$(curl -sSLI -o /dev/null -w '%{url_effective}' "$API_URL" 2>/dev/null || true)
  local dl_url="${redirect_url:-$FALLBACK_URL}"

  curl -sSL -o "$APP_IMAGE" "$dl_url" || err "download failed — check network"
  chmod +x "$APP_IMAGE"
  log "downloaded → ${APP_IMAGE}"
}

# ── Extraction ──────────────────────────────────────────────────────
extract_appimage() {
  # Re-extract when the AppImage file is newer than the marker
  if [ -x "${EXTRACTED_DIR}/AppRun" ] && [ -x "${EXTRACTED_DIR}/@codebufffreebuff-desktop" ]; then
    if [ -f "$APP_IMAGE" ] && [ "${EXTRACTED_DIR}/.appimage-mtime" -nt "$APP_IMAGE" ] 2>/dev/null; then
      return 0
    fi
    log "AppImage changed — re-extracting"
  fi

  log "extracting Freebuff …"
  rm -rf "$EXTRACTED_DIR"
  mkdir -p "$EXTRACTED_DIR"

  if (cd "$EXTRACTED_DIR" && "$APP_IMAGE" --appimage-extract >/dev/null 2>&1); then
    [ -d "${EXTRACTED_DIR}/squashfs-root" ] && {
      find "${EXTRACTED_DIR}/squashfs-root" -mindepth 1 -maxdepth 1 -exec mv {} "$EXTRACTED_DIR/" \;
      rm -rf "${EXTRACTED_DIR}/squashfs-root"
    }
  elif command -v 7z >/dev/null 2>&1; then
    log "using 7z fallback extraction …"
    7z x "$APP_IMAGE" -o"$EXTRACTED_DIR" -y >/dev/null 2>&1 || err "7z extraction failed"
  else
    err "no extraction method available — install 7z / p7zip"
  fi

  chmod +x "$EXTRACTED_DIR/AppRun" \
         "$EXTRACTED_DIR/@codebufffreebuff-desktop" 2>/dev/null || true

  touch -r "$APP_IMAGE" "${EXTRACTED_DIR}/.appimage-mtime" 2>/dev/null || true
  log "extraction complete"
}

# ── GPU library injection ───────────────────────────────────────────
resolve_gpu_libs() {
  local -a preload=()
  local search_dirs=(
    "/run/opengl-driver/lib"
    "/run/current-system/sw/lib"
  )

  local nvidia_driver=""
  [ -L "/run/opengl-driver" ] && nvidia_driver=$(readlink -f /run/opengl-driver)
  [ -n "$nvidia_driver" ] && search_dirs=("${nvidia_driver}/lib" "${search_dirs[@]}")

  for lib in libEGL.so libGLESv2.so libvulkan.so.1; do
    for d in "${search_dirs[@]}"; do
      if [ -f "$d/$lib" ]; then
        preload+=("$d/$lib")
        break
      fi
    done
  done

  local IFS=':'
  echo "${preload[*]}"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  # --health: self-diagnostic
  if [ $# -gt 0 ] && [ "$1" = "--health" ]; then
    health_check
  fi

  # --update: force update check
  if [ $# -gt 0 ] && [ "$1" = "--update" ]; then
    download_appimage
    touch -t 197001010000 "$UPDATE_FILE" 2>/dev/null || rm -f "$UPDATE_FILE"
    handle_update true
    log "update complete"
    exit 0
  fi

  # Normal launch
  download_appimage
  handle_update
  extract_appimage

  local preload_libs
  preload_libs=$(resolve_gpu_libs)
  [ -z "$preload_libs" ] && warn "system GPU libs not found — expect rendering issues"

  local nvidia_driver=""
  [ -L "/run/opengl-driver" ] && nvidia_driver=$(readlink -f /run/opengl-driver)
  [ -L "/run/opengl-driver" ] && export NVIDIA_DRIVER="$nvidia_driver"

  # GLVND EGL vendor config
  local egl_vendor_dir="${nvidia_driver}/share/glvnd/egl_vendor.d"
  [ -d "$egl_vendor_dir" ] && __EGL_VENDOR_LIBRARY_FILENAMES=""
  for f in "$egl_vendor_dir"/10_nvidia.json "$egl_vendor_dir"/50_mesa.json; do
    [ -f "$f" ] && __EGL_VENDOR_LIBRARY_FILENAMES="${__EGL_VENDOR_LIBRARY_FILENAMES:+$__EGL_VENDOR_LIBRARY_FILENAMES:}$f"
  done
  [ -n "$__EGL_VENDOR_LIBRARY_FILENAMES" ] && export __EGL_VENDOR_LIBRARY_FILENAMES

  export LIBGL_DRIVERS_PATH="${nvidia_driver:+$nvidia_driver/lib/dri:}/run/current-system/sw/lib/dri"
  export VK_ICD_FILENAMES="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
  export LD_LIBRARY_PATH="${EXTRACTED_DIR}:${nvidia_driver:+$nvidia_driver/lib:}/run/current-system/sw/lib:/run/current-system/sw/share/nix-ld/lib:${LD_LIBRARY_PATH:-}"
  [ -n "$preload_libs" ] && export LD_PRELOAD="${preload_libs}:${LD_PRELOAD:-}"

  export NIXOS_OZONE_WL=1
  export ELECTRON_OZONE_PLATFORM_HINT=wayland
  export MOZ_ENABLE_WAYLAND=1
  export GDK_BACKEND=wayland

  cd "$EXTRACTED_DIR"
  log "launching Freebuff v${VERSION} …"
  exec ./@codebufffreebuff-desktop \
    --no-sandbox \
    --disable-gpu-sandbox \
    "$@"
}

main "$@"
