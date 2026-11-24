# brew intel-migrate

Move the tools you still use from an old Intel Homebrew (`/usr/local`) to
Apple Silicon Homebrew (`/opt/homebrew`), then remove the Intel install.

Many Macs moved from Intel to Apple Silicon still carry the Intel Homebrew in
`/usr/local`, running through Rosetta. It is easy to forget, it shadows or
mixes with the native tools, and it can break in confusing ways (old `node`,
`pnpm` or `corepack` shims, a git credential helper nobody remembers
installing). This command finds what you still use, installs it natively, and
then removes the rest with Homebrew's official uninstaller.

## Install

```sh
brew tap enesccinar/intel-migrate
brew trust --command enesccinar/intel-migrate/intel-migrate
```

Homebrew 7 and later only run commands from third-party taps you trust. The
second line trusts this one command; `brew untrust` with the same arguments
takes it back.

Needs an Apple Silicon Mac with Homebrew in `/opt/homebrew`, and Rosetta (the
Intel Homebrew already needs it).

## Use

Run the four steps in order. The first two only read.

```sh
brew intel-migrate inventory          # what the Intel install holds
brew intel-migrate plan               # write an editable plan
brew intel-migrate install --yes      # install the plan into /opt/homebrew
brew intel-migrate uninstall --yes    # remove the Intel Homebrew
```

Without `--yes`, `install` and `uninstall` only show what they would do.

### inventory

Lists, without changing anything:

- formulae you installed yourself (dependencies are left out) and casks
- when each was last used, from the access time of its programs
- whether each exists for Apple Silicon, and under which name or tap
- database data in `/usr/local/var` (MySQL, PostgreSQL, MongoDB, Redis)
- your git credential helper, if it points into the Intel install
- shell files and LaunchAgents that still point into the Intel install

### plan

Writes `~/.config/brew-intel-migrate/plan.tsv` (use `--plan <file>` for
another path). Each row is `install`, `drop` or `skip`:

- `install`: used within the last 12 months and available for Apple Silicon
- `drop`: unused for longer, or not available for Apple Silicon
  (for example `python@3.8` or `node@18`)
- `skip`: already installed in `/opt/homebrew`

Change the cut-off with `--since 6m`, `--since 2y` or `--since 90d`, or keep
everything with `--all`. Edit the first column by hand to change any row.

Known renames are handled:

| Intel | Apple Silicon |
| --- | --- |
| cask `git-credential-manager-core` | cask `git-credential-manager` |
| cask `powershell` | formula `powershell` |
| formulae from third-party taps | tapped first, then installed |
| `libpq` (keg-only) | installed and linked, so `psql` is on your PATH |

### install --yes

Installs every `install` row into `/opt/homebrew`, then checks each one is
there. If any fail, it stops and says which, so you can fix them or mark them
`drop`.

### uninstall --yes

1. Refuses while any planned tool is missing from `/opt/homebrew`.
2. Downloads [Homebrew's official uninstaller](https://github.com/Homebrew/install)
   and shows its dry run for `/usr/local`.
3. Asks for your sudo password (files in `/usr/local` are often owned by root
   or by an old user account).
4. Stops Intel `brew services`.
5. Keeps database data, unless you pass `--discard-data`.
6. Runs the uninstaller for `/usr/local` only. `/opt/homebrew` is not touched.
7. Removes broken links it left behind that pointed into Homebrew.
8. Checks the Intel Homebrew is gone, and lists shell files that still point
   into it for you to edit.

It never uninstalls casks one by one. That matters for
`git-credential-manager`: the Apple Silicon package installs into the same
`/usr/local/share/gcm-core` folder, and uninstalling the old Intel cask would
delete the new one.

Files in `/usr/local` that Homebrew did not install are left alone: for
example the AWS CLI, Docker's links, global npm packages and Python packages.

## Safety

- Nothing changes without `--yes`.
- Only `uninstall` asks for sudo.
- Nothing is sent anywhere. The only network use is `brew` itself and the
  download of Homebrew's uninstaller.
- Read the script before running it: it is one bash file,
  [`cmd/brew-intel-migrate`](cmd/brew-intel-migrate).

## Development

```sh
brew install shellcheck bats-core
shellcheck -s bash cmd/brew-intel-migrate test/helpers.bash
bats test
```

Tests use a fake `/usr/local`, a fake `/opt/homebrew` and fake `brew`
binaries in a temporary folder, so they never touch a real install.

## Licence

[MIT](LICENSE)
