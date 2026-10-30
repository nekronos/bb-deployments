#!/usr/bin/env nix
#! nix shell --inputs-from .. nixpkgs#bash nixpkgs#coreutils nixpkgs#gawk nixpkgs#git nixpkgs#gnused nixpkgs#jq --command bash
# shellcheck shell=bash
# Point the flake's Buildbarn inputs at the commits MODULE.bazel pins, pick
# compatible commits for the repositories it does not pin, and refresh the
# hashes in nix/hashes.json.
set -euo pipefail
cd "$(dirname "$0")/.."

pinned=(bb-storage bb-remote-execution)
derived=(bb-clientd bb-autoscaler bb-browser)
fake=sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
declare -A rev pinTime

die() {
  echo "$*" >&2
  exit 1
}

# Commit of a git_override in MODULE.bazel, e.g. bb-storage -> ae61334...
pin() {
  local c
  c=$(awk -v m="com_github_buildbarn_${1//-/_}" '
    $0 ~ "module_name = \"" m "\"" { f = 1 }
    f && /commit =/ { gsub(/[",]/, "", $3); print $3; exit }' MODULE.bazel)
  [[ $c =~ ^[0-9a-f]{40}$ ]] || die "MODULE.bazel has no git_override commit for $1"
  echo "$c"
}

setInput() {
  sed -i -E "s|(\"github:buildbarn/$1)/[0-9a-f]{40}\"|\1/$2\"|" flake.nix
  grep -qF "\"github:buildbarn/$1/$2\"" flake.nix ||
    die "flake.nix has no input github:buildbarn/$1/<commit>"
  rev[$1]=$2
  echo "$1 -> $2"
}

# Sets hashes.json key $1 to $2; key "go" holds only release $2's hash $3.
setHash() {
  # shellcheck disable=SC2016 # jq variables
  if [[ $1 == go ]]; then
    jq --arg k "$2" --arg v "$3" '.go = {($k): $v}'
  else
    jq --arg k "$1" --arg v "$2" '.[$k] = $v'
  fi <nix/hashes.json >"$work/hashes.json"
  mv "$work/hashes.json" nix/hashes.json
}

clone() {
  git clone -q --bare --filter=blob:none "https://github.com/buildbarn/$1.git" "$work/$1"
}

goMod() {
  git -C "$work/$1" show "$2:go.mod"
}

# Pseudo-version of a Buildbarn module in go.mod on stdin: "<time> <commit>",
# e.g. "20260906092937 ae61334ea798". Empty if not required.
requires() {
  sed -n "s|.*github.com/buildbarn/$1 v0\.0\.0-\([0-9]\{14\}\)-\([0-9a-f]\{12\}\).*|\1 \2|p" | head -1
}

# Newest first-parent commit whose go.mod requires each pinned module at a
# commit no newer than the pin.
compatible() {
  local next=HEAD c m t ok
  for c in $(git -C "$work/$1" log --first-parent --format=%H HEAD -- go.mod); do
    ok=1
    for m in "${pinned[@]}"; do
      t=$(goMod "$1" "$c" | requires "$m" | cut -d' ' -f1)
      if [[ -z $t || $t -gt ${pinTime[$m]} ]]; then
        ok=
      fi
    done
    if [[ -n $ok ]]; then
      git -C "$work/$1" rev-parse "$next"
      return
    fi
    next=$c^
  done
  die "no $1 commit is compatible with the pinned ${pinned[*]}"
}

for r in "${pinned[@]}"; do
  c=$(pin "$r")
  setInput "$r" "$c"
  clone "$r"
  pinTime[$r]=$(TZ=UTC git -C "$work/$r" log -1 --date=format-local:%Y%m%d%H%M%S --format=%cd "$c")
done

# Binaries link the bb-storage their go.mod names, not the bb-storage input.
want=${rev[bb-storage]:0:12}
got=$(goMod bb-remote-execution "${rev[bb-remote-execution]}" | requires bb-storage | cut -d' ' -f2)
[[ $got == "$want" ]] ||
  die "bb-remote-execution requires bb-storage $got; MODULE.bazel pins $want"

for r in "${derived[@]}"; do
  clone "$r"
  c=$(compatible "$r")
  setInput "$r" "$c"
done

nix flake lock

# Recorded even when nixpkgs' Go suffices, for consumers whose nixpkgs lags.
required=$(for r in "${pinned[@]}" "${derived[@]}"; do
  goMod "$r" "${rev[$r]}" | sed -n 's/^go \([0-9.]*\).*/\1/p'
done | sort -V | tail -1)
goHash=$(nix store prefetch-file --json "https://go.dev/dl/go$required.src.tar.gz" | jq -r .hash)
setHash go "$required" "$goHash"

# Fake each vendor hash and take the real one from the mismatch.
for r in "${pinned[@]}" "${derived[@]}"; do
  setHash "$r" "$fake"
  if log=$(nix build --no-link ".#$r.goModules" 2>&1); then
    die "$r vendor hash did not mismatch"
  fi
  got=$(sed -n 's|.*got: *\(sha256-[^ ]*\).*|\1|p' <<<"$log" | head -1)
  [[ -n $got ]] || die "$log"
  setHash "$r" "$got"
done
