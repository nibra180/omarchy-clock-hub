# Omarchy Clock Hub

A theme-aware replacement for `omarchy.clock` that turns the clock popup into
a compact desktop hub.

![Omarchy Clock Hub showcase](assets/img/showcase.png)

## Features

- Configurable weekday, ISO week, date, and time label
- Animated, theme-aware now-playing indicator with Vinyl, Equalizer, and Pulse styles
- Full Omarchy calendar with week numbers and month navigation
- Optional year- and life-progress bars above the calendar
- MPRIS media card with clickable artwork, progress, and playback controls
- Omarchy Agents dashboard with provider limits, daily usage, and model totals
- Live CPU, memory, and root-disk status with a btop shortcut
- Manifest-backed toggles for Media, Agents, and System Status
- Automatic upstream change detection after `omarchy update`

The hub reuses Omarchy's running `omarchy.media` service and the live
`omarchy.agents` widget. It does not start duplicate media or usage collectors.

## Requirements

- Omarchy 4.0 or newer
- The stock `omarchy.media` service when the Media section is enabled
- `omarchy.agents` in the bar when the Agents section is enabled
- `bash`, `awk`, `df`, and the Linux `/proc` filesystem when System Status is enabled

## Installation

Review third-party plugins before enabling them. Then install from GitHub:

```bash
omarchy plugin add https://github.com/nibra180/omarchy-clock-hub.git --enable
```

Omarchy places the plugin in:

```text
~/.config/omarchy/plugins/io.github.nibra180.clock-hub/
```

The plugin declares `clonedFrom: omarchy.clock`, so enabling it replaces the
stock clock while retaining Omarchy's clock IPC routes.

## Recommended clock format

Add or adjust the Clock Hub entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "io.github.nibra180.clock-hub",
  "format": "'KW'ww · dddd, dd.MM.yyyy · HH:mm"
}
```

Right-clicking the clock cycles through the available formats. Left-clicking
opens the hub; middle-clicking opens Omarchy's timezone picker.

## Widget settings

Media, Agents, and System Status are enabled by default. Toggle them from the
settings button in the calendar's upper-right corner. Changes apply immediately
and persist in `shell.json`.
Disabling Media also removes the now-playing indicator and tooltip from the
bar. The calendar and optional life-progress feature remain available.

The bar indicator defaults to Vinyl. Choose Vinyl, Equalizer, or Pulse from the
same hub settings menu. You can also script settings with `omarchy bar set`.

## Optional upstream notifications

Install the included post-update hook:

```bash
omarchy hook install post-update \
  ~/.config/omarchy/plugins/io.github.nibra180.clock-hub/tools/post-update-check
```

It only reports upstream changes. It never overwrites local QML. See
[`UPSTREAMS.md`](UPSTREAMS.md) for the review workflow.

## Development

```bash
node --test test/*.test.js
qmllint -I /usr/share/omarchy/shell AgentsHub.qml HubSettingsMenu.qml MediaHub.qml Panel.qml SystemStatus.qml VinylIndicator.qml
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nibra180.clock-hub
omarchy restart shell
```

The Node suite covers the pure calendar and clock model plus the public Omarchy
plugin contracts. It uses only Node's built-in test runner.

Plugin files hot-reload while editing. Keep personal settings in
`~/.config/omarchy/shell.json`; do not commit them to this repository.

## License

MIT. This project contains code derived from Omarchy and Asked Dashboard, and was inspired by Ruixen Shell.
See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
