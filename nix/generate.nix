{
  buf,
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "generated";
  version = "0.0.1";
  src = lib.cleanSource ../.;

  nativeBuildInputs = [ buf ];

  buildPhase = ''
    HOME="$PWD" buf generate --output "$out"
  '';
}
