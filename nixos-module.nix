{ config, lib, pkgs, ... }:

let
  cfg = config.services.omdrop-owl;
  omdropPkg = if cfg.package != null then cfg.package else pkgs.callPackage ./package.nix { };
in
{
  options.services.omdrop-owl = {
    enable = lib.mkEnableOption "omdrop-owl AWDL AirDrop radio backend";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "The omdrop-owl package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ omdropPkg ];

    # Configure NetworkManager to leave AWDL interfaces unmanaged
    networking.networkmanager.unmanaged = [
      "interface-name:awdl0"
      "interface-name:mon0"
      "interface-name:awdlibss0"
    ];

    # Symlink /usr/lib/omdrop for external programs or scripts expecting this standard path
    systemd.tmpfiles.rules = [
      "L+ /usr/lib/omdrop - - - - ${omdropPkg}/lib/omdrop"
    ];

    # Polkit authorization: allow active local users to control AirDrop discoverability
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if ((action.id == "io.github.t4t5.omdrop-owl.discover" ||
             action.id == "io.github.t4t5.omdrop-owl.discover-usr") &&
            subject.active) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
