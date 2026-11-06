{
  lib,
  stdenv,
  rustPlatform,
  cmake,
  perl,
  pkg-config,
}:

rustPlatform.buildRustPackage {
  pname = "rustical";
  version = (lib.importTOML ../Cargo.toml).workspace.package.version;

  src = ../.;

  cargoLock = {
    lockFile = ../Cargo.lock;
    outputHashes = {
      "web-push-0.11.0" = "sha256-0h8zh5EDh/+FA2NddTw3UkVL+5tp/FW1P4rJHg2V/J4=";
    };
  };

  nativeBuildInputs = [
    cmake
    perl
    pkg-config
  ];

  env.SQLX_OFFLINE = "true";

  doCheck = false;

  meta = {
    description = "CalDAV/CardDAV server";
    homepage = "https://github.com/RafaelMuijsert/rustical";
    license = lib.licenses.agpl3Plus;
    mainProgram = "rustical";
    platforms = lib.platforms.unix;
  };
}
