{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.enclave-key;
in
{
  options.programs.enclave-key = {
    enable = lib.mkEnableOption "enclave-key";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ self.packages.${pkgs.system}.default ];
  };
}
