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
  security-key-provider = "/usr/lib/ssh-keychain.dylib";
  resolve-key-file =
    keyFile:
    if lib.hasPrefix "~/" keyFile then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" keyFile}"
    else
      keyFile;
  identities = lib.mapAttrsToList (
    name: identity:
    let
      label = if identity.label == null then "${name}-nix-secure-enclave-key" else identity.label;
      title-prefix = name;
    in
    identity
    // {
      inherit name label title-prefix;
      resolvedKeyFile = resolve-key-file identity.keyFile;
    }
  ) cfg.identities;
  signing-identity-name = cfg.signingIdentity;
  signing-identity = lib.findFirst (identity: identity.name == signing-identity-name) null identities;
  has-auto-ensure = lib.any (identity: identity.autoEnsure) identities;
  has-github-auto-add = lib.any (identity: identity.github.autoAdd) identities;
  signing-key-file = if signing-identity == null then "" else signing-identity.resolvedKeyFile;
  ensure-commands = lib.concatMapStringsSep "\n" (
    identity:
    lib.optionalString identity.autoEnsure ''
      ${package}/bin/nix-secure-enclave-key identity ensure \
        --key-file ${lib.escapeShellArg identity.resolvedKeyFile} \
        --label ${lib.escapeShellArg identity.label} \
        --protection ${lib.escapeShellArg identity.protection}
    ''
  ) identities;
  github-add-commands = lib.concatMapStringsSep "\n" (
    identity:
    let
      github-title-argument =
        if identity.github.title == null then
          "--title-prefix ${lib.escapeShellArg identity.title-prefix}"
        else
          "--title ${lib.escapeShellArg identity.github.title}";
    in
    lib.optionalString identity.github.autoAdd ''
      ${package}/bin/nix-secure-enclave-key github add \
        --key-file ${lib.escapeShellArg identity.resolvedKeyFile} \
        --type ${lib.escapeShellArg identity.github.type} \
        ${github-title-argument}
    ''
  ) identities;
  github-activation-dependencies =
    if has-auto-ensure then [ "nix-secure-enclave-key-ensure" ] else [ "writeBoundary" ];
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.identities != { };
        message = "programs.nix-secure-enclave-key.identities must contain at least one identity.";
      }
      {
        assertion = cfg.signingIdentity != null;
        message = "programs.nix-secure-enclave-key.signingIdentity must be set.";
      }
      {
        assertion = signing-identity != null;
        message = "programs.nix-secure-enclave-key.signingIdentity must name one of the configured identities.";
      }
    ];

    home.packages = [ package ] ++ lib.optional has-github-auto-add pkgs.gh;

    programs.ssh = {
      enable = lib.mkDefault true;
      enableDefaultConfig = lib.mkDefault false;
      settings."*" = {
        IdentityFile = map (identity: identity.keyFile) identities;
        SecurityKeyProvider = security-key-provider;
      };
    };

    programs.git = {
      enable = lib.mkDefault true;
      signing = {
        key = signing-key-file;
        signByDefault = cfg.signByDefault;
        signer = "${package}/bin/nix-secure-enclave-key-git-sign";
      };
      settings = {
        gpg.format = "ssh";
        gpg.ssh.program = "${package}/bin/nix-secure-enclave-key-git-sign";
        user.signingkey = signing-key-file;
      };
    };

    home.activation.nix-secure-enclave-key-ensure = lib.mkIf has-auto-ensure (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ensure-commands
    );

    home.activation.nix-secure-enclave-key-github-add = lib.mkIf has-github-auto-add (
      lib.hm.dag.entryAfter github-activation-dependencies ''
        export PATH="${pkgs.gh}/bin:$PATH"
        ${github-add-commands}
      ''
    );
  };
}
