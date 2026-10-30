# Go toolchain satisfying every source's go.mod `go` directive: nixpkgs' go
# if recent enough, else its go_X_Y, else go_X_Y with the exact release.
{
  inputs,
  lib,
  buildbarnRepos,
  ...
}:
let
  directive =
    src:
    let
      m = builtins.match ".*\ngo ([0-9.]+)[^\n]*\n.*" (builtins.readFile "${src}/go.mod");
    in
    if m == null then throw "no go directive in ${src}/go.mod" else builtins.head m;
  required = lib.last (
    lib.sort lib.versionOlder (map (n: directive inputs.${n}) (lib.attrNames buildbarnRepos))
  );
  sufficient = go: lib.versionAtLeast go.version required;
in
{
  perSystem =
    { pkgs, ... }:
    let
      bp = pkgs.buildPackages;
      attr = "go_" + lib.replaceStrings [ "." ] [ "_" ] (lib.versions.majorMinor required);
      base =
        if sufficient bp.go then
          bp.go
        else
          bp.${attr} or (throw "nixpkgs has no ${attr}; go.mod requires ${required}");
      go =
        if sufficient base then
          base
        else
          base.overrideAttrs (_: {
            version = required;
            src = pkgs.fetchurl {
              url = "https://go.dev/dl/go${required}.src.tar.gz";
              # Keyed by version: fetchurl's store path depends on the hash
              # alone, so a stale hash would silently reuse an old release.
              hash = (lib.importJSON ./hashes.json).go.${required} or lib.fakeHash;
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
