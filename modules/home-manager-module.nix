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
  imports = [ ./options.nix ];

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
