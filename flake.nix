{
  description = "AirDrop radio backend for omdrop on non-Broadcom Wi-Fi using OWL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./package.nix { };
        omdrop-owl = pkgs.callPackage ./package.nix { };
      });

      overlays.default = final: prev: {
        omdrop-owl = final.callPackage ./package.nix { };
      };

      nixosModules.default = import ./nixos-module.nix;
      nixosModules.omdrop-owl = import ./nixos-module.nix;
    };
}
