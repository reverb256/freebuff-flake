{
  description = "Freebuff Desktop — GitHub-native coding-agent orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        freebuff-desktop = pkgs.callPackage ./pkgs/freebuff-desktop.nix { };
        freebuff-desktop-wrapper = pkgs.callPackage ./pkgs/freebuff-wrapper.nix {
          inherit freebuff-desktop;
        };
      in
      {
        packages = {
          inherit freebuff-desktop freebuff-desktop-wrapper;
        };
        defaultPackage = freebuff-desktop;

        apps.freebuff-desktop = flake-utils.lib.mkApp {
          drv = freebuff-desktop-wrapper;
        };
        defaultApp = self.apps.${system}.freebuff-desktop;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            curl
            nix
            coreutils
            gnused
          ];
        };
      }) // {
      # Home-manager module (importable by nixos-config)
      homeModules.default = import ./modules/home-manager.nix;
    };
}
