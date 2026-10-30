# Run each executable once without a configuration. A sound binary exits 1
# with a usage message; a panic exits 2 and a loader error 126/127.
{ lib, ... }: {
  perSystem =
    {
      pkgs,
      buildbarnBinaries,
      ...
    }:
    let
      expected =
        name:
        {
          fake_python = "Fake Python can only be used";
          fake_xcrun = "Expected xcrun to be invoked";
        }
        .${name} or "Usage: ${name} ${name}.jsonnet";

      smoke =
        name: pkg:
        pkgs.runCommand "smoke-${name}" { } ''
          status=0
          ${lib.getExe pkg} > out 2>&1 || status=$?
          cat out
          [ $status -eq 1 ]
          grep -qF '${expected name}' out
          touch $out
        '';

      # Installs the embedded bb_runner, which must itself run.
      installer = pkgs.runCommand "smoke-bb_runner_installer" { } ''
        mkdir bb
        ${lib.getExe buildbarnBinaries.bb_runner_installer} $PWD/bb
        test -e bb/installed
        bb/bb_runner > out 2>&1 || true
        grep -qF 'Usage: bb_runner bb_runner.jsonnet' out
        touch $out
      '';
    in
    {
      checks =
        lib.mapAttrs' (n: p: lib.nameValuePair "smoke-${n}" (smoke n p)) (
          removeAttrs buildbarnBinaries [ "bb_runner_installer" ]
        )
        // {
          smoke-bb_runner_installer = installer;
        };
    };
}
