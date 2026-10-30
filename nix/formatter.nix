{ lib, ... }:
let
  nixFiles = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.fileFilter (f: f.hasExt "nix") ../.;
  };
in
{
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.nixfmt-tree;
      checks.fmt = pkgs.runCommand "fmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
        find ${nixFiles} -name '*.nix' -exec nixfmt --check {} +
        touch $out
      '';
    };
}
