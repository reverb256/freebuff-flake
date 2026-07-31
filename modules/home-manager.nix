{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.freebuff-desktop;
  # Resolve the flake's packages. When consumed via inputs.freebuff-flake.homeModules.default,
  # `pkgs` is the consumer's nixpkgs, which doesn't have freebuff-desktop unless overlaid.
  # Reference them directly from the flake input — but we need `inputs` which is available
  # via extraSpecialArgs. If not available, fall back to pkgs (for backward compat with
  # the now-removed overlay).
  fbpkgs = if builtins ? inputs && builtins.hasAttr "freebuff-flake" inputs
    then inputs.freebuff-flake.packages.${pkgs.stdenv.hostPlatform.system}
    else pkgs;
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

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
      cfg.wrapper
    ];

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
      exec = "${cfg.wrapper}/bin/freebuff-desktop %U";
      icon = iconPath;
      terminal = false;
      type = "Application";
      categories = ["Development" "Utility"];
      mimeType = ["x-scheme-handler/claude"];
    };
  };
}
