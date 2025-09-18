{ config, pkgs, ... }:

{
  ############################
  # Motion: capture frames
  ############################
  services.motion = {
    enable = true;
    package = pkgs.motion;
    settings = {
      daemon = on;

      # Resolution & FPS
      width = 1280;
      height = 720;
      framerate = 1;              # 1 fps is enough for dataset

      # Output
      target_dir = "/var/lib/motion";
      output_pictures = "on";     # save all frames during motion
      ffmpeg_output_movies = off; # only stills

      # Motion detection
      threshold = 1500;           # tweak sensitivity as needed
      stream_localhost = off;
    };
  };

  ############################
  # Lighttpd: serve files
  ############################
  services.lighttpd = {
    enable = true;
    document-root = "/var/lib/motion";
    port = 8080; # access via http://<tailscale-ip>:8080/
  };

  ############################
  # Useful tools for debugging
  ############################
  environment.systemPackages = with pkgs; [
    v4l-utils   # inspect webcam formats: v4l2-ctl --list-formats-ext
    lighttpd    # for testing configs manually if needed
  ];
}
