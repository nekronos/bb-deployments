#!/usr/bin/env nix
#! nix shell nixpkgs#bash nixpkgs#gawk nixpkgs#git nixpkgs#jq --command bash
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

# Commit of a git_override in MODULE.bazel, e.g. bb-storage -> ae61334...
pin() {
  awk -v m="com_github_buildbarn_${1//-/_}" '
    $0 ~ "module_name = \"" m "\"" { f = 1 }
    f && /commit =/ { gsub(/[",]/, "", $3); print $3; exit }' MODULE.bazel
}

setInput() {
  sed -i -E "s|(github:buildbarn/$1)/[0-9a-f]{40}|\1/$2|" flake.nix
  echo "$1 -> $2"
}

setHash() {
  jq --arg k "$1" --arg v "$2" '.[$k] = $v' nix/hashes.json > "$work/hashes.json"
  mv "$work/hashes.json" nix/hashes.json
}

clone() {
  git clone -q --bare --filter=blob:none "https://github.com/buildbarn/$1.git" "$work/$1"
}

# Newest first-parent commit whose go.mod requires a bb-storage no newer
# than the timestamp $2 (YYYYMMDDhhmmss, as in Go pseudo-versions).
compatible() {
  local repo=$work/$1 next=HEAD c ts
  for c in $(git -C "$repo" log --first-parent --format=%H HEAD -- go.mod); do
    ts=$(git -C "$repo" show "$c:go.mod" |
      sed -n 's|.*buildbarn/bb-storage v0\.0\.0-\([0-9]*\)-.*|\1|p')
    if [[ $ts -le $2 ]]; then
      git -C "$repo" rev-parse "$next"
      return
    fi
    next=$c^
  done
  echo "no $1 commit compatible with bb-storage at $2" >&2
  return 1
}

for r in "${pinned[@]}"; do
  setInput "$r" "$(pin "$r")"
done

clone bb-storage
storageTime=$(TZ=UTC git -C "$work/bb-storage" log -1 \
  --date=format-local:%Y%m%d%H%M%S --format=%cd "$(pin bb-storage)")
for r in "${derived[@]}"; do
  clone "$r"
  setInput "$r" "$(compatible "$r" "$storageTime")"
done

nix flake lock

# Fake each vendor hash and take the real one from the mismatch. A Go
# toolchain override (nix/toolchain.nix) fails the same way first.
for r in "${pinned[@]}" "${derived[@]}"; do
  setHash "$r" "$fake"
  while ! log=$(nix build --no-link ".#$r.goModules" 2>&1); do
    drv=$(sed -n "s|.*hash mismatch in fixed-output derivation '\([^']*\)'.*|\1|p" <<<"$log" | head -1)
    got=$(sed -n 's|.*got: *\(sha256-[^ ]*\).*|\1|p' <<<"$log" | head -1)
    case $drv in
      *-go-modules.drv) setHash "$r" "$got" ;;
      *.src.tar.gz.drv) setHash go "$got" ;;
      *) echo "$log" >&2; exit 1 ;;
    esac
  done
done
