{ config, pkgs, lib, ... }:

let
  motionConfig = pkgs.writeText "motion.conf" ''
	  daemon off
	  width 1280
	  height 720
	  framerate 1
	  target_dir /var/www/motion-images
	  picture_output on
	  movie_output off
	  threshold 20000
	  stream_localhost off
	  v4l2_palette 2
  '';
in {

  environment.systemPackages = with pkgs; [
    motion
    v4l-utils
    lighttpd
  ];

  ##################################
  # Systemd service for motion
  ##################################
  systemd.services.motion = {
    description = "Motion daemon";
    after = [ "network.target" "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.motion}/bin/motion -c ${motionConfig}";
      Restart = "always";
      User = "root"; # or create a dedicated user
    };
  };

  ##################################
  # Lighttpd webserver for browsing
  ##################################
  services.lighttpd = {
    enable = true;
    document-root = "/var/www/motion-images";
    port = 8080;
  extraConfig = ''
    server.modules += ( "mod_dirlisting" )
    dir-listing.activate = "enable"
  '';
  };

}
