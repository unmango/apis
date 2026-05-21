{
  buf,
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "proto";
  version = "0.0.1";
  src = lib.cleanSource ../.;

  nativeBuildInputs = [ buf ];

  buildPhase = ''
    HOME="$PWD" buf build . --output apis.binpb
  '';

  installPhase = ''
    mkdir -p $out
    cp apis.binpb $out/
  '';
}
