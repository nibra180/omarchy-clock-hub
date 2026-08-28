import QtQuick
import Quickshell.Io

// Process boundary around the local OAuth/API helper. Tokens never enter QML;
// this component only sees connection state and normalized event JSON.
Item {
  id: root

  property bool enabled: false
  property bool panelOpen: false
  property date rangeStart: new Date(0)
  property date rangeEnd: new Date(0)

  property string state: "disabled"
  property string statusText: ""
  property bool authenticated: false
  property bool refreshing: false
  property bool authorizing: false
  property var events: []
  property date lastUpdated: new Date(0)

  readonly property string helperPath: decodeURIComponent(
    String(Qt.resolvedUrl("tools/google-calendar-helper")).replace(/^file:\/\//, ""))
  readonly property bool busy: statusProcess.running || authProcess.running
    || eventsProcess.running || disconnectProcess.running

  property var _cache: ({})
  property var _cacheOrder: []
  property string _activeRequestId: ""
  property string _activeRangeKey: ""
  property bool _fetchPending: false
  property bool _forcePending: false
  property string _statusOutput: ""
  property string _statusError: ""
  property string _authOutput: ""
  property string _authError: ""
  property string _eventsOutput: ""
  property string _eventsError: ""
  property string _disconnectOutput: ""
  property string _disconnectError: ""
  property int _generation: 0
  property int _statusGeneration: -1
  property int _authGeneration: -1
  property int _eventsGeneration: -1
  property int _disconnectGeneration: -1

  signal connectionChanged()

  function validRange() {
    return rangeStart && rangeEnd
      && rangeStart.getTime() > 0
      && rangeEnd.getTime() > rangeStart.getTime()
  }

  function rangeKey() {
    if (!validRange()) return ""
    return rangeStart.toISOString() + "/" + rangeEnd.toISOString()
  }

  function requestId() {
    return Date.now().toString(36) + "-" + Math.floor(Math.random() * 0x1000000).toString(36)
  }

  function parsePayload(output) {
    var raw = String(output || "").trim()
    if (raw === "") return null
    try {
      return JSON.parse(raw)
    } catch (e) {
      return null
    }
  }

  function errorCode(payload) {
    if (!payload) return ""
    if (typeof payload.error === "string") return payload.error
    if (payload.error && payload.error.code) return String(payload.error.code)
    return String(payload.code || "")
  }

  function errorMessage(payload, fallback) {
    if (!payload) return fallback
    if (payload.message) return String(payload.message)
    if (payload.error && payload.error.message) return String(payload.error.message)
    return fallback
  }

  function clearEventData() {
    root._cache = ({})
    root._cacheOrder = []
    root.events = []
    root.lastUpdated = new Date(0)
  }

  function applyFailure(payload, fallback) {
    var code = errorCode(payload)
    root.statusText = errorMessage(payload, fallback)

    if (code === "missing_client" || code === "invalid_client"
        || code === "invalid_client_config") {
      root.authenticated = false
      root.clearEventData()
      root.state = "missing_client"
    } else if (code === "keyring_unavailable" || code === "keyring_locked"
        || code === "keyring_error" || code === "missing_dependency") {
      root.authenticated = false
      root.clearEventData()
      root.state = "keyring_unavailable"
    } else if (code === "invalid_grant" || code === "reauth_required"
        || code === "unauthorized" || code === "authentication_required"
        || code === "authentication_error") {
      root.authenticated = false
      root.clearEventData()
      root.state = "reauth_required"
    } else if (root.events.length > 0) {
      root.state = "offline"
    } else {
      root.state = "error"
    }
  }

  function checkStatus() {
    if (!root.enabled || root.busy) return
    root._statusOutput = ""
    root._statusError = ""
    root.state = "checking"
    root._statusGeneration = root._generation
    statusProcess.command = ["python3", root.helperPath, "status"]
    statusProcess.running = true
  }

  function connectAccount() {
    if (!root.enabled || root.busy) return
    root._generation++
    root._authOutput = ""
    root._authError = ""
    root.authorizing = true
    root._authGeneration = root._generation
    root.state = "authorizing"
    root.statusText = "Complete sign-in in your browser"
    authProcess.command = ["python3", root.helperPath, "auth"]
    authProcess.running = true
  }

  function disconnectAccount() {
    if (disconnectProcess.running) return
    root._generation++
    if (statusProcess.running) statusProcess.running = false
    if (eventsProcess.running) eventsProcess.running = false
    if (authProcess.running) authProcess.running = false
    root._fetchPending = false
    root._forcePending = false
    root.refreshing = false
    root.authenticated = false
    root.authorizing = false
    root.clearEventData()
    root.state = "disconnecting"
    root._disconnectOutput = ""
    root._disconnectError = ""
    root._disconnectGeneration = root._generation
    disconnectProcess.command = ["python3", root.helperPath, "disconnect"]
    disconnectProcess.running = true
  }

  function storeCachedRange(key, values, fetchedAt) {
    var nextCache = ({})
    for (var existing in root._cache) nextCache[existing] = root._cache[existing]
    nextCache[key] = { events: values, fetchedAt: fetchedAt }

    var nextOrder = []
    for (var i = 0; i < root._cacheOrder.length; i++)
      if (root._cacheOrder[i] !== key) nextOrder.push(root._cacheOrder[i])
    nextOrder.push(key)

    function eventTotal() {
      var total = 0
      for (var cacheKey in nextCache)
        total += (nextCache[cacheKey].events || []).length
      return total
    }

    while (nextOrder.length > 4 || eventTotal() > 10000) {
      var evicted = nextOrder.shift()
      delete nextCache[evicted]
    }
    root._cache = nextCache
    root._cacheOrder = nextOrder
  }

  function retryStatusAfterStaleExit() {
    if (!root.enabled) return
    Qt.callLater(function() { root.checkStatus() })
  }

  function applyCachedRange(key) {
    var cached = root._cache[key]
    if (!cached) return false
    root.events = cached.events || []
    root.lastUpdated = new Date(Number(cached.fetchedAt || 0))
    return true
  }

  function cacheFresh(key) {
    var cached = root._cache[key]
    return cached && Date.now() - Number(cached.fetchedAt || 0) < 15 * 60 * 1000
  }

  function scheduleRangeRefresh() {
    if (!root.enabled || !root.panelOpen || !root.validRange()) return
    var key = root.rangeKey()
    if (!root.applyCachedRange(key)) {
      root.events = []
      root.lastUpdated = new Date(0)
      if (root.authenticated) root.state = "loading"
    }
    rangeDebounce.restart()
  }

  function refresh(force) {
    if (!root.enabled || !root.panelOpen || !root.authenticated || !root.validRange()) return

    var key = root.rangeKey()
    if (!force && root.cacheFresh(key)) {
      root.applyCachedRange(key)
      root.state = "ready"
      return
    }

    if (eventsProcess.running) {
      root._fetchPending = true
      root._forcePending = root._forcePending || force
      return
    }

    root._eventsOutput = ""
    root._eventsError = ""
    root._activeRequestId = root.requestId()
    root._activeRangeKey = key
    root._eventsGeneration = root._generation
    root.refreshing = true
    if (root.events.length === 0) root.state = "loading"
    var paddedStart = new Date(root.rangeStart.getTime() - 2 * 24 * 60 * 60 * 1000)
    var paddedEnd = new Date(root.rangeEnd.getTime() + 2 * 24 * 60 * 60 * 1000)
    eventsProcess.command = [
      "python3",
      root.helperPath,
      "events",
      "--time-min", paddedStart.toISOString(),
      "--time-max", paddedEnd.toISOString(),
      "--request-id", root._activeRequestId
    ]
    eventsProcess.running = true
  }

  function runPendingFetch() {
    if (!root._fetchPending) return
    var force = root._forcePending
    root._fetchPending = false
    root._forcePending = false
    Qt.callLater(function() { root.refresh(force) })
  }

  onEnabledChanged: {
    if (!enabled) {
      root._generation++
      rangeDebounce.stop()
      refreshTimer.stop()
      if (statusProcess.running) statusProcess.running = false
      if (eventsProcess.running) eventsProcess.running = false
      if (authProcess.running) authProcess.running = false
      root._fetchPending = false
      root._forcePending = false
      root.refreshing = false
      root.authenticated = false
      root.authorizing = false
      root.clearEventData()
      root.state = "disabled"
      root.statusText = ""
      return
    }
    root.checkStatus()
  }

  onPanelOpenChanged: {
    if (!panelOpen || !enabled) return
    if (authenticated) root.scheduleRangeRefresh()
    else root.checkStatus()
  }
  onRangeStartChanged: root.scheduleRangeRefresh()
  onRangeEndChanged: root.scheduleRangeRefresh()

  Component.onCompleted: if (root.enabled) root.checkStatus()

  Timer {
    id: rangeDebounce
    interval: 400
    repeat: false
    onTriggered: root.refresh(false)
  }

  Timer {
    id: refreshTimer
    interval: 15 * 60 * 1000
    repeat: true
    running: root.enabled && root.panelOpen && root.authenticated
    onTriggered: root.refresh(true)
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      if (root._statusGeneration !== root._generation) {
        root.retryStatusAfterStaleExit()
        return
      }
      var payload = root.parsePayload(statusStdout.text || root._statusOutput)
      if (exitCode !== 0 || !payload || payload.ok === false) {
        root.applyFailure(payload, String(statusStderr.text || root._statusError || "Could not check Google Calendar"))
        return
      }

      if (payload.configured === false) {
        root.authenticated = false
        root.clearEventData()
        root.state = "missing_client"
        root.statusText = "OAuth client file missing or invalid"
      } else if (payload.secretToolAvailable === false) {
        root.authenticated = false
        root.clearEventData()
        root.state = "keyring_unavailable"
        root.statusText = "Keyring unavailable"
      } else {
        root.authenticated = payload.connected === true
        if (!root.authenticated) root.clearEventData()
        root.state = root.authenticated ? "ready" : "disconnected"
        root.statusText = String(payload.message || "")
      }
      root.connectionChanged()
      if (root.authenticated && root.panelOpen) root.scheduleRangeRefresh()
    }
  }

  Process {
    id: authProcess
    command: []
    stdout: StdioCollector { id: authStdout; waitForEnd: true; onStreamFinished: root._authOutput = text }
    stderr: StdioCollector { id: authStderr; waitForEnd: true; onStreamFinished: root._authError = text }
    onExited: function(exitCode) {
      if (root._authGeneration !== root._generation) {
        root.authorizing = false
        root.retryStatusAfterStaleExit()
        return
      }
      root.authorizing = false
      var payload = root.parsePayload(authStdout.text || root._authOutput)
      if (exitCode !== 0 || !payload || payload.ok === false) {
        root.applyFailure(payload, String(authStderr.text || root._authError || "Google sign-in failed"))
        return
      }
      root.authenticated = true
      root.state = "ready"
      root.statusText = "Connected"
      root.connectionChanged()
      if (root.panelOpen) root.scheduleRangeRefresh()
    }
  }

  Process {
    id: eventsProcess
    command: []
    stdout: StdioCollector { id: eventsStdout; waitForEnd: true; onStreamFinished: root._eventsOutput = text }
    stderr: StdioCollector { id: eventsStderr; waitForEnd: true; onStreamFinished: root._eventsError = text }
    onExited: function(exitCode) {
      if (root._eventsGeneration !== root._generation) {
        root.refreshing = false
        root.retryStatusAfterStaleExit()
        return
      }
      root.refreshing = false
      var payload = root.parsePayload(eventsStdout.text || root._eventsOutput)
      var responseId = payload ? String(payload.requestId || payload.request_id || "") : ""
      if (exitCode !== 0 || !payload || payload.ok === false) {
        root.applyFailure(payload, String(eventsStderr.text || root._eventsError || "Could not refresh Google Calendar"))
        root.runPendingFetch()
        return
      }

      if (responseId !== "" && responseId !== root._activeRequestId) {
        root.runPendingFetch()
        return
      }

      var fetchedAt = Date.now()
      root.storeCachedRange(root._activeRangeKey, payload.events || [], fetchedAt)
      if (root._activeRangeKey === root.rangeKey()) {
        root.events = payload.events || []
        root.lastUpdated = new Date(fetchedAt)
        root.state = "ready"
        root.statusText = ""
      }
      root.runPendingFetch()
    }
  }

  Process {
    id: disconnectProcess
    command: []
    stdout: StdioCollector { id: disconnectStdout; waitForEnd: true; onStreamFinished: root._disconnectOutput = text }
    stderr: StdioCollector { id: disconnectStderr; waitForEnd: true; onStreamFinished: root._disconnectError = text }
    onExited: function(exitCode) {
      if (root._disconnectGeneration !== root._generation) {
        root.retryStatusAfterStaleExit()
        return
      }
      var payload = root.parsePayload(disconnectStdout.text || root._disconnectOutput)
      if (exitCode !== 0 || !payload || payload.ok === false) {
        root.applyFailure(payload, String(disconnectStderr.text || root._disconnectError || "Could not disconnect Google Calendar"))
        return
      }
      root.authenticated = false
      root.clearEventData()
      root.state = "disconnected"
      root.statusText = String(payload.warning || "Disconnected")
      root.connectionChanged()
    }
  }
}
