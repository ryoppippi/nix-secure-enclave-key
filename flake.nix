{
  description = "Secure Enclave-backed SSH authentication and Git SSH signing for macOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      packageFor =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.callPackage ./nix/package.nix { };
    in
    {
      packages = forAllSystems (system: {
        default = packageFor system;
      });

      overlays.default = final: _prev: {
        enclave-key = final.callPackage ./nix/package.nix { };
      };

      darwinModules.default = import ./nix/darwin-module.nix { inherit self; };
      homeManagerModules.default = import ./nix/home-manager-module.nix { inherit self; };

      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt-rfc-style);
    };
}
