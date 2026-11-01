# Changelog

All notable changes to the CodeBurn Omarchy shell plugin will be documented in this file.

## Unreleased

### Added
- **DeepSeek rates**: Popup section, after the period overview, showing the CLI's current peak or off-peak phase, the countdown to `nextChangeAt` in local time and UTC, the published UTC windows, and peak versus off-peak USD per 1M tokens (cache hit, cache miss, output) for each listed model. The current phase column is highlighted.
- **Bar phase**: When `deepseek.phase` is present, the badge reads `󰈸 $X.XX · peak` or `· off-peak`, and the tooltip includes the next flip. The phase label is the CLI's value at `generated`. The clock only counts down to `nextChangeAt`, and one refresh is issued after that instant so the next phase comes from the CLI.

### Changed
- `status.sh` resolves the GlorifiedTypist/codeburn fork (commit `a616400c46e9e3a8a7dfd5251eac751909843d61`) instead of `npx`/`bunx` `codeburn@0.9.27`. Order: `CODEBURN_BIN`, `codeburn` on `PATH`, `CODEBURN_HOME`, `~/.local/src/codeburn`, then `CODEBURN_PACKAGE` only if set. A git/`npx` install of the fork is not used because `dist/` is not published and there is no `prepare` script.

## [1.1.0] - 2026-08-19

### Added
- **Selectable Reporting Periods**: Switch reporting ranges directly inside the popup across **Today**, **7 Days**, **30 Days**, **Month**, **6 Months**, and **Lifetime**.
- **Keyboard Period Navigation**: Cycle periods using `←` / `→` arrows, `[` / `]`, or jump instantly using number keys `1`–`6`.
- **Fast Status Querying**: Added `--no-optimize --no-timeline` flags to background queries for lower latency and reduced JSON payload.
- **Session Persistence**: Retains selected period across popup toggles for the duration of the shell session.
- **Dynamic Bar Tooltip**: Shows active reporting period name alongside spend, calls, and session statistics.
- **IPC Handlers**: Added `setPeriod`, `nextPeriod`, and `prevPeriod` methods for scriptable shell control.

## [1.0.0] - 2026-08-19

### Added
- Initial release of the CodeBurn status bar widget for Omarchy.
- Concise bar badge displaying real-time daily AI spend (`󰈸 $X.XX`).
- Detailed interactive popup panel with overview metrics (Cost, Calls, Sessions, Cache Hit rate).
- Secondary token throughput breakdown (Input, Output, Cache read).
- Real-time provider spend breakdown (OpenCode, Anthropic, OpenAI, etc.).
- Top model consumption listing with proportional visual burn distribution meters.
- Task activity breakdown (Exploration, Coding, Conversation, Debugging).
- Resilient non-blocking background polling with auto-discovery of local `codeburn` CLI or pinned `npx`/`bunx` Git fallback.
- Unobtrusive error handling and recovery troubleshooting guidance.
- Full keyboard navigation and shortcuts (`R` to refresh, `Esc` to close).
