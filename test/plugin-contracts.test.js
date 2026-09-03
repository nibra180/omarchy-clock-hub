const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const projectRoot = path.resolve(__dirname, "..")

function read(relativePath) {
  return fs.readFileSync(path.join(projectRoot, relativePath), "utf8")
}

test("manifest exposes the expected Omarchy clock replacement", () => {
  const manifest = JSON.parse(read("manifest.json"))

  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "io.github.nibra180.clock-hub")
  assert.deepEqual(manifest.kinds, ["bar-widget"])
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml")
  assert.equal(manifest.omarchy.clonedFrom, "omarchy.clock")
  assert.equal(fs.existsSync(path.join(projectRoot, manifest.entryPoints.barWidget)), true)
})

test("bar widget preserves the clock module and IPC contract", () => {
  const source = read("BarWidget.qml")

  assert.match(source, /moduleName:\s*"omarchy\.clock"/)
  assert.match(source, /IpcHandler\s*{[\s\S]*?target:\s*"omarchy\.clock"/)
  assert.match(source, /readonly property bool opened:/)
  assert.match(source, /function open\(\)/)
  assert.match(source, /function close\(\)/)
  assert.match(source, /function closeForPopoutSwitch\(\)/)
})

test("nested panel delegates IPC ownership to the bar widget", () => {
  const source = read("Panel.qml")

  assert.match(source, /moduleName:\s*"omarchy\.clock"/)
  assert.match(source, /ipcTarget:\s*"omarchy\.clock"/)
  assert.match(source, /manageIpc:\s*false/)
  assert.match(source, /readonly property var barIdentity:\s*hostWidget \|\| root/)
})

test("hub reuses mounted media and agents providers", () => {
  const barWidget = read("BarWidget.qml")
  const panel = read("Panel.qml")

  assert.match(barWidget, /firstPartyServiceFor\("omarchy\.media"\)/)
  assert.match(panel, /firstPartyServiceFor\("omarchy\.media"\)/)
  assert.match(panel, /moduleWidgets\("omarchy\.agents"\)/)
})

test("agent model usage mirrors the mounted Agents panel", () => {
  const source = read("AgentsHub.qml")

  assert.match(source, /readonly property var models:[\s\S]*?agentsWidget\.models/)
  assert.match(source, /text:\s*"TOKENS BY MODEL"/)
  assert.match(source, /component ModelRow:/)
  assert.match(source, /share:\s*modelData\.total \/ Math\.max\(1, root\.models\[0\]\.total\)/)
  assert.match(source, /cache read/)
  assert.match(source, /cache write/)
  assert.match(source, /limit\.resetAt \|\| limit\.resetsAt/)
  assert.match(source, /interval:\s*30000/)
  assert.match(source, /running:\s*root\.panelOpen/)

  const modelRow = source.slice(
    source.indexOf("component ModelRow:"),
    source.indexOf("component DayRow:")
  )
  assert.doesNotMatch(modelRow, /ThemeProgressBar/)
  assert.match(modelRow, /root\.alpha\(root\.foreground, 0\.05\)/)
  assert.match(modelRow, /root\.alpha\(root\.foreground, 0\.14\)/)
})

test("number keys select the first two ordered agent providers", () => {
  const hub = read("AgentsHub.qml")
  const panel = read("Panel.qml")

  assert.match(hub, /function selectProviderAt\(index\)/)
  assert.match(hub, /selectProvider\(orderedProviders\[index\]\)/)
  assert.match(hub, /iconText: index < 2 \? String\(index \+ 1\) : ""/)
  assert.match(panel, /\(t === "1" \|\| t === "2"\) && root\.showAgents/)
  assert.match(panel, /agentsHub\.selectProviderAt\(Number\(t\) - 1\)/)
})

test("section settings stay aligned across manifest and panel", () => {
  const manifest = JSON.parse(read("manifest.json"))
  const barWidget = read("BarWidget.qml")
  const panel = read("Panel.qml")
  const schema = Object.fromEntries(manifest.barWidget.schema.map((item) => [item.key, item]))
  const keys = ["showMedia", "showAgents", "showSystemStatus"]

  assert.deepEqual(
    Object.keys(manifest.barWidget.defaults).sort(),
    [...keys, "showGoogleCalendar", "mediaIndicatorStyle"].sort()
  )
  for (const key of keys) {
    assert.equal(manifest.barWidget.defaults[key], true)
    assert.equal(schema[key].type, "boolean")
    assert.equal(schema[key].defaultValue, true)
    assert.match(panel, new RegExp(`setting\\("${key}", true\\)`))
    assert.match(panel, new RegExp(`toggleSection\\("${key}"`))
  }

  assert.equal(manifest.barWidget.defaults.showGoogleCalendar, false)
  assert.equal(schema.showGoogleCalendar.type, "boolean")
  assert.equal(schema.showGoogleCalendar.defaultValue, false)
  assert.match(panel, /setting\("showGoogleCalendar", false\) === true/)
  assert.match(panel, /toggleSection\("showGoogleCalendar"/)

  assert.equal(fs.existsSync(path.join(projectRoot, "HubSettingsMenu.qml")), true)
  assert.match(barWidget, new RegExp(`settingsEntryId:\\s*"${manifest.id.replace(/\./g, "\\.")}"`))
  assert.match(panel, new RegExp(`settingsEntryId:\\s*"${manifest.id.replace(/\./g, "\\.")}"`))
  assert.match(barWidget, /setting\("showMedia", true\) === true/)
  assert.match(barWidget, /updateEntryInline\(root\.settingsEntryId, entry\)/)
  assert.match(panel, /updateEntryInline\(root\.settingsEntryId, entry\)/)
  assert.match(panel, /panelOpen:\s*root\.opened && root\.showMedia/)
  assert.match(panel, /panelOpen:\s*root\.opened && root\.showAgents/)
  assert.match(panel, /running:\s*root\.opened && root\.showSystemStatus/)
})

test("Google Calendar stays read-only and outside shell settings", () => {
  const manifest = JSON.parse(read("manifest.json"))
  const panel = read("Panel.qml")
  const provider = read("GoogleCalendarProvider.qml")
  const helper = read("tools/google-calendar-helper")
  const settingsMenu = read("HubSettingsMenu.qml")

  assert.equal(fs.existsSync(path.join(projectRoot, "CalendarEventsBar.qml")), true)
  assert.equal(fs.existsSync(path.join(projectRoot, "GoogleCalendarProvider.qml")), true)
  assert.equal(fs.existsSync(path.join(projectRoot, "tools/google-calendar-helper")), true)
  assert.equal(manifest.barWidget.defaults.showGoogleCalendar, false)
  assert.doesNotMatch(JSON.stringify(manifest), /refresh.?token|access.?token|client.?secret/i)
  assert.match(provider, /panelOpen:\s*false/)
  assert.match(provider, /running:\s*root\.enabled && root\.panelOpen && root\.authenticated/)
  assert.match(panel, /GoogleCalendarProvider\s*{/)
  assert.match(panel, /CalendarEventsBar\s*{/)
  assert.match(settingsMenu, /signal calendarConnectRequested\(\)/)
  assert.match(settingsMenu, /signal calendarDisconnectRequested\(\)/)
  assert.match(helper, /calendar\.events\.readonly/)
  assert.doesNotMatch(helper, /calendar\.events(?:["'])/)
})

test("calendar keyboard navigation and event presentation stay aligned", () => {
  const panel = read("Panel.qml")
  const eventBar = read("CalendarEventsBar.qml")

  assert.match(panel, /function moveDay\(delta\)[\s\S]*?Model\.stepDay/)
  assert.match(panel, /if \(dx !== 0\) root\.moveDay\(dx\)/)
  assert.match(panel, /if \(dy !== 0\) root\.moveDay\(dy \* 7\)/)
  assert.match(eventBar, /if \(event && event\.allDay === true\) return ""/)
  assert.match(eventBar, /id:\s*eventSeparator/)
  assert.match(eventBar, /required property int index/)
  assert.match(eventBar, /anchors\.leftMargin:\s*Style\.spacing\.xxxl/)
  assert.match(eventBar, /anchors\.rightMargin:\s*Style\.spacing\.xxxl/)
  assert.match(eventBar, /PanelActionButton\s*{[\s\S]*?Refresh calendar/)
  assert.doesNotMatch(eventBar, /return "ALL DAY"/)
})

test("hub progress bars reuse the active theme border gradient", () => {
  const progress = read("ThemeProgressBar.qml")

  assert.match(progress, /Border\.hyprlandActiveSpec\(Color\.accent, 0\)/)
  assert.match(progress, /activeSpec\.gradient\.colors/)
  assert.match(progress, /urgent \? \[urgentColor\] : themeColors/)

  for (const file of ["Panel.qml", "SystemStatus.qml", "AgentsHub.qml", "MediaSourceCard.qml"])
    assert.match(read(file), /ThemeProgressBar\s*{/)
})

test("now-playing indicator styles stay aligned across manifest and bar widget", () => {
  const manifest = JSON.parse(read("manifest.json"))
  const barWidget = read("BarWidget.qml")
  const panel = read("Panel.qml")
  const indicator = read("VinylIndicator.qml")
  const setting = manifest.barWidget.schema.find((item) => item.key === "mediaIndicatorStyle")

  assert.equal(manifest.barWidget.defaults.mediaIndicatorStyle, "Equalizer")
  assert.equal(setting.type, "enum")
  assert.deepEqual(setting.options, ["Vinyl", "Equalizer", "Pulse"])
  assert.equal(setting.defaultValue, "Equalizer")
  assert.match(barWidget, /setting\("mediaIndicatorStyle", "Equalizer"\)/)
  assert.match(barWidget, /variant:\s*root\.mediaIndicatorStyle/)
  assert.match(panel, /setting\("mediaIndicatorStyle", "Equalizer"\)/)
  assert.match(panel, /indicatorStyle:\s*root\.mediaIndicatorStyle/)
  assert.match(panel, /persistSettings\(\{ mediaIndicatorStyle: style \}\)/)
  assert.match(panel, /onIndicatorStyleSelected:/)
  assert.match(indicator, /property string variant:\s*"Equalizer"/)
  assert.match(indicator, /root\.variant === "Equalizer"/)
  assert.match(indicator, /root\.variant === "Pulse"/)
})

test("the media carousel reuses the MPRIS service for every source", () => {
  const hub = read("MediaHub.qml")
  const card = read("MediaSourceCard.qml")
  const panel = read("Panel.qml")

  // One card per source, addressed by key rather than by the service's own
  // notion of an active player.
  assert.match(hub, /mediaService\.sourcePlayers/)
  assert.match(hub, /model:\s*root\.sources/)
  assert.match(hub, /orientation:\s*ListView\.Horizontal/)
  assert.match(hub, /snapMode:\s*ListView\.SnapOneItem/)
  assert.match(card, /root\.actionRequested\(action\)/)
  assert.match(hub, /mediaService\.runAction\(action, false, focusedKey\)/)
  assert.match(hub, /onActionRequested: function\(action\) { root\.runActionOn\(index, action\) }/)

  // Browsing stays local to the hub and never moves playback or changes the
  // media service's preferred player.
  assert.doesNotMatch(hub, /mediaService\.selectPlayer/)
  assert.doesNotMatch(hub, /switchSource|\.play\(\)|\.pause\(\)/)

  // Pausing a card must not move it. The order ignores playback state, every
  // action pins the card it acted on, and a model rebuild restores the view
  // without animating.
  assert.match(hub, /Model\.orderedMediaSources\(mediaService\.sourcePlayers/)
  assert.match(hub, /function runActionOn\(index, action\)[\s\S]*?focusedKey = mediaService\.playerKey\(player\)[\s\S]*?mediaService\.runAction/)
  assert.match(hub, /var handled = mediaService\.runAction\(action, false, focusedKey\)/)
  assert.match(hub, /if \(handled && \(action === "next" \|\| action === "previous"\)\) trackPosition = 0/)
  assert.match(hub, /return handled/)
  assert.match(hub, /function togglePlayPause\(\)\s*{\s*\n\s*return runActionOn\(focusedIndex, "playPause"\)/)
  assert.match(hub, /onSourcesChanged: Qt\.callLater\(restoreCarousel\)/)
  assert.match(hub, /function restoreCarousel\(\)[\s\S]*?positionViewAtIndex\(focusedIndex, ListView\.SnapPosition\)/)

  // Swiping counts as picking a source only when the move began at the
  // pointer; a programmatic reposition must not steal the focus.
  assert.match(hub, /onDragStarted: root\.userMovingCarousel = true/)
  assert.match(hub, /onFlickStarted: root\.userMovingCarousel = true/)
  assert.match(hub, /onMovementEnded: {\s*\n\s*if \(!root\.userMovingCarousel\) return/)

  // Carousel chrome appears only with something to switch between.
  assert.match(hub, /hasMultipleSources:\s*sources\.length > 1/)
  assert.match(hub, /id:\s*navRow[\s\S]*?visible:\s*root\.hasMultipleSources/)
  assert.match(hub, /id:\s*dotsRow[\s\S]*?text:\s*"p"[\s\S]*?Repeater\s*{[\s\S]*?text:\s*"n"/)
  assert.match(hub, /id:\s*dotsRow[\s\S]*?transform:\s*Translate\s*{ y: -Style\.space\(6\) }/)
  assert.match(hub, /id:\s*dotsRow[\s\S]*?visible:\s*root\.hasMultipleSources/)

  // No second collector or poller: one timer for the visible card's position.
  assert.equal(hub.match(/\bTimer\s*{/g).length, 1)
  assert.doesNotMatch(card, /\bTimer\s*{/)

  assert.match(panel, /root\.showMedia\) mediaHub\.stepSource\(1\)/)
  assert.match(panel, /root\.showMedia\) mediaHub\.stepSource\(-1\)/)
})

test("Space toggles the focused source while Enter still jumps to today", () => {
  const hub = read("MediaHub.qml")
  const panel = read("Panel.qml")

  // Space and Enter both reach the panel as activateRequested. Telling them
  // apart depends on Enter emitting returnRequested first, in the same key
  // event, so both halves of that handshake have to stay in place.
  assert.match(panel, /onReturnRequested:\s*root\.activateFromReturn = true/)
  assert.match(panel, /var fromReturn = root\.activateFromReturn/)
  assert.match(panel, /root\.activateFromReturn = false/)
  assert.match(panel, /if \(fromReturn\) {\s*\n\s*root\.goToToday\(\)/)
  assert.match(panel, /if \(!root\.showMedia \|\| !mediaHub\.togglePlayPause\(\)\) root\.goToToday\(\)/)

  // The toggle addresses the card in view, not the service's active player,
  // and goes through the same pinning path as the card buttons.
  assert.match(hub, /function togglePlayPause\(\)\s*{\s*\n\s*return runActionOn\(focusedIndex, "playPause"\)/)
})
