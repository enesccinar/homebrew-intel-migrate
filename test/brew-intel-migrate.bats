#!/usr/bin/env bats

load helpers

setup() { setup_fakes; }

@test "--version and --help" {
  run "$CMD" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-intel-migrate "* ]]
  run "$CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"inventory"* && "$output" == *"uninstall"* ]]
}

@test "unknown command and option fail" {
  run "$CMD" frobnicate
  [ "$status" -ne 0 ]
  run "$CMD" plan --bogus
  [ "$status" -ne 0 ]
  run "$CMD" plan --since 12x
  [ "$status" -ne 0 ]
}

@test "refuses on Intel Macs" {
  BIM_ARCH=x86_64 run "$CMD" inventory
  [ "$status" -ne 0 ]
  [[ "$output" == *"Apple Silicon"* ]]
}

@test "nothing to do without an Intel Homebrew" {
  rm -rf "$BIM_INTEL_PREFIX"/{Cellar,Caskroom,Homebrew}
  run "$CMD" inventory
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to do"* ]]
}

@test "inventory lists installed-on-request formulae and casks, not dependencies" {
  add_formula jq
  add_formula libdep false
  add_formula mytool true acme/tools
  add_cask zulu
  available jq zulu
  run "$CMD" inventory
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 formulae (1 you installed"* ]] || [[ "$output" == *"3 formulae (2 you installed"* ]]
  [[ "$output" == *"jq"*"available as jq"* ]]
  [[ "$output" == *"mytool"*"available from tap acme/tools"* ]]
  [[ "$output" == *"zulu"* ]]
  [[ "$output" != *"libdep"* ]]
}

@test "inventory is read-only" {
  add_formula jq
  available jq
  before=$(find "$ROOT" | sort)
  run "$CMD" inventory
  [ "$status" -eq 0 ]
  [ "$(find "$ROOT" | sort)" = "$before" ]
  ! grep -q "install\|uninstall" "$CALLS"
}

@test "inventory reports data, credential helper and shell references" {
  add_formula jq
  available jq
  mkdir -p "$BIM_INTEL_PREFIX/var/mysql"
  git config --global credential.helper "$BIM_INTEL_PREFIX/Cellar/gcm/1/bin/git-credential-manager"
  echo "export PATH=\"$BIM_INTEL_PREFIX/opt/mysql-client/bin:\$PATH\"" >"$HOME/.zshrc"
  run "$CMD" inventory
  [ "$status" -eq 0 ]
  [[ "$output" == *"var/mysql"* ]]
  [[ "$output" == *"breaks when the Intel Homebrew is removed"* ]]
  [[ "$output" == *".zshrc:1"* ]]
}

@test "plan keeps recent tools, drops old, unavailable and disabled ones" {
  add_formula jq true homebrew/core 10
  add_formula wget true homebrew/core 500
  add_formula python@3.8
  add_formula python@3.9
  add_formula ripgrep
  mkdir -p "$BIM_ARM_PREFIX/Cellar/ripgrep"
  available jq wget
  disabled python@3.9
  run "$CMD" plan
  [ "$status" -eq 0 ]
  grep -q "^install	formula	jq	formula:jq	" "$PLAN"
  grep -q "^drop	formula	wget	.*not used within 12m" "$PLAN"
  grep -q "^drop	formula	python@3.8	.*not available" "$PLAN"
  grep -q "^drop	formula	python@3.9	.*disabled" "$PLAN"
  grep -q "^skip	formula	ripgrep	" "$PLAN"
  [[ "$output" == *"1 to install, 3 to drop, 1 already"* ]]
}

@test "plan --all and --since change the cut-off" {
  add_formula wget true homebrew/core 500
  available wget
  run "$CMD" plan --all
  grep -q "^install	formula	wget	" "$PLAN"
  run "$CMD" plan --since 2y
  grep -q "^install	formula	wget	" "$PLAN"
  run "$CMD" plan --since 30d
  grep -q "^drop	formula	wget	" "$PLAN"
}

@test "plan maps renamed casks and tap formulae" {
  add_cask git-credential-manager-core
  add_cask powershell
  add_formula mongodb-database-tools true mongodb/brew
  available git-credential-manager powershell
  run "$CMD" plan
  [ "$status" -eq 0 ]
  grep -q "^install	cask	git-credential-manager-core	cask:git-credential-manager	" "$PLAN"
  grep -q "^install	cask	powershell	formula:powershell	" "$PLAN"
  grep -q "^install	formula	mongodb-database-tools	formula:mongodb/brew/mongodb-database-tools	" "$PLAN"
}

@test "install without --yes changes nothing" {
  add_formula jq
  available jq
  "$CMD" plan >/dev/null
  run "$CMD" install
  [ "$status" -eq 0 ]
  [[ "$output" == *"Run again with --yes"* ]]
  ! grep -q "^arm install" "$CALLS"
}

@test "install --yes installs the plan, taps first, links libpq, checks result" {
  add_formula jq
  add_formula libpq
  add_formula mongodb-database-tools true mongodb/brew
  add_cask git-credential-manager-core
  available jq libpq git-credential-manager
  "$CMD" plan >/dev/null
  run "$CMD" install --yes
  [ "$status" -eq 0 ]
  grep -q "^arm install jq$" "$CALLS"
  grep -q "^arm tap mongodb/brew$" "$CALLS"
  grep -q "^arm install mongodb/brew/mongodb-database-tools$" "$CALLS"
  grep -q "^arm install --cask git-credential-manager$" "$CALLS"
  grep -q "^arm link --force libpq$" "$CALLS"
  [[ "$output" == *"All planned tools are installed"* ]]
}

@test "install honours edits to the plan" {
  add_formula jq
  add_formula wget
  available jq wget
  "$CMD" plan >/dev/null
  sed -i '' 's/^install	formula	wget/drop	formula	wget/' "$PLAN"
  run "$CMD" install --yes
  [ "$status" -eq 0 ]
  grep -q "^arm install jq$" "$CALLS"
  ! grep -q "^arm install wget$" "$CALLS"
}

@test "install reports failures and exits non-zero" {
  add_formula jq
  add_formula broken
  available jq broken
  echo broken >"$ROOT/fail"
  "$CMD" plan >/dev/null
  run "$CMD" install --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING  broken"* ]]
}

@test "uninstall needs a plan" {
  add_formula jq
  run "$CMD" uninstall --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"no plan"* ]]
}

