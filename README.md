# Omarchy Clock Hub

A theme-aware replacement for `omarchy.clock` that turns the clock popup into
a compact desktop hub.

![Omarchy Clock Hub showcase](assets/img/showcase.png)

## Features

- Configurable weekday, ISO week, date, and time label
- Animated, theme-aware now-playing indicator with Vinyl, Equalizer, and Pulse styles
- Full Omarchy calendar with week numbers, month navigation, and optional read-only Google Calendar events
- Year progress above the calendar, with an optional life-progress bar
- MPRIS media card with clickable artwork, progress, and playback controls
- Omarchy Agents dashboard with provider limits, reset countdowns, daily usage, and model totals
- Live CPU, memory, and root-disk status with a btop shortcut
- Theme-aware progress fills, with stock Omarchy styling for readable model rows
- Manifest-backed toggles for Media, Agents, System Status, and Google Calendar
- Automatic upstream change detection after `omarchy update`

The hub reuses Omarchy's running `omarchy.media` service and the live
`omarchy.agents` widget. It does not start duplicate media or usage collectors.

## Requirements

- Omarchy 4.0 or newer
- The stock `omarchy.media` service when the Media section is enabled
- `omarchy.agents` in the bar when the Agents section is enabled
- `bash`, `awk`, `df`, and the Linux `/proc` filesystem when System Status is enabled
- `python3` and `secret-tool` when Google Calendar is enabled

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
  "format": "'KW'ww · dddd, dd.MM.yyyy · HH:mm",
  "verticalFormat": "HH\n—\nmm"
}
```

Right-clicking the clock cycles through the available formats for that bar
orientation and writes the next one to `shell.json`. Left-clicking opens the
hub; middle-clicking opens Omarchy's timezone picker.

## Widget settings

Media, Agents, and System Status are enabled by default. Google Calendar is
not. Toggle them from the settings button in the calendar's upper-right
corner, or press `s` while the hub is focused. Changes apply immediately and
persist in `shell.json`.
Disabling Media also removes the now-playing indicator and tooltip from the
bar. The calendar and optional life-progress feature remain available.

The now-playing indicator defaults to Equalizer and only appears on a
horizontal bar while audio is playing. Choose Vinyl, Equalizer, or Pulse from
the same hub settings menu. You can also script settings with `omarchy bar set`.

## Calendar

The year bar is always shown. Double-click it, enter a birth year and a life
expectancy, then press Enter to add a life-progress bar underneath. Double-click
that bar to hide it again. The expectancy stays in `shell.json` so the next
birth year you enter reuses it.

Weeks follow the desktop locale's first day. Click the `W` heading, or press
`w` with the hub focused, to switch between Sunday and Monday.

With the hub focused:

- Left / Right: previous or next day
- Up / Down: same weekday in the previous or next week
- `[` / `]`: previous or next month
- `{` / `}`: previous or next year
- `t` or Enter: jump to today
- `w`: toggle week start
- `s`: open hub settings

Day selection follows the date across month and year boundaries. Mouse wheel
over the grid steps by month.

## Google Calendar

Google Calendar support is disabled by default and reads only the primary
calendar. Enabling it adds up to three event dots to each day and a full-width
selected-day event rail above System Status. The rail shows at most three events
as plain entries separated by hairlines; hover `+N` to inspect the remainder.
Timed entries show their start time and title, while all-day entries show only
the title. On the current day, timed events that have already ended are omitted
from the rail; all-day events stay.

The integration uses the read-only
`https://www.googleapis.com/auth/calendar.events.readonly` OAuth scope. Create a
Google OAuth client of type **Desktop app**, download its JSON file, and save it
at:

```text
${XDG_CONFIG_HOME:-~/.config}/io.github.nibra180.clock-hub/google-oauth-client.json
```

Restrict the file to your user, enable Google Calendar in the hub settings, then
press **Connect Google Calendar**. If the sign-in later expires, the same row
becomes **Reconnect Google Calendar**. Sign-in opens in the default browser and
waits for a loopback callback on `127.0.0.1` for up to two minutes.

The refresh token is stored through Linux Secret Service. Clock Hub does not
store tokens in `shell.json` and has no plaintext fallback. Event title, type,
start, and end remain in shell memory only and are discarded when the shell
restarts. Disconnect removes the local secret and attempts to revoke the Google
token. If Google is unreachable, the local credential is still removed and the
UI reports that remote revocation could not be confirmed.

For a personal OAuth project left in Google's **Testing** publishing state,
Calendar refresh tokens expire after seven days. Use Testing while developing,
then move the personal consent screen to Production after validating the flow if
you need a lasting login.

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
python3 -m unittest discover -s test -p 'test_google_calendar_helper.py'
python3 -m py_compile tools/google-calendar-helper
qmllint -I /usr/share/omarchy/shell AgentsHub.qml CalendarEventsBar.qml GoogleCalendarProvider.qml HubSettingsMenu.qml MediaHub.qml Panel.qml SystemStatus.qml ThemeProgressBar.qml VinylIndicator.qml
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
