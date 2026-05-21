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
          inherit (lib.attrsets) recurseIntoAttrs;
          unmangoApis = pkgs.callPackage ./nix { };
        in
        {
          packages.default = unmangoApis.generated;
          packages.update = pkgs.callPackage ./nix/update.nix { };
          legacyPackages.unmangoApis = recurseIntoAttrs unmangoApis;

          devShells.default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              buf
              gnumake
              nixfmt
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
