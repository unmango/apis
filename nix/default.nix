{
  apimachinerySrc,
  bufLib,
  googleapisSrc,
  lib,
  pkgs,
}:
lib.makeScope pkgs.newScope (self: {
  inherit apimachinerySrc bufLib googleapisSrc;

  apimachinery = self.callPackage ./apimachinery.nix { };
  googleapis = self.callPackage ./googleapis.nix { };
  workspace = self.callPackage ./workspace.nix { };
  generated = self.callPackage ./generate.nix { };
  proto = self.callPackage ./proto.nix { };
})
