# Upstream maintenance

This plugin is a local fork of `omarchy.clock` with a custom media and agents
hub. Upstream files are never copied over the customization automatically.

## What is tracked

- Omarchy's stock clock implementation
- Omarchy's MPRIS media service
- Omarchy's agents widget and data model
- `ruixen.media` and `ruixen.notch` from Ruixen Shell

The current reviewed revisions and source hashes live in `UPSTREAMS.json`.
Reviewed Omarchy snapshots and generated reports are stored outside the plugin
at:

```text
~/.local/state/omarchy/io-github-nibra180-clock-hub-upstreams/
```

## Checking

A check runs automatically after `omarchy update`. Run the same check manually:

```bash
~/.config/omarchy/plugins/io.github.nibra180.clock-hub/tools/check-upstreams
```

When changes are found, inspect the report path printed by the command. Reports
contain one diff per changed Omarchy component and a Ruixen diff or compare URL.

## Accepting a reviewed upstream

First adapt and test this plugin as needed. Then mark the current upstream state
as reviewed:

```bash
~/.config/omarchy/plugins/io.github.nibra180.clock-hub/tools/check-upstreams --accept
```

Commit the resulting `UPSTREAMS.json` update together with any compatibility
changes. `--accept` only advances the review baseline; it never modifies QML.

## Validation

```bash
qmllint -I /usr/share/omarchy/shell ./*.qml
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nibra180.clock-hub
omarchy restart shell
```
