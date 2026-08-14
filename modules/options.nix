{ lib, ... }:

{
  options.programs.nix-secure-enclave-key = {
    enable = lib.mkEnableOption "nix-secure-enclave-key";

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/id_enclave_key";
      description = "Path to the non-secret SSH stub or public-key reference; the public key is read from the matching .pub file.";
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

    identities = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            keyFile = lib.mkOption {
              type = lib.types.str;
              description = "Path to this identity's non-secret SSH stub or public-key reference; the public key is read from the matching .pub file.";
            };

            label = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "CryptoTokenKit label for this identity. When omitted, it is derived as <name>-nix-secure-enclave-key.";
            };

            protection = lib.mkOption {
              type = lib.types.enum [
                "none"
                "bio"
              ];
              default = "none";
              description = "Secure Enclave protection for this identity. none is suitable for unattended use; bio may require Touch ID.";
            };

            autoEnsure = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Ensure this identity and SSH stub/reference during activation.";
            };

            github.autoAdd = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Register this identity's public key with GitHub during activation.";
            };

            github.type = lib.mkOption {
              type = lib.types.enum [
                "signing"
                "authentication"
                "both"
              ];
              default = "both";
              description = "GitHub key purpose for this identity when autoAdd is enabled.";
            };

            github.title = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "GitHub title for this identity when it is registered. When omitted, it is generated from the identity name, macOS machine name, and public-key fingerprint.";
            };
          };
        }
      );
      default = { };
      description = "Named Secure Enclave identities. When set, the named identity selected by signingIdentity is used for Git signing and all identities are added to SSH configuration.";
    };

    signingIdentity = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Name of the identity in identities to use for Git signing. Required when identities is non-empty; legacy settings use the single default identity.";
    };

    autoEnsure = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Ensure the local identity and SSH stub/reference during activation; GitHub registration is never run unless github.autoAdd is enabled.";
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
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "GitHub title for the default identity. When omitted, it is generated from the macOS machine name and public-key fingerprint.";
    };
  };
}
