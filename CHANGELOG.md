# Changelog

## 0.2.0

- Find commands that only the Intel Homebrew provides, including ones from
  dependencies and ones an Apple Silicon package no longer ships. `inventory`
  lists them; `plan` adds a replacement or marks them `missing`; `uninstall`
  refuses while a recently used one would disappear without a decision.
  Found when removing an Intel Homebrew took `corepack` (bundled with Intel
  `node` 23, dropped from Node.js 25) away from a background service.
- Install the `corepack` formula for a recently used `corepack`. Drop Intel
  `yarn` and `pnpm` from the plan and uninstall them from `/opt/homebrew`
  first, since Homebrew's `corepack` conflicts with them and provides their
  commands.
- List LaunchAgents that have `/usr/local/bin` on their PATH.
- Date cask use from the installed app in `/Applications`, not the Caskroom.

## 0.1.0

- First release: `inventory`, `plan`, `install --yes`, `uninstall --yes`.
