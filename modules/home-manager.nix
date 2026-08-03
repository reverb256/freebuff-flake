{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.freebuff-desktop;
  # Resolve packages from the parent flake (guaranteed via extraSpecialArgs).
  # Not using pkgs directly because the consumer's nixpkgs doesn't include
  # freebuff-desktop unless overlaid.
  fbpkgs = inputs.freebuff-flake.packages.x86_64-linux;
  iconPath = "${config.home.homeDirectory}/.local/share/freebuff/extracted/@codebufffreebuff-desktop.png";
in {
  options.programs.freebuff-desktop = {
    enable = mkEnableOption "Freebuff Desktop — GitHub-native coding-agent orchestrator";
    package = mkOption {
      type = types.package;
      default = fbpkgs.freebuff-desktop;
      description = "The FHS-wrapped freebuff-desktop AppImage (build artifact).";
    };
    wrapper = mkOption {
      type = types.package;
      default = fbpkgs.freebuff-desktop-wrapper;
      description = "Runtime launcher with GPU fixes and auto-update.";
    };
  };

  # NOTE: the freebuff-desktop package is intentionally NOT installed via
  # home.packages here. It is installed through `nix profile install`
  # (Layer 3) so a stale upstream AppImage hash can never block
  # `home-manager switch` builds. This module only manages the declarative
  # launcher (.desktop) and the Stylix-limitation doc; the package/wrapper
  # are expected to already be on PATH via the user nix profile.
  config = mkIf cfg.enable {
    xdg.configFile."freebuff-desktop/STYLIX-LIMITATION.md".text = ''
      # Freebuff Desktop — Stylix theming limitation

      Freebuff does NOT support visible Electron UI theming as of 2026-07-30.
      Verified signals:
      - `~/.config/Freebuff/Preferences` only contains spellcheck settings.
      - The extracted AppImage exposes no `.config`, `settings.json`, or
        env-var hook for colors/theme/accents.
      - No Electron nativeTheme, CSS/theme-color, or accent/primary override
        is exposed by this version.

      What Stylix CAN touch here: only the `.desktop` launcher metadata.
      The .desktop uses an absolute path to the icon inside the runtime-
      extracted AppDir. The running Electron window uses Freebuff's own
      palette and is unaffected by Stylix.
    '';

    xdg.desktopEntries."freebuff-desktop" = {
      name = "Freebuff";
      genericName = "Coding Agent Orchestrator";
      comment = "Freebuff Desktop — GitHub-native coding-agent orchestrator";
      exec = "${cfg.wrapper}/bin/freebuff-desktop-launcher %U";
      icon = iconPath;
      terminal = false;
      type = "Application";
      categories = ["Development" "Utility"];
      mimeType = ["x-scheme-handler/claude"];
    };
  };
}
