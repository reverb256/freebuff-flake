{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.freebuff-desktop;
  # Icon lives inside the runtime-extracted AppDir. The wrapper guarantees
  # extraction on first launch, so this path exists after the first run.
  iconPath = "${config.home.homeDirectory}/.local/share/freebuff/extracted/@codebufffreebuff-desktop.png";
in {
  options.programs.freebuff-desktop = {
    enable = mkEnableOption "Freebuff Desktop — GitHub-native coding-agent orchestrator";
    package = mkOption {
      type = types.package;
      default = pkgs.freebuff-desktop;
      description = "The FHS-wrapped freebuff-desktop AppImage (build artifact).";
    };
    wrapper = mkOption {
      type = types.package;
      default = pkgs.freebuff-desktop-wrapper;
      description = "Runtime launcher with GPU fixes and auto-update.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package   # FHS-wrapped AppImage (appimageTools.wrapType2)
      cfg.wrapper   # Runtime launcher (GPU, updates, extraction)
    ];

    # Stylix limitation — see STYLIX-LIMITATION.md
    # Freebuff's Electron UI has no theme hooks. The launcher icon is a
    # runtime-extracted PNG, not a Stylix-themed icon.
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

    # .desktop entry — points to the runtime wrapper, not the Nix package.
    # The wrapper handles GPU library injection, updates, and extraction.
    xdg.desktopEntries."freebuff-desktop" = {
      name = "Freebuff";
      genericName = "Coding Agent Orchestrator";
      comment = "Freebuff Desktop — GitHub-native coding-agent orchestrator";
      exec = "${cfg.wrapper}/bin/freebuff-desktop %U";
      icon = iconPath;
      terminal = false;
      type = "Application";
      categories = ["Development" "Utility"];
      startupWMClass = "Freebuff";
    };
  };
}
