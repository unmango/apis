{ lib, pkgs }:
lib.makeScope pkgs.newScope (self: {
  generated = self.callPackage ./generate.nix { };
  proto = self.callPackage ./proto.nix { };
})
