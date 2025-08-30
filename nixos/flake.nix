{
  description = ''
    Examples of NixOS systems' configuration for Raspberry Pi boards
    using nixos-raspberrypi
  '';

  nixConfig = {
    bash-prompt = "\[nixos-raspberrypi-demo\] ➜ ";
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
      "https://devenv.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
    ];
    connect-timeout = 5;
  };

  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };

    disko = {
      # the fork is needed for partition attributes support
      url = "github:nvmd/disko/gpt-attrs";
      # url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
    };
  };

  outputs = { self, nixpkgs
            , nixos-raspberrypi, disko
            , nixos-anywhere, ... }@inputs: let
    allSystems = nixpkgs.lib.systems.flakeExposed;
    forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);
  in {

    devShells = forSystems allSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          nil # lsp language server for nix
          nixpkgs-fmt
          nix-output-monitor
          nixos-anywhere.packages.${system}.default
        ];
      };
    });

    nixosConfigurations = let

      users-config-stub = ({ config, pkgs, ... }: {
        # This is identical to what nixos installer does in
        # (modulesPash + "profiles/installation-device.nix")

        # Use less privileged nixos user
        users.users.amon = {
          isNormalUser = true;
          shell = pkgs.fish;
          extraGroups = [
            "wheel"
            "networkmanager"
            "video"
          ];
          # Allow the graphical user to login without password
          initialHashedPassword = "";
        };

        # Don't require sudo/root to `reboot` or `poweroff`.
        security.polkit.enable = true;

        # Allow passwordless sudo from nixos user
        security.sudo = {
          enable = true;
          wheelNeedsPassword = false;
        };

        # Automatically log in at the virtual consoles.
        services.getty.autologinUser = "amon";

        # We run sshd by default. Login is only possible after adding a
        # password via "passwd" or by adding a ssh key to ~/.ssh/authorized_keys.
        # The latter one is particular useful if keys are manually added to
        # installation device for head-less systems i.e. arm boards by manually
        # mounting the storage in a different system.
        services.openssh = {
          enable = true;
          settings.PermitRootLogin = "yes";
        };

        # allow nix-copy to live system
        nix.settings.trusted-users = [ "amon" ];

        # We are stateless, so just default to latest.
        system.stateVersion = config.system.nixos.release;
      });

      network-config = {
        # This is mostly portions of safe network configuration defaults that
        # nixos-images and srvos provide

        networking.useNetworkd = true;
        # mdns
        networking.firewall.allowedUDPPorts = [ 5353 ];
        systemd.network.networks = {
          "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
          "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
        };

        # This comment was lifted from `srvos`
        # Do not take down the network for too long when upgrading,
        # This also prevents failures of services that are restarted instead of stopped.
        # It will use `systemctl restart` rather than stopping it with `systemctl stop`
        # followed by a delayed `systemctl start`.
        systemd.services = {
          systemd-networkd.stopIfChanged = false;
          # Services that are only restarted might be not able to resolve when resolved is stopped before
          systemd-resolved.stopIfChanged = false;
        };

        # Use iwd instead of wpa_supplicant. It has a user friendly CLI
        networking.wireless.enable = false;
        networking.wireless.iwd = {
          enable = true;
          settings = {
            Network = {
              EnableIPv6 = true;
              RoutePriorityOffset = 300;
            };
            Settings.AutoConnect = true;
          };
        };
      };

      common-user-config = {config, pkgs, ... }: {
        imports = [
          ./modules/nice-looking-console.nix
          ./modules/wifi-auto-connect.nix
          ./modules/wifi-watchdog.nix
          users-config-stub
          network-config
        ];

        time.timeZone = "UTC";
        networking.hostName = "meowpi";

        # Enable experimental Nix features
        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        # WiFi auto-connect configuration
        networking.wifi-credentials = {
          enable = true;
          credentialsFile = ./wifi-credentials.json;
        };

        # WiFi watchdog to reconnect if disconnected
        services.wifi-watchdog = {
          enable = true;
          interval = "10s";  # Check every 10 seconds
        };

        services.tailscale = {
          enable = true;
          openFirewall = true;     # open UDP 41641 for Tailscale
          # Optional but handy so you can use a name instead of an IP:
          extraUpFlags = [ "--accept-dns=true" ];  # MagicDNS
        };

        services.udev.extraRules = ''
          # Ignore partitions with "Required Partition" GPT partition attribute
          # On our RPis this is firmware (/boot/firmware) partition
          ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
            ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
            ENV{UDISKS_IGNORE}="1"
        '';

        environment.systemPackages = with pkgs; [
          autojump
          bat
          busybox
          coreutils
          devenv
          direnv
          git
          gnumake
          neovim
          python3
          tmux
          uv
        ];

        users.users.amon.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiKlVyn39sZsB28J4yJVmUoVkQj7O69M96mXLaRQymq thai-rpi5"
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFzZ1Ny+blJvL85rZLQXYNh3tiE3QdppWUuGbq1Se/oQrn5injs3pqg4uzb+FO4ZdAjnIHexgX6FnxT3sCI3EbI= thai-rpi5@secretive.Amon's-MacBook-Air.local"
        ];
        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFiKlVyn39sZsB28J4yJVmUoVkQj7O69M96mXLaRQymq thai-rpi5"
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFzZ1Ny+blJvL85rZLQXYNh3tiE3QdppWUuGbq1Se/oQrn5injs3pqg4uzb+FO4ZdAjnIHexgX6FnxT3sCI3EbI= thai-rpi5@secretive.Amon's-MacBook-Air.local"
        ];

        programs.autojump.enable = true;
        programs.fish.enable = true;
        programs.starship.enable = true;  # Beautiful prompt theme
        users.users.root.shell = pkgs.fish;

        system.nixos.tags = let
          cfg = config.boot.loader.raspberryPi;
        in [
          "raspberry-pi-${cfg.variant}"
          cfg.bootloader
          config.boot.kernelPackages.kernel.version
        ];
      };
    in {

      meowpi = nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, disko, ... }: {
            imports = with nixos-raspberrypi.nixosModules; [
              # Hardware configuration
              raspberry-pi-5.base
              raspberry-pi-5.display-vc4
              ./pi5-configtxt.nix
            ];
          })
          # Disk configuration
          disko.nixosModules.disko
          # WARNING: formatting disk with disko is DESTRUCTIVE, check if
          # `disko.devices.disk.nvme0.device` is set correctly!
          ./disko-usb-btrfs.nix
          { networking.hostId = "8821e309"; } # NOTE: for zfs, must be unique
          # Further user configuration
          common-user-config
          {
            boot.tmp.useTmpfs = true;
          }

          # Advanced: Use non-default kernel from kernel-firmware bundle
          ({ config, pkgs, lib, ... }: let
            kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
          in {
            boot = {
              loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
              kernelPackages = kernelBundle.linuxPackages_rpi5;
            };

            nixpkgs.overlays = lib.mkAfter [
              (self: super: {
                # This is used in (modulesPath + "/hardware/all-firmware.nix") when at least
                # enableRedistributableFirmware is enabled
                # I know no easier way to override this package
                inherit (kernelBundle) raspberrypiWirelessFirmware;
                # Some derivations want to use it as an input,
                # e.g. raspberrypi-dtbs, omxplayer, sd-image-* modules
                inherit (kernelBundle) raspberrypifw;
              })
            ];
          })

        ];
      };

    };

  };
}
