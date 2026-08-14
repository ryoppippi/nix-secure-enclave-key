{
  description = "Nix-packaged Secure Enclave-backed SSH authentication and Git SSH signing for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
      ];

      perSystem =
        { pkgs, ... }:
        {
          packages.default = pkgs.callPackage ./package.nix { };
        };

      flake = {
        overlays.default = final: _prev: {
          nix-secure-enclave-key = final.callPackage ./package.nix { };
        };

        darwinModules.default = import ./modules/darwin-module.nix { inherit self; };
        homeManagerModules.default = import ./modules/home-manager-module.nix { inherit self; };
      };
    };
}
