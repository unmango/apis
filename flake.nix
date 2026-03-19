{
  description = "Public API definitions";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [ inputs.treefmt-nix.flakeModule ];

      perSystem =
        { pkgs, lib, ... }:
        let
          protoapis = pkgs.stdenv.mkDerivation {
            pname = "protoapis";
            version = "0.0.1";
            src = lib.cleanSource ./.;

            nativeBuildInputs = [ pkgs.buf ];

            buildPhase = ''
              HOME="$PWD" buf build . --output apis.binpb
            '';

            installPhase = ''
              mkdir -p $out
              cp apis.binpb $out/
            '';
          };
        in
        {
          packages = {
            inherit protoapis;
            default = protoapis;
          };

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              buf
              gnumake
            ];
          };

          treefmt.programs = {
            actionlint.enable = true;
            buf.enable = true;
            mdformat.enable = true;
            nixfmt.enable = true;

            yamllint = {
              enable = true;
              settings.document-start = "disable";
            };
          };
        };
    };
}
