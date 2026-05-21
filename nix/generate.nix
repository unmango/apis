{
  buf,
  lib,
  protoc-gen-go,
  runCommand,
}:
let
  src = lib.cleanSource ../.;
in
runCommand "generated"
  {
    nativeBuildInputs = [
      buf
      protoc-gen-go
    ];
  }
  ''
    mkdir -p "$out"
    HOME="$PWD" buf generate ${src} \
      --template ${../buf.gen.yaml} \
      --output "$out"
  ''
