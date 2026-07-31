# Freebuff Desktop — Nix flake

[Freebuff Desktop](https://freebuff.com) packaged as a Nix flake for NixOS.
Fetches the latest upstream AppImage directly from freebuff.com and wraps it
with `appimageTools.wrapType2` for proper NixOS integration (FHS environment,
system library compatibility, Wayland/Ozone support).

## Usage

### As a flake input

```nix
# flake.nix
{
  inputs = {
    freebuff-desktop.url = "github:reverb256/freebuff-desktop-nixos";
    freebuff-desktop.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

### System-wide

```nix
# configuration.nix
environment.systemPackages = [
  inputs.freebuff-desktop.packages.${system}.freebuff-desktop
];
```

### Home Manager

```nix
home.packages = [
  inputs.freebuff-desktop.packages.${system}.freebuff-desktop
];
```

### One-shot

```bash
nix run github:reverb256/freebuff-desktop-nixos
```

### Update the hash manually

```bash
nix develop .# -c scripts/bump-version.sh
```

## CI/CD

A scheduled GitHub Action runs every Monday at 4am UTC. If a new version is
detected on the upstream API, it opens a PR with the updated version and hash.
Merge the PR to publish the updated package.

## Version tracking

The upstream version is read from the filename
(`Freebuff-{X.Y.Z}-linux-x86_64.AppImage`) at the end of the download
redirect chain. The SRI hash is computed from the downloaded content.
