# omarchy-codeburn

> Lightweight, real-time AI spend and token usage tracker for the [Omarchy](https://omarchy.org/) status bar.

`omarchy-codeburn` is an Omarchy shell bar-widget plugin powered by [CodeBurn](https://github.com/GlorifiedTypist/codeburn). It gives you instant visibility into your AI assistant spend, active provider accounts (OpenCode, Anthropic, OpenAI, etc.), token throughput, model consumption, and the current DeepSeek peak or off-peak window directly from your desktop panel.

<p align="center">
  <img src="preview.png" alt="CodeBurn Omarchy Status Bar Widget and Analytics Popup" width="420" />
</p>

<a href="https://www.buymeacoffee.com/erzz"><img src="docs/buy-me-a-coffee.png" alt="Buy me a coffee" /></a>

---

## Features

- **Concise Bar Badge**: Displays spend at a glance (e.g. `󰈸 $10.70`) with automatic 5-minute background caching and refresh. DeepSeek phase stays out of the badge; the tooltip still mentions it and when it next flips.
- **Selectable Reporting Periods**: Switch reporting ranges on the fly with a single click or keystroke:
  - **Today** (default)
  - **7 Days**
  - **30 Days**
  - **Month**
  - **6 Months**
  - **Lifetime**
- **Rich Analytics Popup**:
  - **Period Overview**: Total cost, API call count, active sessions, and cache hit rate percentage.
  - **Token Throughput Strip**: Real-time input, output, and cache read tokens.
  - **Provider Spend Breakdown**: Granular cost tracking by provider (OpenCode, OpenAI, Anthropic, Fireworks, etc.).
  - **Top Models Breakdown**: Token spend per model with proportional visual burn distribution meters.
  - **Activity Breakdown**: Spend and turn counts grouped by activity (Exploration, Coding, Debugging, etc.).
  - **DeepSeek**: Current peak or off-peak state and a countdown to the next flip (local time and UTC), with the published UTC windows. Per-model USD rates are not shown. The section is hidden when the CLI omits `deepseek` or none of its fields are usable.
- **Local CodeBurn Fork**: Uses a `codeburn` binary on `PATH` first, then a build of [GlorifiedTypist/codeburn](https://github.com/GlorifiedTypist/codeburn) at `~/.local/src/codeburn`. That fork is what emits the `deepseek` object.
- **Unobtrusive Recovery UX**: When the fork is missing, offline, or usage logs are uninitialized, displays a graceful recovery hint rather than intrusive error dialogs. A missing `deepseek` object hides the DeepSeek section and leaves the rest of the panel alone.
- **Full Keyboard Navigation**: Supports standard Omarchy shortcuts (`←` / `→` for periods, `1`–`6` for direct jumps, `R` to refresh, `Esc` to close).

---

## Prerequisites

- **[Omarchy Linux](https://omarchy.org/)** with `omarchy-shell` (Quickshell).
- **Node.js >= 22.13** and **git**, used to build the CodeBurn fork below.
- A checkout of [GlorifiedTypist/codeburn](https://github.com/GlorifiedTypist/codeburn) at the commit that emits `deepseek` (see [Install the CodeBurn fork](#install-the-codeburn-fork)).

The published npm package `codeburn@0.9.27` does not emit `deepseek`. This plugin does not `npx` the fork: its `bin` is `dist/cli.js`, `dist/` is not in git, and the package has no `prepare` script, so a GitHub install cannot start.

---

## Installation

Add and enable the plugin directly using the Omarchy CLI:

```bash
omarchy plugin add https://github.com/GlorifiedTypist/omarchy-codeburn --enable
```

To position the widget in a specific location on the status bar (e.g., right next to `omarchy.agents`):

```bash
# Move or place next to existing widgets
omarchy bar move codeburn --after omarchy.agents
```

---

## Install the CodeBurn fork

`status.sh` resolves the CLI in this order. It never shell-evaluates the period; only `today`, `week`, `30days`, `month`, `all`, and `lifetime` are passed through.

1. **`CODEBURN_BIN`** — executable path, if that variable is set in the environment that launches Quickshell. This wins over `PATH`, so you can force the fork when an older `codeburn` is installed. A non-executable file is run with `node` when Node is available.
2. **`codeburn` on `PATH`**. The script prepends `~/.local/share/mise/shims` and `~/.local/bin`, then the session `PATH`. An older binary earlier in that list is what the bar will run, and the DeepSeek section stays hidden if that binary omits `deepseek`.
3. **`CODEBURN_HOME`** — checkout directory, if set in the Quickshell environment.
4. **`~/.local/src/codeburn`** — the default checkout. This needs no extra environment variable.
5. **`CODEBURN_PACKAGE`** — optional `npx` / `bunx` spec, only when you set it. Leave it unset for the fork. `CODEBURN_PACKAGE=codeburn@0.9.27` is the old npm pin and will not show the DeepSeek section.

A checkout is runnable when `dist/cli.js` and `dist/main.js` exist (`npm run build:cli`), or when `src/cli.ts` exists and `node_modules/tsx` is installed (`npm install`, then the repo's dev entry). The built bundle is preferred.

The pin below is [GlorifiedTypist/codeburn](https://github.com/GlorifiedTypist/codeburn) `main` after [PR #1](https://github.com/GlorifiedTypist/codeburn/pull/1) (DeepSeek peak/off-peak pricing). Cloning `main` is enough; the SHA is a documented fallback.

```bash
git clone https://github.com/GlorifiedTypist/codeburn.git ~/.local/src/codeburn
cd ~/.local/src/codeburn
# optional pin; main already includes the DeepSeek pricing work
# git checkout 5fc19cc539b4eda10a953db9e9eed02cd2d0ba8e
npm install
npm run build:cli
```

To prefer this build over a `codeburn` that appears later on `PATH`, link it into `~/.local/bin`. The script inserts that directory ahead of the inherited `PATH`:

```bash
mkdir -p ~/.local/bin
ln -sfn ~/.local/src/codeburn/dist/cli.js ~/.local/bin/codeburn
```

`~/.local/bin` is still after mise shims. If mise already provides `codeburn`, either retarget that shim or export `CODEBURN_BIN` to the fork's `dist/cli.js` in the session that starts Omarchy, not only in an interactive shell.

---

## Usage & Controls

- **Left-Click**: Toggle the CodeBurn details popup.
- **Right-Click**: Instantly trigger a live background data refresh.
- **Keyboard Shortcuts** (while popup is open):
  - `←` / `→` or `[` / `]` — Cycle through reporting periods
  - `1` to `6` — Direct jump to period (1: Today, 2: 7 Days, 3: 30 Days, 4: Month, 5: 6 Months, 6: Lifetime)
  - `R` — Refresh data immediately
  - `Esc` — Close popup
  - `Tab` / `Shift+Tab` — Switch between adjacent Omarchy panels

---

## Updating

Update to the latest version at any time with:

```bash
omarchy plugin update codeburn
```

---

## Uninstallation

To remove the plugin from your system:

```bash
omarchy plugin remove codeburn --yes
```

---

## Configuration

You can customize the polling interval directly in `~/.config/omarchy/shell.json` under your widget layout settings:

```json
{
  "id": "codeburn",
  "refreshIntervalSec": 300
}
```

---

## Attribution & Acknowledgments

This plugin interfaces with the **[GlorifiedTypist/codeburn](https://github.com/GlorifiedTypist/codeburn)** fork of [CodeBurn](https://github.com/getagentseal/codeburn), an open-source CLI for inspecting and optimizing LLM and AI coding assistant usage. DeepSeek peak and off-peak status is rendered from that fork's `menubar-json` `deepseek` object. The plugin does not reimplement the schedule, and the bar stays cost-only.

---

## License

[MIT](LICENSE) © 2026 Sean Erswell-Liljefelt
