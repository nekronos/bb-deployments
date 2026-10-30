{
  inputs,
  lib,
  ...
}:
let
  # Executables under cmd/ per source repository, plus build overrides.
  repos = {
    bb-storage.bins = [
      "bb_copy"
      "bb_replicator"
      "bb_storage"
      "partition_ephemeral_disks"
      "sync_jwks_to_configmap"
    ];
    bb-remote-execution = {
      bins = [
        "bb_noop_worker"
        "bb_runner"
        "bb_runner_installer"
        "bb_scheduler"
        "bb_virtual_tmp"
        "bb_worker"
        "fake_python"
        "fake_xcrun"
      ];
      # bb_runner_installer embeds bb_runner, which Bazel copies in. Not
      # preBuild: the go-modules derivation inherits it and has no vendor/.
      postConfigure = ''
        go build -ldflags="-s -w" -o cmd/bb_runner_installer/bb_runner ./cmd/bb_runner
      '';
    };
    bb-clientd.bins = [ "bb_clientd" ];
    bb-autoscaler.bins = [
      "bb_asg_lifecycle_hook"
      "bb_autoscaler"
    ];
    bb-browser.bins = [ "bb_browser" ];
  };

  # Go module patches bb-deployments applies through go_deps.module_override.
  modulePatches = {
    "google.golang.org/genproto/googleapis/bytestream" =
      "${inputs.bb-storage}/patches/org_golang_google_genproto_googleapis_bytestream/service-registrar.diff";
    "golang.org/x/sys" = ../patches/org_golang_x_sys/o-search.diff;
  };
  patchVendor = lib.concatStrings (
    lib.mapAttrsToList (mod: patch: ''
      if [ -d vendor/${mod} ]; then
        chmod -R u+w vendor/${mod}
        patch -d vendor/${mod} -p0 < ${patch}
      fi
    '') modulePatches
  );

  # Maintained by nix/update.sh.
  hashes = lib.importJSON ./hashes.json;
in
{
  perSystem =
    {
      pkgs,
      buildGoModule,
      ...
    }:
    let
      mkBuildbarn =
        pname:
        { bins, ... }@args:
        let
          src = inputs.${pname};
        in
        buildGoModule (
          {
            inherit pname src;
            version = "0-unstable-${lib.substring 0 8 src.lastModifiedDate}";
            vendorHash = hashes.${pname};
            subPackages = map (b: "cmd/${b}") bins;
            postConfigure = patchVendor + args.postConfigure or "";
            env.CGO_ENABLED = 0;
            ldflags = [
              "-s"
              "-w"
            ];
            # Tests need the gomock mocks Bazel generates.
            doCheck = false;
            meta = {
              homepage = "https://github.com/buildbarn/${pname}";
              license = lib.licenses.asl20;
              platforms = lib.platforms.linux ++ lib.platforms.darwin;
            };
          }
          // removeAttrs args [
            "bins"
            "postConfigure"
          ]
        );

      # One package per executable, sharing its repository's build.
      mkBinary =
        repo: name:
        pkgs.runCommand name
          {
            meta = repo.meta // {
              mainProgram = name;
            };
          }
          ''
            mkdir -p $out/bin
            ln -s ${repo}/bin/${name} $out/bin/${name}
          '';

      repoPkgs = lib.mapAttrs mkBuildbarn repos;
      binPkgs = lib.concatMapAttrs (r: { bins, ... }: lib.genAttrs bins (mkBinary repoPkgs.${r})) repos;
    in
    {
      _module.args.buildbarnBinaries = binPkgs;

      packages =
        repoPkgs
        // binPkgs
        // {
          default = pkgs.symlinkJoin {
            name = "buildbarn";
            paths = lib.attrValues repoPkgs;
          };
        };

      apps = lib.mapAttrs (name: pkg: {
        type = "app";
        program = lib.getExe pkg;
        meta.description = "Buildbarn ${name}";
      }) binPkgs;
    };
}
