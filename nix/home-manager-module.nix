{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.enclave-key;
  package = self.packages.${pkgs.system}.default;
  keyFile =
    if lib.hasPrefix "~/" cfg.keyFile then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" cfg.keyFile}"
    else
      cfg.keyFile;
in
{
  options.programs.enclave-key = {
    enable = lib.mkEnableOption "enclave-key";

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/id_enclave_key";
      description = "Path to the non-secret SSH stub and its public key.";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "enclave-key";
      description = "Label used when creating the CryptoTokenKit identity.";
    };

    protection = lib.mkOption {
      type = lib.types.enum [
        "none"
        "bio"
      ];
      default = "none";
      description = "Secure Enclave private-key protection mode.";
    };

    autoEnsure = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ensure the local identity and SSH stub during user activation.";
    };

    signByDefault = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Sign Git commits by default with the SSH signing key.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    programs.ssh = {
      enable = lib.mkDefault true;
      matchBlocks."github.com" = {
        identityFile = [ keyFile ];
        extraOptions.SecurityKeyProvider = "/usr/lib/ssh-keychain.dylib";
      };
    };

    programs.git = {
      enable = lib.mkDefault true;
      signing = {
        key = keyFile;
        signByDefault = cfg.signByDefault;
        signer = "${package}/bin/enclave-key-git-sign";
      };
      extraConfig = {
        "gpg.format" = "ssh";
        "gpg.ssh.program" = "${package}/bin/enclave-key-git-sign";
        "user.signingkey" = keyFile;
      };
    };

    home.activation.enclave-key-ensure = lib.mkIf cfg.autoEnsure (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${package}/bin/enclave-key identity ensure \
          --key-file ${lib.escapeShellArg keyFile} \
          --label ${lib.escapeShellArg cfg.label} \
          --protection ${lib.escapeShellArg cfg.protection}
      ''
    );
  };
}
