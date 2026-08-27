# Google Calendar integration implementation

## Goal

Build a first working, read-only Google Calendar integration for Clock Hub on
`feature/google-calendar-integration`.

The MVP uses one Google account and the primary calendar. It reads only the
visible 42-day grid, stores OAuth refresh credentials in Linux Secret Service,
and keeps event data in memory only.

## Confirmed decisions

- Private MVP first, with clean extension points for a later public OAuth client.
- OAuth client status starts in Google `Testing`, then moves to `Production`
  after validation.
- Scope: `https://www.googleapis.com/auth/calendar.events.readonly`.
- Client file:
  `$XDG_CONFIG_HOME/io.github.nibra180.clock-hub/google-oauth-client.json`.
- Python standard-library helper, with `secret-tool` for refresh-token storage.
- No plaintext credential fallback and no persistent event cache.
- Connect is available in the event bar and settings menu.
- OAuth loopback binds to `127.0.0.1` and times out after two minutes.
- Fetch on panel open, debounced month changes, manual refresh, and every 15
  minutes while open. No event polling while closed.
- Calendar feature defaults to disabled.
- Day selection is mouse-only. Opening selects today; month changes select the
  first day. Clicking an adjacent-month day changes month and selects it.
- Selection uses a subtle fill; today keeps its existing border.
- Up to three accent dots are shown per day.
- A full-width event bar sits between the main hub row and System Status.
- The event bar shows the selected date, up to three events, `+N`, and refresh.
- `+N` exposes remaining events in a hover tooltip.
- Empty days show `No events` without collapsing the bar.
- Entries show start time and title; all-day events show `ALL DAY`; missing
  titles show `Busy`.
- Today's bar excludes past events, but day dots count them.
- Today's order: ongoing, all-day, upcoming. Other days: all-day, then start.
- Normal events, birthdays, focus time, out of office, and transparent events
  are included. Working-location, cancelled, and self-declined events are
  excluded.
- Multi-day events appear on every affected day.
- Timed events use the desktop time zone. All-day values remain calendar dates.
- Entries are display-only in the MVP.
- Network errors retain last-good RAM data and show its age. Auth failures clear
  event data and require reconnect.
- Disconnect revokes the Google token, clears keyring and RAM data, and leaves
  the feature enabled in its disconnected state.

## Proposed internal boundaries

### `tools/google-calendar-helper`

Commands:

- `status`
- `auth`
- `events --time-min <RFC3339> --time-max <RFC3339> --request-id <id>`
- `disconnect`

Every command writes one JSON object to stdout. Secrets never appear in argv,
stdout, or logs.

Normalized event fields:

- `id`
- `summary`
- `allDay`
- `start`
- `end`
- `eventType`
- `transparency`

### `GoogleCalendarProvider.qml`

Owns helper processes, connection state, request IDs, visible-range RAM cache,
refresh timers, debounce, stale-response rejection, and last-good state.

### `CalendarEventsBar.qml`

Owns presentation and actions for date, events, overflow tooltip, connect,
reconnect, refresh, loading, offline, and empty states.

### `Model.js`

Keeps pure date-range, event indexing, filtering, and sorting helpers that can be
tested with Node.

## Work breakdown and progress

- [x] Create feature branch.
- [x] Record agreed plan and progress in this file.
- [x] Implement and test Python OAuth/API helper.
- [x] Implement and test pure event/date model functions.
- [x] Implement QML provider.
- [x] Implement full-width event bar.
- [x] Integrate day selection and dots into `Panel.qml`.
- [x] Add manifest and quick-settings controls.
- [x] Update contract tests.
- [x] Update README and CHANGELOG.
- [x] Run Node and Python tests.
- [x] Run qmllint and plugin validation.
- [x] Run a shell smoke test with the missing-client state.
- [x] Complete a focused subagent security review and fix its high/medium findings.
- [ ] Test live OAuth in the default browser when the client file is available.

## Current blockers

- The OAuth client file is not present yet at the agreed path. The Google Cloud
  credentials page has been opened in the default browser. Live login, event
  retrieval, token refresh, and revoke testing require the downloaded Desktop
  client JSON at that path.

## Validation progress

- Node: 31 tests passed.
- Python: 24 tests passed.
- `qmllint`: passed for every plugin QML file, including both new components.
- `omarchy plugin validate`: passed.
- Shell restart and IPC-open smoke test: passed with no new calendar QML errors.
- Security recheck found no remaining high-severity issue. Its remaining medium
  findings were fixed by classifying auth failures as reconnectable, hardening
  process lifecycle generations, bounding the range cache, and validating the
  helper's date span.
- Visual smoke test: event rail renders full width and reports the missing OAuth
  client without breaking Media, Calendar, Agents, or System Status.

## Validation commands

```bash
node --test test/*.test.js
python3 -m unittest discover -s test -p 'test_google_calendar_helper.py'
python3 -m py_compile tools/google-calendar-helper
qmllint -I /usr/share/omarchy/shell \
  AgentsHub.qml CalendarEventsBar.qml GoogleCalendarProvider.qml \
  HubSettingsMenu.qml MediaHub.qml Panel.qml SystemStatus.qml VinylIndicator.qml
omarchy plugin validate \
  ~/.config/omarchy/plugins/io.github.nibra180.clock-hub
```

Manual checks include horizontal and vertical bars, light and dark themes,
missing client file, locked or missing keyring, offline last-good data, rejected
or cancelled events, all-day and multi-day events, month boundaries, midnight,
and OAuth success, timeout, reconnect, and disconnect.
