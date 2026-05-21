{ gnumake, nix, writeShellApplication }:
writeShellApplication {
  name = "update";

  runtimeInputs = [ gnumake nix ];

  text = ''
    make update
  '';
}
