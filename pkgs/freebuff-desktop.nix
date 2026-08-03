{
  lib,
  appimageTools,
  fetchurl,
}:
# Freebuff Desktop — Codebuff's free coding-agent GUI (Electron AppImage).
#
# NixOS package wrapping v0.0.42 of the upstream AppImage.
# Auto-bumped by .github/workflows/update.yml when upstream ships a new release.
let
  pname = "freebuff-desktop";
  src = fetchurl {
    url = "https://freebuff.com/api/desktop/download/linux";
    # Auto-bumped — do not edit manually. Run: nix run .#update-hash
    sha256 = "sha256-U/T6NEsA8DhFiktR8FOsxiPxHnBrW+XGlhyfd26gedg=";
  };
in
appimageTools.wrapType2 {
  inherit pname src;
  version = "0.0.42";

  extraPkgs = pkgs:
    with pkgs; [
      bash
      glib
      nss
      nspr
      libGL
      fontconfig
      freetype
      alsa-lib
      cups
      dbus
      expat
      libxshmfence
      # Xorg / Wayland / GPU deps
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxcb
      xorg.libxkbfile
      xorg.libXScrnSaver
    ];
}
