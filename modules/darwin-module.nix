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
  primaryUser = config.system.primaryUser;
  primaryUserHome = lib.optionalString (primaryUser != null) config.system.primaryUserHome;
  resolve-key-file =
    keyFile:
    if primaryUser != null && lib.hasPrefix "~/" keyFile then
      "${primaryUserHome}/${lib.removePrefix "~/" keyFile}"
    else
      keyFile;
  legacy-identities = {
    default = {
      keyFile = cfg.keyFile;
      label = cfg.label;
      protection = cfg.protection;
      autoEnsure = cfg.autoEnsure;
      github = cfg.github;
    };
  };
  configured-identities = if cfg.identities == { } then legacy-identities else cfg.identities;
  identities = lib.mapAttrsToList (
    name: identity:
    let
      label = if identity.label == null then "${name}-nix-secure-enclave-key" else identity.label;
      github-title =
        if identity.github.title == null then "${name}-nix-secure-enclave-key" else identity.github.title;
    in
    identity
    // {
      inherit name label;
      github = identity.github // {
        title = github-title;
      };
      resolvedKeyFile = resolve-key-file identity.keyFile;
    }
  ) configured-identities;
  signing-identity-name = if cfg.identities == { } then "default" else cfg.signingIdentity;
  signing-identity = lib.findFirst (identity: identity.name == signing-identity-name) null identities;
  has-auto-ensure = lib.any (identity: identity.autoEnsure) identities;
  has-github-auto-add = lib.any (identity: identity.github.autoAdd) identities;
  signing-key-file =
    if signing-identity == null then resolve-key-file cfg.keyFile else signing-identity.resolvedKeyFile;
  run-as-primary-user =
    command: "/usr/bin/sudo --user=${lib.escapeShellArg primaryUser} --set-home ${command}";
  ensure-commands = lib.concatMapStringsSep "\n" (
    identity:
    lib.optionalString identity.autoEnsure ''
      ${run-as-primary-user "${package}/bin/nix-secure-enclave-key"} identity ensure \
        --key-file ${lib.escapeShellArg identity.resolvedKeyFile} \
        --label ${lib.escapeShellArg identity.label} \
        --protection ${lib.escapeShellArg identity.protection}
    ''
  ) identities;
  github-add-commands = lib.concatMapStringsSep "\n" (
    identity:
    lib.optionalString identity.github.autoAdd ''
      ${run-as-primary-user "/usr/bin/env"} \
        ${lib.escapeShellArg "PATH=${pkgs.gh}/bin:/usr/bin:/bin:/usr/sbin:/sbin"} \
        ${package}/bin/nix-secure-enclave-key github add \
          --key-file ${lib.escapeShellArg identity.resolvedKeyFile} \
          --type ${lib.escapeShellArg identity.github.type} \
          --title ${lib.escapeShellArg identity.github.title}
    ''
  ) identities;
  ssh-identity-files = lib.concatMapStringsSep "\n" (
    identity: "  IdentityFile ${identity.keyFile}"
  ) identities;
  ssh-extra-config =
    lib.concatStringsSep "\n" [
      "Host *"
      ssh-identity-files
      "  SecurityKeyProvider /usr/lib/ssh-keychain.dylib"
    ]
    + "\n";
  activation = lib.optionalString (primaryUser != null) ''
    ${ensure-commands}

    ${lib.optionalString (signing-identity != null) ''
      ${run-as-primary-user "/usr/bin/git"} config --global gpg.format ssh
      ${run-as-primary-user "/usr/bin/git"} config --global user.signingkey ${lib.escapeShellArg signing-key-file}
      ${run-as-primary-user "/usr/bin/git"} config --global gpg.ssh.program ${lib.escapeShellArg "${package}/bin/nix-secure-enclave-key-git-sign"}
      ${run-as-primary-user "/usr/bin/git"} config --global commit.gpgsign ${
        if cfg.signByDefault then "true" else "false"
      }
    ''}

    ${github-add-commands}
  '';
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.identities == { } || cfg.signingIdentity != null;
        message = "programs.nix-secure-enclave-key.signingIdentity must be set when named identities are configured.";
      }
      {
        assertion = cfg.identities == { } || signing-identity != null;
        message = "programs.nix-secure-enclave-key.signingIdentity must name one of the configured identities.";
      }
    ];

    system.requiresPrimaryUser = [ "programs.nix-secure-enclave-key" ];

    environment.systemPackages = lib.mkAfter ([ package ] ++ lib.optional has-github-auto-add pkgs.gh);

    programs.ssh.extraConfig = lib.mkAfter ssh-extra-config;

    system.activationScripts.postActivation.text = lib.mkAfter activation;
  };
}
