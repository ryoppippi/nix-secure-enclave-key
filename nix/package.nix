{
  lib,
  stdenvNoCC,
  nushell,
}:

stdenvNoCC.mkDerivation {
  pname = "enclave-key";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 ${./enclave-key.nu} "$out/bin/enclave-key"
    substituteInPlace "$out/bin/enclave-key" \
      --replace-fail '#!/usr/bin/env nu' '#!${nushell}/bin/nu'
    install -Dm755 ${./enclave-key-git-sign.nu} "$out/bin/enclave-key-git-sign"
    substituteInPlace "$out/bin/enclave-key-git-sign" \
      --replace-fail '#!/usr/bin/env nu' '#!${nushell}/bin/nu'
    runHook postInstall
  '';

  meta = {
    description = "Secure Enclave-backed SSH and Git signing helper for macOS";
    homepage = "https://github.com/ryoppippi/enclave-key";
    license = lib.licenses.mit;
    mainProgram = "enclave-key";
    platforms = lib.platforms.unix;
  };
}
