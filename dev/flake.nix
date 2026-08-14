{
  description = "Development checks for nix-secure-enclave-key";

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
        let
          package = inputs.root.packages.${pkgs.system}.default;
        in
        {
          treefmt = {
            projectRoot = ./..;
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              typos = {
                enable = true;
                configFile = "${./../typos.toml}";
              };
            };
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
            pkgs.runCommand "nix-secure-enclave-key-static-check"
              {
                nativeBuildInputs = [ pkgs.nushell ];
              }
              ''
                ${pkgs.nushell}/bin/nu --no-config-file ${./../tests/check.nu} ${./..}
                touch "$out"
              '';

          checks.packaged-e2e =
            pkgs.runCommand "nix-secure-enclave-key-packaged-e2e"
              {
                nativeBuildInputs = [ pkgs.nushell ];
              }
              ''
                ${pkgs.nushell}/bin/nu ${./../tests/e2e.nu} ${./..} --package ${package}/bin/nix-secure-enclave-key
                touch "$out"
              '';

          checks.darwin-module =
            (inputs.nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              modules = [
                inputs.root.darwinModules.default
                ({ ... }: {
                  system.primaryUser = "nobody";
                  system.stateVersion = 6;
                  programs.nix-secure-enclave-key = {
                    enable = true;
                    identities = {
                      git-signing = {
                        keyFile = "~/.ssh/id_git_signing";
                        protection = "none";
                        github.autoAdd = true;
                      };
                      remote-server-x-ssh-login-key = {
                        keyFile = "~/.ssh/id_remote_server_x";
                        protection = "bio";
                      };
                    };
                    signingIdentity = "git-signing";
                  };
                })
              ];
            }).config.system.build.toplevel;

          checks.renovate-config =
            pkgs.runCommand "nix-secure-enclave-key-renovate-config"
              {
                nativeBuildInputs = [ pkgs.renovate ];
              }
              ''
                renovate-config-validator --strict ${./../.github/renovate.json5}
                touch "$out"
              '';

          devShells.default = pkgs.mkShellNoCC {
            packages = [
              config.treefmt.build.wrapper
              pkgs.nixd
              pkgs.nushell
              pkgs.typos
            ];
          };
        };
    };
}
