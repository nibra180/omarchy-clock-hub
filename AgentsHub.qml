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
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal closeRequested()

  readonly property var providers: agentsWidget ? agentsWidget.providers : []
  readonly property var provider: agentsWidget ? agentsWidget.provider : null
  readonly property int providerIndex: agentsWidget ? agentsWidget.providerIndex : 0
  readonly property var limits: agentsWidget ? agentsWidget.limits : []
  readonly property var balance: provider ? (provider.balance || null) : null
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
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
    if (!limit || !limit.resetsAt) return ""
    var delta = new Date(limit.resetsAt).getTime() - Date.now()
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

  function modelRows() {
    var source = provider ? (provider.modelUsage || {}) : {}
    var rows = []
    for (var id in source) {
      var item = source[id] || {}
      rows.push({
        name: id,
        total: Number(item.inputTokens || 0) + Number(item.outputTokens || 0)
          + Number(item.cacheReadInputTokens || 0) + Number(item.cacheCreationInputTokens || 0)
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function selectProvider(index) {
    if (agentsWidget) agentsWidget.selectProvider(index)
  }

  function refresh() {
    if (agentsWidget) agentsWidget.refreshNow()
  }

  function launchAgent() {
    if (bar) bar.run("omarchy-agent --pick")
    root.closeRequested()
  }

  onPanelOpenChanged: if (panelOpen) agentScroll.contentY = 0

  Flickable {
    id: agentScroll
    anchors.fill: parent
    contentWidth: width
    contentHeight: agentColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar {
      id: agentScrollBar
      policy: ScrollBar.AsNeeded
      background: Item { }
      contentItem: Rectangle {
        implicitWidth: Style.space(3)
        radius: width / 2
        color: root.foreground
        opacity: agentScrollBar.pressed ? 0.55 : (agentScrollBar.hovered ? 0.35 : 0.16)

        Behavior on opacity { NumberAnimation { duration: 120 } }
      }
    }

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

        readonly property real cellWidth: root.providers.length > 0
          ? (width - spacing * (root.providers.length - 1)) / root.providers.length
          : 0

        Repeater {
          model: root.providers

          Button {
            required property var modelData
            required property int index
            width: providerSwitch.cellWidth
            text: modelData.providerName
            selected: index === root.providerIndex
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            horizontalPadding: Style.space(5)
            onClicked: root.selectProvider(index)
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

            Rectangle {
              width: parent.width
              height: Style.space(7)
              radius: Style.cornerRadius > 0 ? height / 2 : 0
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Rectangle {
                width: parent.width * root.clamp(Number(modelData.percent || 0), 0, 1)
                height: parent.height
                radius: parent.radius
                color: Number(modelData.percent || 0) >= 0.9
                  ? root.urgent
                  : Style.selectedStateColor(root.foreground, Color.accent)
                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
              }
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

      Column {
        readonly property var rows: root.modelRows()
        visible: rows.length > 0
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: "TOP MODELS"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }

        Repeater {
          model: parent.rows

          Row {
            required property var modelData
            width: parent.width

            Text {
              width: parent.width * 0.7
              text: modelData.name
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            Text {
              width: parent.width * 0.3
              text: root.formatTokenCount(modelData.total)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }
    }
  }

  // Kept structurally identical to omarchy.agents so daily usage reads the
  // same here and in the stock panel.
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

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
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
