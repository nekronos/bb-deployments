# Nix flake

`flake.nix` builds the Buildbarn executables with `buildGoModule` at the
commits this repository's `MODULE.bazel` pins.

```sh
nix build .#default             # every executable, in result/bin
nix build .#bb-storage          # one repository's executables
nix run .#bb_scheduler -- bb_scheduler.jsonnet
nix flake check                 # build and run each executable once
nix develop                     # go, jsonnet, grpcurl
```

Systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`. Only
`x86_64-linux` is built and checked; the others evaluate, and every
executable cross-compiles for darwin with `GOOS=darwin`.

Other flakes consume it through `packages.<system>.<name>` or
`overlays.default`, which adds `pkgs.buildbarn.<name>`.

## Outputs

| Package               | Executables                                                                                                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------- |
| `bb-storage`          | `bb_copy` `bb_replicator` `bb_storage` `partition_ephemeral_disks` `sync_jwks_to_configmap`                    |
| `bb-remote-execution` | `bb_noop_worker` `bb_runner` `bb_runner_installer` `bb_scheduler` `bb_virtual_tmp` `bb_worker` `fake_python` `fake_xcrun` |
| `bb-clientd`          | `bb_clientd`                                                                                                   |
| `bb-autoscaler`       | `bb_asg_lifecycle_hook` `bb_autoscaler`                                                                        |
| `bb-browser`          | `bb_browser` (deprecated upstream in favour of bb-portal)                                                      |

Each executable is also a package and an app of its own name.
`packages.default` joins them all.

Not provided: bb-portal, whose `bb_portal` embeds a web frontend that only
its Bazel build produces.

## Sources

`bb-storage` and `bb-remote-execution` follow the `git_override` commits
in `MODULE.bazel`. The other repositories are not pinned there; each uses
its newest commit whose `go.mod` requires a bb-storage no newer than the
pinned one.

The Go module patches `MODULE.bazel` applies through
`go_deps.module_override` (`service-registrar.diff` on the bytestream
API, `o-search.diff` on `golang.org/x/sys` for darwin) are applied to the
vendored modules.

## Updating

After `MODULE.bazel` moves:

```sh
nix/update.sh      # inputs from MODULE.bazel, lock, nix/hashes.json
nix flake check
```

`nix flake update nixpkgs` bumps the toolchain. `nix/toolchain.nix` picks
nixpkgs' `go_X_Y` for the highest `go` directive among the sources and
fetches the exact release only if nixpkgs lags it; `update.sh` records
that tarball's hash in `nix/hashes.json`.
