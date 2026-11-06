{
  lib,
  appimageTools,
  fetchurl,
}:
# Freebuff Desktop — Codebuff's free coding-agent GUI (Electron AppImage).
#
# NixOS package wrapping the desktop AppImage published at
#   https://github.com/CodebuffAI/codebuff-community/releases
# (tag freebuff-desktop-v<version>) — the same artifact upstream's
# https://freebuff.com/api/desktop/download/linux endpoint redirects to.
#
# The URL is built from `version` on purpose: the freebuff.com endpoint is a
# floating 302 whose payload changes on every release (and since 2026-11 it
# serves a .deb on Linux, not the AppImage). Pinning fetchurl to that endpoint
# makes the build irreproducible — the pinned sha256 stops matching and
# `nix build` fails — so we pin the versioned release asset instead.
#
# Best-practice Electron-AppImage-on-NixOS packaging (pattern from nixpkgs
# pkgs/by-name/os/osu-lazer-bin):
#   - extraBwrapArgs mount the Wayland socket, /dev/dri, and EGL external
#     platform dir so Electron can reach the real compositor + GPU.
#   - extraPkgs provide wayland/vulkan/libdrm/libglvnd so the Electron GPU
#     process doesn't fall back to a broken renderer inside the sandbox.
#   - NOT forcing --ozone-platform=wayland inside the package: forcing raw
#     Wayland inside bwrap + NVIDIA HW accel on kernel 6.12+ is the known
#     system-hang (nixpkgs#382612). ELECTRON_OZONE_PLATFORM_HINT is left to
#     the launcher (freebuff-desktop-latest), which can choose Wayland or
#     XWayland without wedging the compositor.
#
# Auto-bumped by .github/workflows/update.yml when upstream ships a new
# release: scripts/bump-version.sh rewrites `version` + `sha256` below.
let
  pname = "freebuff-desktop";
  version = "0.0.200";
  src = fetchurl {
    url = "https://github.com/CodebuffAI/codebuff-community/releases/download/freebuff-desktop-v${version}/Freebuff-${version}-linux-x86_64.AppImage";
    # Auto-bumped — do not edit manually. Run: scripts/bump-version.sh
    sha256 = "sha256-BKyKW1eUlMs/atVLL07agoceaHNhCZBvdQuiF2fsEGw=";
  };
in
appimageTools.wrapType2 {
  inherit pname src version;

  # Libraries Electron's GPU/GL stack needs inside the FHS sandbox.
  extraPkgs = pkgs:
    with pkgs; [
      bash
      glib
      nss
      nspr
      libGL
      libglvnd
      fontconfig
      freetype
      alsa-lib
      cups
      dbus
      expat
      libxshmfence
      # Wayland / GPU / Vulkan deps (best-practice additions)
      wayland
      libdrm
      vulkan-loader
      libxkbcommon
      libgbm
      pango
      cairo
      gtk3
      mesa
      # Xorg / Window-system deps
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxcb
      xorg.libxkbfile
      xorg.libXScrnSaver
      xorg.libXinerama
      xorg.libXtst
      xorg.libXi
    ];

  # Mount spelling that lets Electron reach the compositor + GPU through bwrap.
  # "--ro-bind-try" is tolerant: it only binds if the source exists, so the
  # package also works on headless builders.
  extraBwrapArgs = [
    "--ro-bind-try /etc/egl/egl_external_platform.d /etc/egl/egl_external_platform.d"
    "--ro-bind-try /dev/dri /dev/dri"
  ];
}
