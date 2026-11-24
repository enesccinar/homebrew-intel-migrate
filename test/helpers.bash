# Shared setup for the bats tests: a fake Intel /usr/local, a fake /opt/homebrew
# and fake brew binaries, so no test touches a real Homebrew install.

setup_fakes() {
  export ROOT="$BATS_TEST_TMPDIR/root"
  export BIM_INTEL_PREFIX="$ROOT/usr/local"
  export BIM_ARM_PREFIX="$ROOT/opt/homebrew"
  export BIM_ARCH=arm64
  export BIM_SUDO=""
  export HOME="$ROOT/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export CALLS="$ROOT/calls.log"
  export PLAN="$XDG_CONFIG_HOME/brew-intel-migrate/plan.tsv"
  export CMD="$BATS_TEST_DIRNAME/../cmd/brew-intel-migrate"

  mkdir -p "$BIM_INTEL_PREFIX"/{Cellar,Caskroom,Homebrew,bin,var} "$BIM_ARM_PREFIX"/{Cellar,Caskroom,bin} "$HOME"
  : >"$CALLS"
  git config --global --unset-all credential.helper >/dev/null 2>&1 || true

  # Fake Apple Silicon brew. AVAILABLE / DISABLED list names `brew info` knows.
  export BIM_ARM_BREW="$ROOT/arm-brew"
  cat >"$BIM_ARM_BREW" <<'EOF'
#!/bin/bash
echo "arm $*" >>"$CALLS"
case "$1" in
  info)
    name="${*: -1}"; kind=formulae; [[ " $* " == *" --cask "* ]] && kind=casks
    if grep -qx "$name" "$ROOT/disabled" 2>/dev/null; then
      echo "{\"$kind\":[{\"disabled\":true}]}"
    elif grep -qx "$name" "$ROOT/available" 2>/dev/null; then
      echo "{\"$kind\":[{\"disabled\":false}]}"
    else
      exit 1
    fi ;;
  install)
    if [ "$2" = --cask ]; then mkdir -p "$BIM_ARM_PREFIX/Caskroom/$3"
    else n="${2##*/}"; grep -qx "$n" "$ROOT/fail" 2>/dev/null && exit 1; mkdir -p "$BIM_ARM_PREFIX/Cellar/$n"; fi ;;
esac
exit 0
EOF
  chmod +x "$BIM_ARM_BREW"

  export BIM_INTEL_BREW="$ROOT/intel-brew"
  cat >"$BIM_INTEL_BREW" <<'EOF'
#!/bin/bash
echo "intel $*" >>"$CALLS"
EOF
  chmod +x "$BIM_INTEL_BREW"

  # Fake Homebrew uninstaller: --dry-run prints, --force removes the brew dirs.
  export BIM_UNINSTALL_SCRIPT="$ROOT/uninstall.sh"
  cat >"$BIM_UNINSTALL_SCRIPT" <<'EOF'
echo "uninstall $*" >>"$CALLS"
prefix="${1#--path=}"
if [ "$2" = --dry-run ]; then echo "Would delete $prefix/Cellar"; exit 0; fi
rm -rf "$prefix/Cellar" "$prefix/Caskroom" "$prefix/Homebrew" "$prefix/bin/brew"
EOF
  touch "$BIM_INTEL_PREFIX/bin/brew"
}

# add_formula <name> [on_request true|false] [tap] [days since last use]
add_formula() {
  local name="$1" req="${2:-true}" tap="${3:-homebrew/core}" days="${4:-1}" d
  d="$BIM_INTEL_PREFIX/Cellar/$name/1.0"
  mkdir -p "$d/bin"
  printf '{"installed_on_request":%s,"source":{"tap":"%s"}}' "$req" "$tap" >"$d/INSTALL_RECEIPT.json"
  touch "$d/bin/$name"
  touch -a -t "$(date -v-"${days}"d +%Y%m%d%H%M)" "$d/bin/$name"
}

# add_cask <name> [days since last use]
add_cask() {
  local d="$BIM_INTEL_PREFIX/Caskroom/$1/1.0"
  mkdir -p "$d"
  touch "$d/$1"
  touch -a -t "$(date -v-"${2:-1}"d +%Y%m%d%H%M)" "$d/$1"
}

available() { printf '%s\n' "$@" >>"$ROOT/available"; }
disabled() { printf '%s\n' "$@" >>"$ROOT/disabled"; }
