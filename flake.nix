{
  description = "Public API definitions";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/triplet";
    flake-parts.url = "github:hercules-ci/flake-parts";

    a2b = {
      url = "github:UnstoppableMango/a2b";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.flake-parts.follows = "flake-parts";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    googleapis = {
      url = "github:googleapis/googleapis";
      flake = false;
    };

    # Tag-pinned, so `nix flake update` leaves it alone. Bumping is an edit to
    # this URL followed by `nix flake lock --update-input apimachinery`.
    apimachinery = {
      url = "github:kubernetes/apimachinery/v0.36.4";
      flake = false;
    };

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
        {
          inputs',
          pkgs,
          lib,
          ...
        }:
        let
          inherit (lib.attrsets) recurseIntoAttrs;
          unmangoApis = pkgs.callPackage ./nix {
            bufLib = inputs'.a2b.legacyPackages.lib.buf;
            googleapisSrc = inputs.googleapis;
            apimachinerySrc = inputs.apimachinery;
          };
        in
        {
          packages.default = unmangoApis.generated;
          packages.update = pkgs.callPackage ./nix/update.nix { };
          legacyPackages.unmangoApis = recurseIntoAttrs unmangoApis;

          # k8s.io imports resolve only inside the workspace, so the repo-root
          # buf.yaml cannot be linted on its own.
          checks.buf-lint = pkgs.runCommand "buf-lint" { } ''
            export HOME="$(mktemp -d)"
            ${pkgs.buf}/bin/buf lint ${unmangoApis.workspace}
            touch "$out"
          '';

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
