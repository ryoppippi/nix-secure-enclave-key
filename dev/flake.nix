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
          darwin-system = inputs.nix-darwin.lib.darwinSystem {
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
          };
          darwin-config = darwin-system.config;
          legacy-config-evaluation = builtins.tryEval (
            (inputs.nix-darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              modules = [
                inputs.root.darwinModules.default
                ({ ... }: {
                  system.primaryUser = "nobody";
                  system.stateVersion = 6;
                  programs.nix-secure-enclave-key = {
                    enable = true;
                    keyFile = "~/.ssh/id_legacy";
                    label = "legacy";
                    protection = "none";
                    autoEnsure = true;
                    github.autoAdd = false;
                  };
                })
              ];
            }).config.system.build.toplevel.drvPath
          );
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

          checks.source =
            pkgs.runCommand "nix-secure-enclave-key-source-check"
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

          checks.darwin-module = darwin-system.config.system.build.toplevel;

          checks.darwin-module-config =
            assert pkgs.lib.hasInfix "IdentityFile ~/.ssh/id_git_signing"
              darwin-config.programs.ssh.extraConfig;
            assert pkgs.lib.hasInfix "IdentityFile ~/.ssh/id_remote_server_x"
              darwin-config.programs.ssh.extraConfig;
            assert pkgs.lib.hasInfix "SecurityKeyProvider /usr/lib/ssh-keychain.dylib"
              darwin-config.programs.ssh.extraConfig;
            assert pkgs.lib.hasInfix "--protection none"
              darwin-config.system.activationScripts.postActivation.text;
            assert pkgs.lib.hasInfix "--protection bio"
              darwin-config.system.activationScripts.postActivation.text;
            assert pkgs.lib.hasInfix "--title-prefix git-signing"
              darwin-config.system.activationScripts.postActivation.text;
            assert pkgs.lib.hasInfix "user.signingkey /Users/nobody/.ssh/id_git_signing"
              darwin-config.system.activationScripts.postActivation.text;
            pkgs.runCommand "nix-secure-enclave-key-darwin-module-config" { } "touch $out";

          checks.legacy-config-rejected =
            assert !legacy-config-evaluation.success;
            pkgs.runCommand "nix-secure-enclave-key-legacy-config-rejected" { } "touch $out";

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
