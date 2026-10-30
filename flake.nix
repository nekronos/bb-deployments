{
  description = "Buildbarn executables at the commits bb-deployments pins";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";

    # Pinned by MODULE.bazel; nix/update.sh keeps these in sync.
    bb-storage = {
      url = "github:buildbarn/bb-storage/ae61334ea7982155ceb317e286e2a462d875477d";
      flake = false;
    };
    bb-remote-execution = {
      url = "github:buildbarn/bb-remote-execution/582d07ff2acc2faa91b3e875e62bf610b13d37b5";
      flake = false;
    };

    # Not in MODULE.bazel: newest commit whose go.mod requires a bb-storage
    # no newer than the pinned one.
    bb-clientd = {
      url = "github:buildbarn/bb-clientd/ffb681565e116c8e3a713dbf1b20ee9e45429f19";
      flake = false;
    };
    bb-autoscaler = {
      url = "github:buildbarn/bb-autoscaler/9e8d8bec87763a812f3817a8df57155314e9688a";
      flake = false;
    };
    bb-browser = {
      url = "github:buildbarn/bb-browser/8acf6e3e5afc12fd6e1c1af57f0f7afcb67681f4";
      flake = false;
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      imports = [
        ./nix/toolchain.nix
        ./nix/packages.nix
        ./nix/checks.nix
        ./nix/devshell.nix
        ./nix/overlay.nix
      ];
    };
}
