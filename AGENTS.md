# Project guide

## Purpose

Clock Hub is an Omarchy 4 bar-widget plugin. It replaces `omarchy.clock` with a
QML popup that combines the clock, calendar, MPRIS controls, agent usage, and
system status. The repository has no package manager or build step.

## Repository map

- `BarWidget.qml` is the plugin entry point and owns the clock label.
- `Panel.qml` coordinates the popup and persists widget settings.
- `AgentsHub.qml`, `MediaHub.qml`, `SystemStatus.qml`, and
  `VinylIndicator.qml` implement focused UI sections.
- `Model.js` contains Qt-independent date, calendar, and format logic.
- `manifest.json` defines the public plugin identity and entry point.
- `tools/check-upstreams` and `tools/post-update-check` track changes in the
  Omarchy and Ruixen sources listed in `UPSTREAMS.md`.

## Compatibility contracts

- Keep the plugin ID `io.github.nibra180.clock-hub` and the cloned module name
  and IPC target `omarchy.clock` unless a migration is part of the task.
- Preserve `open()`, `close()`, `opened`, and popout handoff behavior on the bar
  widget. Omarchy uses that shape to route panel and IPC actions.
- Reuse the running `omarchy.media` service and mounted `omarchy.agents` widget.
  Do not add duplicate collectors or background polling.
- Treat injected `bar`, service, player, and agents objects as optional. The UI
  must still instantiate when one is unavailable.
- Keep reusable date and format calculations in `Model.js`. It must remain free
  of QML and Qt dependencies and export testable functions through
  `module.exports`.
- Persist widget options through the existing settings copy and
  `updateEntryInline` flow. Never commit personal values from
  `~/.config/omarchy/shell.json`.

## Code and UI conventions

- Follow the existing QML style: two-space indentation, `root` IDs, typed
  properties where practical, early returns, and short comments for non-obvious
  host-shell behavior.
- Use `Style.space`, `Style.font`, `Style.cornerRadius`, `Color`, `BorderSurface`,
  and the shared `qs.Commons` and `qs.Ui` controls. Avoid fixed styling that
  breaks theme changes or display scaling.
- Check horizontal and vertical bars, light and dark themes, an empty media
  state, and a missing agents widget when changing UI behavior.
- Keep user-facing copy consistent with the current English interface.
- Update `README.md` and `CHANGELOG.md` when behavior or configuration changes.
  Update `THIRD_PARTY_NOTICES.md` when incorporating outside code or assets.
- Do not accept or overwrite upstream baselines as part of unrelated work. Use
  the review flow in `UPSTREAMS.md` only when the task concerns upstream sync.

## Validation

Run the relevant checks before reporting completion:

```bash
node --test test/*.test.js
qmllint -I /usr/share/omarchy/shell AgentsHub.qml HubSettingsMenu.qml MediaHub.qml Panel.qml SystemStatus.qml VinylIndicator.qml
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nibra180.clock-hub
```

For shell-script changes, also run `bash -n` on each changed script and
`shellcheck` when it is installed. Add or update `test/*.test.js` coverage when
changing `Model.js` or a tested host-shell contract. Use `omarchy restart shell`
for manual UI verification and state exactly which checks you ran.
