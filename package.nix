{
  lib,
  stdenvNoCC,
  nushell,
}:

stdenvNoCC.mkDerivation {
  pname = "nix-secure-enclave-key";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ${./src/nix-secure-enclave-key.nu} "$out/bin/nix-secure-enclave-key"
    substituteInPlace "$out/bin/nix-secure-enclave-key" \
      --replace-fail '#!/usr/bin/env nu' '#!${nushell}/bin/nu'
    install -Dm755 ${./src/nix-secure-enclave-key-git-sign.nu} "$out/bin/nix-secure-enclave-key-git-sign"
    substituteInPlace "$out/bin/nix-secure-enclave-key-git-sign" \
      --replace-fail '#!/usr/bin/env nu' '#!${nushell}/bin/nu'
    runHook postInstall
  '';

  meta = {
    description = "Secure Enclave-backed SSH and Git signing helper for macOS";
    homepage = "https://github.com/ryoppippi/nix-secure-enclave-key";
    license = lib.licenses.mit;
    mainProgram = "nix-secure-enclave-key";
    maintainers = [ lib.maintainers.ryoppippi ];
    platforms = lib.platforms.darwin;
  };
}
