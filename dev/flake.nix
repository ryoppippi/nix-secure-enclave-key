{
  description = "Development checks for enclave-key";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    root = {
      url = "..";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "aarch64-darwin"
      ];

      perSystem =
        { config, pkgs, ... }:
        {
          treefmt = {
            projectRoot = ./..;
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
            settings.formatter = {
              actionlint = {
                command = pkgs.lib.getExe pkgs.actionlint;
                includes = [
                  ".github/workflows/*.yaml"
                  ".github/workflows/*.yml"
                ];
              };
              nufmt = {
                command = pkgs.lib.getExe pkgs.nufmt;
                includes = [ "*.nu" ];
              };
            };
          };

          checks.static =
            pkgs.runCommand "enclave-key-static-check"
              {
                nativeBuildInputs = [ pkgs.nushell ];
              }
              ''
                ${pkgs.nushell}/bin/nu --no-config-file ${./../tests/check.nu} ${./..}
                touch "$out"
              '';

          checks.darwin-module =
            (inputs.nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              modules = [
                inputs.root.darwinModules.default
                ({ ... }: {
                  system.stateVersion = 6;
                })
              ];
            }).config.system.build.toplevel;

          devShells.default = pkgs.mkShellNoCC {
            packages = [ config.treefmt.build.wrapper ];
          };
        };
    };
}
