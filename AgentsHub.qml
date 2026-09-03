import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Dashboard view over the already-running omarchy.agents bar widget. Sharing
// that instance avoids a second usage scan and keeps both views in sync.
Item {
  id: root

  property var bar: null
  property var agentsWidget: null
  property bool panelOpen: false
  property double nowMs: Date.now()
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal closeRequested()

  readonly property var providers: agentsWidget ? agentsWidget.providers : []
  readonly property var orderedProviders: orderedProviderList(providers)
  readonly property var provider: agentsWidget ? agentsWidget.provider : null
  readonly property var limits: agentsWidget ? agentsWidget.limits : []
  readonly property var models: agentsWidget && "models" in agentsWidget
    ? agentsWidget.models
    : modelRows()
  readonly property var balance: provider ? (provider.balance || null) : null
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property bool alarming: agentsWidget ? agentsWidget.alarming : false

  implicitWidth: Style.space(380)
  implicitHeight: Style.space(560)

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function alpha(color, opacity) {
    return Qt.rgba(color.r, color.g, color.b, opacity)
  }

  function formatTokenCount(value) {
    if (value === undefined || value === null) return "0"
    if (value >= 1e9) return (value / 1e9).toFixed(1) + "B"
    if (value >= 1e6) return (value / 1e6).toFixed(1) + "M"
    if (value >= 1e3) return (value / 1e3).toFixed(1) + "K"
    return String(value)
  }

  function providerMeta() {
    if (!provider) return ""
    if (String(provider.usageStatusText || "") !== "") return provider.usageStatusText
    return String(provider.tierLabel || "Subscription")
  }

  function resetText(limit) {
    if (!limit) return ""
    var resetAt = String(limit.resetAt || limit.resetsAt || "")
    if (resetAt === "") return ""
    var delta = new Date(resetAt).getTime() - root.nowMs
    if (!(delta > 0)) return "Resets now"
    var minutes = Math.floor(delta / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return "Resets in " + days + "d " + (hours % 24) + "h"
    if (hours > 0) return "Resets in " + hours + "h " + (minutes % 60) + "m"
    return "Resets in " + Math.max(1, minutes) + "m"
  }

  function limitTitle(limit) {
    if (!limit) return "Limit"
    if (limit.title) return String(limit.title)
    var label = String(limit.label || "Limit")
    var lower = label.toLowerCase()
    if (lower.indexOf("week") >= 0 || lower.indexOf("7-day") >= 0) return "Weekly"
    if (lower.indexOf("session") >= 0 || lower.match(/\d+\s*-?\s*h/)) return "Session"
    return label.replace(/\s*\(.*\)\s*/, "")
  }

  function currency(value, code) {
    var prefixes = { USD: "$", EUR: "€", GBP: "£" }
    var key = String(code || "USD").toUpperCase()
    return (prefixes[key] || key + " ") + (Number(value) || 0).toFixed(2)
  }

  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  function iconCandidatesForProvider(item) {
    if (!item) return []
    var candidates = []
    var id = String(item.providerId || "")
    if (colorLuminance(Color.popups.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/agents/" + id + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/agents/" + id + ".svg"))
    return candidates
  }

  function recentPeak() {
    var days = provider ? (provider.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function todayDate() {
    var now = new Date()
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    return today ? "Today" : dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function modelWordCase(word) {
    if (word === "gpt") return "GPT"
    if (word === "deepseek") return "DeepSeek"
    return word.charAt(0).toUpperCase() + word.slice(1)
  }

  function friendlyModelName(id) {
    if (!id) return "Unknown"
    var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "")
    var parts = name.split("-")
    var words = []
    var version = []
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i]
      if (part === "") continue
      if (/^\d/.test(part)) {
        version.push(part)
        continue
      }
      if (version.length > 0) {
        words.push(version.join("."))
        version = []
      }
      words.push(modelWordCase(part))
    }
    if (version.length > 0) words.push(version.join("."))
    return words.length > 0 ? words.join(" ") : "Unknown"
  }

  function modelRows() {
    var source = provider ? (provider.modelUsage || {}) : {}
    var rows = []
    for (var id in source) {
      var item = source[id] || {}
      var input = Number(item.inputTokens || 0)
      var output = Number(item.outputTokens || 0)
      var cacheRead = Number(item.cacheReadInputTokens || 0)
      var cacheWrite = Number(item.cacheCreationInputTokens || 0)
      rows.push({
        name: friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + formatTokenCount(row.input)
      + " · out " + formatTokenCount(row.output)
      + " · cache read " + formatTokenCount(row.cacheRead)
      + " · cache write " + formatTokenCount(row.cacheWrite)
  }

  function orderedProviderList(source) {
    var ordered = []
    var priorities = ["codex", "claude"]

    for (var p = 0; p < priorities.length; p++) {
      for (var i = 0; i < source.length; i++) {
        if (String(source[i].providerId || "").toLowerCase() === priorities[p])
          ordered.push(source[i])
      }
    }

    for (var j = 0; j < source.length; j++) {
      var id = String(source[j].providerId || "").toLowerCase()
      if (priorities.indexOf(id) < 0) ordered.push(source[j])
    }

    return ordered
  }

  function selectProvider(item) {
    if (!agentsWidget || !item) return
    var targetId = String(item.providerId || "")
    for (var i = 0; i < providers.length; i++) {
      if (String(providers[i].providerId || "") === targetId) {
        agentsWidget.selectProvider(i)
        return
      }
    }
  }

  function selectProviderAt(index) {
    if (index < 0 || index >= orderedProviders.length) return
    selectProvider(orderedProviders[index])
  }

  function selectMainProvider() {
    if (!agentsWidget || providers.length === 0) return
    if (String(agentsWidget.selectedProviderId || "") !== "") return

    for (var i = 0; i < providers.length; i++) {
      if (String(providers[i].providerId || "").toLowerCase() === "codex") {
        agentsWidget.selectProvider(i)
        return
      }
    }
  }

  function refresh() {
    if (agentsWidget) agentsWidget.refreshNow()
  }

  function launchAgent() {
    if (bar) bar.run("omarchy-agent --pick")
    root.closeRequested()
  }

  onAgentsWidgetChanged: selectMainProvider()
  onProvidersChanged: selectMainProvider()
  onPanelOpenChanged: if (panelOpen) {
    root.nowMs = Date.now()
    Qt.callLater(function() {
      agentScroll.contentY = agentScroll.originY
    })
  }

  Timer {
    interval: 30000
    running: root.panelOpen
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Flickable {
    id: agentScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: Math.max(height, agentColumn.implicitHeight)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height

    Column {
      id: agentColumn
      width: agentScroll.width
      spacing: Style.space(12)

      Item {
        width: parent.width
        height: Math.max(agentTitle.implicitHeight, refreshButton.implicitHeight)

        Text {
          id: agentTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󱚣  AGENTS"
          color: root.alarming ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          font.letterSpacing: 1
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          PanelActionButton {
            id: refreshButton
            iconText: "󰑓"
            tooltipText: "Refresh usage"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.refresh()
          }

          PanelActionButton {
            iconText: "󰆍"
            tooltipText: "Launch agent"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.launchAgent()
          }
        }
      }

      Row {
        id: providerSwitch
        visible: root.providers.length > 1
        width: parent.width
        spacing: Style.space(6)

        readonly property real cellWidth: root.orderedProviders.length > 0
          ? (width - spacing * (root.orderedProviders.length - 1)) / root.orderedProviders.length
          : 0

        Repeater {
          model: root.orderedProviders

          Button {
            required property var modelData
            required property int index
            width: providerSwitch.cellWidth
            iconText: index < 2 ? String(index + 1) : ""
            text: modelData.providerName
            selected: root.provider !== null
              && String(modelData.providerId || "") === String(root.provider.providerId || "")
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.caption
            horizontalPadding: Style.space(5)
            onClicked: root.selectProvider(modelData)
          }
        }
      }

      BorderSurface {
        visible: root.provider !== null
        width: parent.width
        height: providerHero.implicitHeight + Style.space(22)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Row {
          id: providerHero
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(10)

          Item {
            id: providerMark
            anchors.verticalCenter: parent.verticalCenter
            width: Style.font.display
            height: Style.font.display

            property var candidates: root.iconCandidatesForProvider(root.provider)
            property string candidatesKey: candidates.join("\n")
            property int candidateIndex: 0
            onCandidatesKeyChanged: candidateIndex = 0

            Image {
              id: providerMarkImage
              anchors.fill: parent
              source: providerMark.candidateIndex < providerMark.candidates.length
                ? providerMark.candidates[providerMark.candidateIndex]
                : ""
              sourceSize.width: Style.font.display * 2
              sourceSize.height: Style.font.display * 2
              fillMode: Image.PreserveAspectFit
              onStatusChanged: if (status === Image.Error && providerMark.candidateIndex < providerMark.candidates.length)
                Qt.callLater(function() { providerMark.candidateIndex++ })
            }

            Text {
              anchors.centerIn: parent
              visible: providerMarkImage.status !== Image.Ready
              text: "󱚣"
              color: root.alarming ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }

          Column {
            width: parent.width - Style.space(50)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.provider ? root.provider.providerName : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: root.providerMeta()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        visible: root.providers.length === 0
        width: parent.width
        topPadding: Style.space(28)
        text: "No agent usage found"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      Column {
        visible: root.limits.length > 0
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: root.limits

          Column {
            required property var modelData
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width

              Text {
                width: parent.width / 2
                text: root.limitTitle(modelData)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                width: parent.width / 2
                text: Math.round(Number(modelData.percent || 0) * 100) + "%"
                color: Number(modelData.percent || 0) >= 0.9 ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignRight
              }
            }

            ThemeProgressBar {
              width: parent.width
              height: Style.space(7)
              value: root.clamp(Number(modelData.percent || 0), 0, 1)
              foreground: root.foreground
              urgentColor: root.urgent
              urgent: Number(modelData.percent || 0) >= 0.9
              animationDuration: 220
            }

            Text {
              width: parent.width
              text: root.resetText(modelData)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }

      BorderSurface {
        visible: root.balance !== null
        width: parent.width
        height: balanceColumn.implicitHeight + Style.space(20)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Column {
          id: balanceColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(4)

          Text {
            text: root.balance ? root.currency(root.balance.remaining, root.balance.currency) + " remaining" : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            text: root.balance && root.balance.funded > 0
              ? root.currency(root.balance.spent, root.balance.currency) + " spent"
              : "Prepaid balance"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      PanelSeparator {
        visible: root.provider !== null
        foreground: root.foreground
      }

      Column {
        visible: root.provider !== null
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "TODAY"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }

        Row {
          width: parent.width

          Column {
            width: parent.width / 3
            Text {
              width: parent.width
              text: root.provider ? root.formatTokenCount(root.provider.todayTotalTokens) : "0"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }
            Text {
              width: parent.width
              text: "TOKENS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            width: parent.width / 3
            Text {
              width: parent.width
              text: root.provider ? Number(root.provider.todayPrompts || 0) : 0
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }
            Text {
              width: parent.width
              text: "PROMPTS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Column {
            width: parent.width / 3
            Text {
              width: parent.width
              text: root.provider ? Number(root.provider.todaySessions || 0) : 0
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              horizontalAlignment: Text.AlignHCenter
            }
            Text {
              width: parent.width
              text: "SESSIONS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }

      Column {
        id: usageSection
        visible: root.provider !== null && root.provider.recentDays && root.provider.recentDays.length > 0
        width: parent.width
        spacing: Style.spacing.md

        readonly property var days: root.provider ? (root.provider.recentDays || []) : []
        readonly property real peak: Math.max(1, root.recentPeak())

        PanelSectionHeader {
          width: parent.width
          text: "TOKENS BY DAY"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: usageSection.days

          DayRow {
            required property var modelData
            required property int index
            width: usageSection.width
            day: modelData
            ratio: Number(modelData.messageCount || 0) / usageSection.peak
            today: String(modelData.date || "") === root.todayDate()
          }
        }
      }

      PanelSeparator {
        visible: modelSection.visible
        foreground: root.foreground
      }

      Column {
        id: modelSection
        visible: root.models.length > 0
        width: parent.width
        spacing: Style.spacing.md

        PanelSectionHeader {
          width: parent.width
          text: "TOKENS BY MODEL"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Repeater {
          model: root.models

          ModelRow {
            required property var modelData
            width: modelSection.width
            row: modelData
            share: modelData.total / Math.max(1, root.models[0].total)
          }
        }
      }
    }
  }

  // Kept structurally identical to omarchy.agents so daily usage reads the
  // same here and in the stock panel.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      text: modelRow.row ? root.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }

  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    ThemeProgressBar {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      value: root.clamp(dayRow.ratio, 0, 1)
      foreground: root.foreground
      trackColor: root.alpha(root.foreground, 0.05)
      animationDuration: 160
    }

    Text {
      id: dayValue
      text: root.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }
}
