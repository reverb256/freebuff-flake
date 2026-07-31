# Freebuff Desktop — Nix flake

[Freebuff Desktop](https://freebuff.com) packaged as a Nix flake for NixOS.
Fetches the latest upstream AppImage via `appimageTools.wrapType2` and ships
a runtime wrapper with GPU library injection, auto-update, and diagnostics.

## Quick start

```bash
nix run github:reverb256/freebuff-flake
```

## As a flake input in your NixOS config

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    freebuff-flake.url = "github:reverb256/freebuff-flake";
    freebuff-flake.inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

### System-wide

```nix
environment.systemPackages = [
  inputs.freebuff-flake.packages.${system}.freebuff-desktop
  inputs.freebuff-flake.packages.${system}.freebuff-desktop-wrapper
];
```

### Home Manager (recommended — includes .desktop entry)

```nix
# home.nix
{ inputs, ... }: {
  imports = [ inputs.freebuff-flake.homeModules.default ];
  programs.freebuff-desktop.enable = true;
}
```

This installs:
- The FHS-wrapped AppImage (`.freebuff-desktop`)
- The runtime wrapper with GPU fixes (`freebuff-desktop` in PATH)
- A `.desktop` launcher entry
- Stylix limitation documentation

## Components

| Output | Type | What |
|--------|------|------|
| `packages.freebuff-desktop` | `appimageTools.wrapType2` | FHS-wrapped AppImage build artifact |
| `packages.freebuff-desktop-wrapper` | Nix script derivation | Runtime launcher (GPU, updates, extraction, `--health`) |
| `homeModules.default` | Home Manager module | `.desktop` entry, Stylix docs, package wiring |

## Diagnostics

```bash
freebuff-desktop --health
```

Outputs version, extraction state, GPU driver status, last crash info, and update throttle remaining.

## Auto-update

- **Fast ring** (runtime): wrapper checks `--appimage-update` every 24h on launch
- **Stable ring** (Nix): GitHub Action runs weekly, bumps the pinned hash, opens a PR
- Both rings converge: fast ring re-extracts when the AppImage mtime changes

## Version bump

```bash
nix develop .# -c scripts/bump-version.sh
```

Or wait for the Monday 4am UTC GitHub Action to open an automated PR.

## Stylix

Freebuff's Electron UI has **no theme hooks**. Stylix controls only the `.desktop`
launcher metadata. See `~/.config/freebuff-desktop/STYLIX-LIMITATION.md` for details.
