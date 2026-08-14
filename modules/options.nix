{ lib, ... }:

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
      description = "Ensure the local identity and SSH stub during activation; GitHub registration is never run unless github.autoAdd is enabled.";
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
}
