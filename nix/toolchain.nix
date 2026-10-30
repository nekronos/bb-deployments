# Go toolchain satisfying every source's go.mod `go` directive. nixpkgs'
# go_X_Y is used as is; it is overridden only when it lags the directive.
{
  inputs,
  lib,
  ...
}:
let
  sources = lib.attrValues (lib.filterAttrs (n: _: lib.hasPrefix "bb-" n) inputs);
  directive =
    src: builtins.head (builtins.match ".*\ngo ([0-9.]+)\n.*" (builtins.readFile "${src}/go.mod"));
  required = lib.last (lib.sort lib.versionOlder (map directive sources));
in
{
  perSystem =
    { pkgs, ... }:
    let
      attr = "go_" + lib.replaceStrings [ "." ] [ "_" ] (lib.versions.majorMinor required);
      base = pkgs.${attr} or (throw "nixpkgs has no ${attr}; go.mod requires ${required}");
      go =
        if lib.versionAtLeast base.version required then
          base
        else
          base.overrideAttrs (_: {
            version = required;
            src = pkgs.fetchurl {
              url = "https://go.dev/dl/go${required}.src.tar.gz";
              # Maintained by nix/update.sh.
              hash = lib.defaultTo lib.fakeHash (lib.importJSON ./hashes.json).go;
            };
          });
    in
    {
      _module.args = {
        inherit go;
        buildGoModule = pkgs.buildGoModule.override { inherit go; };
      };
    };
}
