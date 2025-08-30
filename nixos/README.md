NixOs config for running meow-shield on a Raspberry pi 5.

# Installation

## 1. Preparing installation media
```
# clone repo
git clone https://github.com/nvmd/
cd nixos-raspberrypi

# build image (didn't change anything in repo)
nix --extra-experimental-features nix-command --extra-experimental-features flakes build .#installerImages.rpi5

# flash to USB disk
cd result/sd-image
# find which disk is USB disk
# run before inserting USB disk
lsblk -p
# insert USB disk and run again
lsblk -p
# flash
zstdcat nixos-installer-rpi5-kernelboot.img.zst | sudo dd of=/dev/sdb bs=4M conv=fsync
sync

# insert USB disk to raspberry pi and boot
```

## 2. Installation

The flake was taken and adjusted from https://github.com/nvmd/nixos-raspberrypi-demo.

```
cd meow-shield/nixos
```

```
cp wifi-credentials.example.json wifi-credentials.json
nvim wifi-credentials.json
git add -N wifi-credentials.json -f
```

```
nix-shell -p nixos-anywhere --run "nixos-anywhere --build-on-remote --flake .#meowpi root@<ip>"
```

## 3. Post-installation

#### Setup tailscale
```
sudo tailscale up
```

### Setup SSH access with Secretive

Secretive, a macOS app that allows you to store your SSH keys in the macOS Secure Enclave and require a finger-print every time a key is used.

Install Secretive from https://github.com/maxgoedjen/secretive/releases
Create a new SSH key with Secretive and select `Require Authentication` for it.
For SSH, using Secretive on macOS, add the following to your `~/.ssh/config`:

```
Host meowpi
	User amon
	HostName <ip>
	ForwardAgent yes
	IdentityAgent /Users/amon/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
```

# Rebuilding

```
ssh meowpi

# Get config
git clone https://github.com/am-on/meow-shield

# Setup wifi credentials
cp wifi-credentials.example.json wifi-credentials.json
nvim wifi-credentials.json
git add -N wifi-credentials.json -f

# Rebuild
sudo nixos-rebuild switch --flake .#meowpi
```
