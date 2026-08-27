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
})

test("section settings stay aligned across manifest and panel", () => {
  const manifest = JSON.parse(read("manifest.json"))
  const barWidget = read("BarWidget.qml")
  const panel = read("Panel.qml")
  const schema = Object.fromEntries(manifest.barWidget.schema.map((item) => [item.key, item]))
  const keys = ["showMedia", "showAgents", "showSystemStatus"]

  assert.deepEqual(Object.keys(manifest.barWidget.defaults).sort(), [...keys, "mediaIndicatorStyle"].sort())
  for (const key of keys) {
    assert.equal(manifest.barWidget.defaults[key], true)
    assert.equal(schema[key].type, "boolean")
    assert.equal(schema[key].defaultValue, true)
    assert.match(panel, new RegExp(`setting\\("${key}", true\\)`))
    assert.match(panel, new RegExp(`toggleSection\\("${key}"`))
  }

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
