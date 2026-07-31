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
      in
      {
        packages = {
          freebuff-desktop = pkgs.callPackage ./pkgs/freebuff-desktop.nix { };
        };
        defaultPackage = self.packages.${system}.freebuff-desktop;

        apps = {
          freebuff-desktop = flake-utils.lib.mkApp {
            drv = self.packages.${system}.freebuff-desktop;
          };
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
      });
}
