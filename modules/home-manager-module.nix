{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.nix-secure-enclave-key;
  package = self.packages.${pkgs.system}.default;
  securityKeyProvider = "/usr/lib/ssh-keychain.dylib";
  keyFile =
    if lib.hasPrefix "~/" cfg.keyFile then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" cfg.keyFile}"
    else
      cfg.keyFile;
in
{
  options.programs.nix-secure-enclave-key = {
    enable = lib.mkEnableOption "nix-secure-enclave-key";

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/id_enclave_key";
      description = "Path to the non-secret SSH stub; the public key is read from the matching .pub file.";
    };

    label = lib.mkOption {
      type = lib.types.str;
      default = "nix-secure-enclave-key";
      description = "Label used when creating the CryptoTokenKit identity.";
    };

    protection = lib.mkOption {
      type = lib.types.enum [
        "none"
        "bio"
      ];
      default = "none";
      description = "Secure Enclave protection mode. none creates the identity without biometric protection; bio requests biometric protection and may require Touch ID when the identity is created or the key is used.";
    };

    autoEnsure = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ensure the local identity and SSH stub during user activation; GitHub registration is never run here.";
    };

    signByDefault = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether Git commits should be SSH-signed by default.";
    };

    github.autoAdd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Register the public key with GitHub during user activation; disabled by default because this writes to GitHub.";
    };

    github.type = lib.mkOption {
      type = lib.types.enum [
        "signing"
        "authentication"
        "both"
      ];
      default = "both";
      description = "GitHub key purpose to register when autoAdd is enabled.";
    };

    github.title = lib.mkOption {
      type = lib.types.str;
      default = "nix-secure-enclave-key";
      description = "Title to use when registering the public key with GitHub.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ] ++ lib.optional cfg.github.autoAdd pkgs.gh;

    programs.ssh = {
      enable = lib.mkDefault true;
      matchBlocks."*" = {
        identityFile = [ keyFile ];
        extraOptions.SecurityKeyProvider = securityKeyProvider;
      };
    };

    programs.git = {
      enable = lib.mkDefault true;
      signing = {
        key = keyFile;
        signByDefault = cfg.signByDefault;
        signer = "${package}/bin/nix-secure-enclave-key-git-sign";
      };
      extraConfig = {
        "gpg.format" = "ssh";
        "gpg.ssh.program" = "${package}/bin/nix-secure-enclave-key-git-sign";
        "user.signingkey" = keyFile;
      };
    };

    home.activation.nix-secure-enclave-key-ensure = lib.mkIf cfg.autoEnsure (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${package}/bin/nix-secure-enclave-key identity ensure \
          --key-file ${lib.escapeShellArg keyFile} \
          --label ${lib.escapeShellArg cfg.label} \
          --protection ${lib.escapeShellArg cfg.protection}
      ''
    );

    home.activation.nix-secure-enclave-key-github-add = lib.mkIf cfg.github.autoAdd (
      lib.hm.dag.entryAfter (lib.optional cfg.autoEnsure "nix-secure-enclave-key-ensure") ''
        ${package}/bin/nix-secure-enclave-key github add \
          --key-file ${lib.escapeShellArg keyFile} \
          --type ${lib.escapeShellArg cfg.github.type} \
          --title ${lib.escapeShellArg cfg.github.title}
      ''
    );
  };
}