@test "uninstall refuses while planned tools are missing" {
  add_formula jq
  available jq
  "$CMD" plan >/dev/null
  run "$CMD" uninstall --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed on Apple Silicon: jq"* ]]
  [ -d "$BIM_INTEL_PREFIX/Cellar" ]
}

@test "uninstall without --yes only runs the dry run" {
  add_formula jq
  available jq
  "$CMD" plan >/dev/null
  "$CMD" install --yes >/dev/null
  run "$CMD" uninstall
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would delete"* && "$output" == *"Nothing was removed"* ]]
  grep -q "^uninstall --path=$BIM_INTEL_PREFIX --dry-run$" "$CALLS"
  ! grep -q -- "--force" "$CALLS"
  [ -d "$BIM_INTEL_PREFIX/Cellar" ]
}

@test "uninstall --yes removes Homebrew, keeps data and non-brew files, cleans links" {
  add_formula jq
  available jq
  mkdir -p "$BIM_INTEL_PREFIX/var/mysql" "$BIM_INTEL_PREFIX/aws-cli"
  touch "$BIM_INTEL_PREFIX/aws-cli/aws"
  ln -s ../aws-cli/aws "$BIM_INTEL_PREFIX/bin/aws"
  mkdir -p "$BIM_INTEL_PREFIX/share/man/man1"
  ln -s ../../../Homebrew/manpages/brew.1 "$BIM_INTEL_PREFIX/share/man/man1/brew.1"
  ln -s /nonexistent/other "$BIM_INTEL_PREFIX/bin/unrelated"
  "$CMD" plan >/dev/null
  "$CMD" install --yes >/dev/null
  run "$CMD" uninstall --yes
  [ "$status" -eq 0 ]
  grep -q "^intel services stop --all$" "$CALLS"
  grep -q "^uninstall --path=$BIM_INTEL_PREFIX --force$" "$CALLS"
  [ ! -e "$BIM_INTEL_PREFIX/Cellar" ]
  [ -d "$BIM_INTEL_PREFIX/var/mysql" ]
  [ -L "$BIM_INTEL_PREFIX/bin/aws" ]
  [ ! -L "$BIM_INTEL_PREFIX/share/man/man1/brew.1" ]
  [ -L "$BIM_INTEL_PREFIX/bin/unrelated" ]
  [[ "$output" == *"Intel Homebrew removed"* ]]
}

@test "uninstall --discard-data deletes database data" {
  add_formula jq
  available jq
  mkdir -p "$BIM_INTEL_PREFIX/var/mysql" "$BIM_INTEL_PREFIX/var/postgresql@15"
  "$CMD" plan >/dev/null
  "$CMD" install --yes >/dev/null
  run "$CMD" uninstall --yes --discard-data
  [ "$status" -eq 0 ]
  [ ! -e "$BIM_INTEL_PREFIX/var/mysql" ]
  [ ! -e "$BIM_INTEL_PREFIX/var/postgresql@15" ]
}

@test "uninstall never uninstalls casks itself (keeps git-credential-manager files)" {
  add_cask git-credential-manager-core
  available git-credential-manager
  mkdir -p "$BIM_INTEL_PREFIX/share/gcm-core"
  touch "$BIM_INTEL_PREFIX/share/gcm-core/git-credential-manager"
  "$CMD" plan >/dev/null
  "$CMD" install --yes >/dev/null
  run "$CMD" uninstall --yes
  [ "$status" -eq 0 ]
  ! grep -q "^intel uninstall" "$CALLS"
  [ -f "$BIM_INTEL_PREFIX/share/gcm-core/git-credential-manager" ]
}
