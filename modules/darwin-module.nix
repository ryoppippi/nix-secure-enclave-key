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
  keyFile =
    if primaryUser != null && lib.hasPrefix "~/" cfg.keyFile then
      "${primaryUserHome}/${lib.removePrefix "~/" cfg.keyFile}"
    else
      cfg.keyFile;
  runAsPrimaryUser =
    command: "/usr/bin/sudo --user=${lib.escapeShellArg primaryUser} --set-home ${command}";
  activation = lib.optionalString (primaryUser != null) ''
    ${lib.optionalString cfg.autoEnsure ''
      ${runAsPrimaryUser "${package}/bin/nix-secure-enclave-key"} identity ensure \
        --key-file ${lib.escapeShellArg keyFile} \
        --label ${lib.escapeShellArg cfg.label} \
        --protection ${lib.escapeShellArg cfg.protection}
    ''}

    ${runAsPrimaryUser "/usr/bin/git"} config --global gpg.format ssh
    ${runAsPrimaryUser "/usr/bin/git"} config --global user.signingkey ${lib.escapeShellArg keyFile}
    ${runAsPrimaryUser "/usr/bin/git"} config --global gpg.ssh.program ${lib.escapeShellArg "${package}/bin/nix-secure-enclave-key-git-sign"}
    ${runAsPrimaryUser "/usr/bin/git"} config --global commit.gpgsign ${
      if cfg.signByDefault then "true" else "false"
    }

    ${lib.optionalString cfg.github.autoAdd ''
      ${runAsPrimaryUser "/usr/bin/env"} \
        ${lib.escapeShellArg "PATH=${pkgs.gh}/bin:/usr/bin:/bin:/usr/sbin:/sbin"} \
        ${package}/bin/nix-secure-enclave-key github add \
          --key-file ${lib.escapeShellArg keyFile} \
          --type ${lib.escapeShellArg cfg.github.type} \
          --title ${lib.escapeShellArg cfg.github.title}
    ''}
  '';
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    system.requiresPrimaryUser = [ "programs.nix-secure-enclave-key" ];

    environment.systemPackages = lib.mkAfter ([ package ] ++ lib.optional cfg.github.autoAdd pkgs.gh);

    programs.ssh.extraConfig = lib.mkAfter ''
      Host *
        IdentityFile ${cfg.keyFile}
        SecurityKeyProvider /usr/lib/ssh-keychain.dylib
    '';

    system.activationScripts.postActivation.text = lib.mkAfter activation;
  };
}
