{ self }:

{
  config,
  lib,
  pkgs,
  ...
}:

{
  config.environment.systemPackages = lib.mkAfter [
    self.packages.${pkgs.system}.default
  ];
}
