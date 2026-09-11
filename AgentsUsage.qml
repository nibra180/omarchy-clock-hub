import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Read-only view of the usage JSON files omarchy-agent-usage-update writes.
// The hub prefers the live omarchy.agents widget; PluginBarApi no longer
// hands that widget to a third-party clock, so this is the fallback.
Item {
  id: root
  visible: false

  property bool panelOpen: false
  property bool watchFiles: true

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy/agents/usage"

  property var agentIds: []
  property int dataRevision: 0
  property string selectedProviderId: ""
  property string pendingUpdateKind: ""

  readonly property var providers: {
    var rev = dataRevision
    var result = []
    for (var i = 0; i < agentInstantiator.count; i++) {
      var agent = agentInstantiator.objectAt(i)
      var display = Model.agentDisplayProvider(agent ? agent.record : null)
      if (display && Model.agentHasUsageData(display)) result.push(display)
    }
    return result
  }

  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }

  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null
  readonly property var limits: Model.agentLimitWindows(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  readonly property bool alarming: {
    var windows = limits
    for (var i = 0; i < windows.length; i++)
      if (windows[i].percent >= 0.9) return true
    return !!balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1
  }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() { runUpdate("force") }
  function refreshLimits() { runUpdate("limits") }

  function rescanAgents() {
    if (!listProcess.running) listProcess.running = true
  }

  function runUpdate(kind) {
    if (updateProcess.running) {
      if (kind === "force" || pendingUpdateKind === "") pendingUpdateKind = kind
      return
    }
    updateProcess.command = kind === "force"
      ? ["omarchy-agent-usage-update", "--force"]
      : ["omarchy-agent-usage-update", "--limits-only"]
    updateProcess.running = true
  }

  function applyAgentListing(output) {
    var ids = []
    var lines = String(output || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var name = lines[i].trim()
      if (name.slice(-5) === ".json") ids.push(name.slice(0, -5))
    }
    ids.sort()
    if (JSON.stringify(ids) !== JSON.stringify(agentIds)) agentIds = ids
    else dataRevision++
  }

  function rebuildAgents() {
    dataRevision++
  }

  onPanelOpenChanged: if (panelOpen) {
    if (watchFiles) rescanAgents()
    refreshLimits()
  }

  onWatchFilesChanged: if (watchFiles && panelOpen) rescanAgents()

  Process {
    id: listProcess
    running: false
    command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAgentListing(text)
    }
  }

  Process {
    id: updateProcess
    running: false
    onExited: {
      if (root.watchFiles) root.rescanAgents()
      if (root.pendingUpdateKind !== "") {
        var kind = root.pendingUpdateKind
        root.pendingUpdateKind = ""
        root.runUpdate(kind)
      }
    }
  }

  Instantiator {
    id: agentInstantiator
    model: root.watchFiles ? root.agentIds : []

    delegate: Item {
      id: agentItem
      required property var modelData
      property var record: null

      FileView {
        path: root.usageDir + "/" + modelData + ".json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
          try {
            var parsed = JSON.parse(String(text() || ""))
            agentItem.record = parsed && typeof parsed === "object" ? parsed : null
          } catch (e) {
            agentItem.record = null
          }
          root.rebuildAgents()
        }
        onLoadFailed: {
          agentItem.record = null
          root.rebuildAgents()
        }
      }
    }

    onObjectAdded: function() { root.rebuildAgents() }
    onObjectRemoved: function() { root.rebuildAgents() }
  }
}
