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
  readonly property bool alarming: agentsWidget ? agentsWidget.alarming : false

  implicitWidth: Style.space(330)
  implicitHeight: Style.space(560)

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  function formatTokenCount(value) {
    var amount = Math.max(0, Number(value) || 0)
    if (amount >= 1000000000) return (amount / 1000000000).toFixed(amount >= 10000000000 ? 0 : 1) + "B"
    if (amount >= 1000000) return (amount / 1000000).toFixed(amount >= 10000000 ? 0 : 1) + "M"
    if (amount >= 1000) return (amount / 1000).toFixed(amount >= 10000 ? 0 : 1) + "K"
    return String(Math.round(amount))
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

  function dayLabel(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    return isNaN(parsed.getTime()) ? "" : ["S", "M", "T", "W", "T", "F", "S"][parsed.getDay()]
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
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

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
        visible: root.provider !== null && (root.provider.recentDays || []).length > 0
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: "LAST 7 DAYS"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1
        }

        Row {
          id: dayChart
          width: parent.width
          height: Style.space(78)
          spacing: Style.space(5)

          Repeater {
            model: root.provider ? (root.provider.recentDays || []) : []

            Item {
              required property var modelData
              width: (dayChart.width - dayChart.spacing * 6) / 7
              height: dayChart.height

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: dayName.top
                anchors.bottomMargin: Style.space(4)
                height: Math.max(Style.space(3), (parent.height - dayName.height - Style.space(8))
                  * Number(modelData.messageCount || 0) / Math.max(1, root.recentPeak()))
                radius: Style.cornerRadius
                color: Style.selectedStateColor(root.foreground, Color.accent)
                opacity: 0.35 + 0.65 * Number(modelData.messageCount || 0) / Math.max(1, root.recentPeak())
              }

              Text {
                id: dayName
                anchors.bottom: parent.bottom
                width: parent.width
                text: root.dayLabel(modelData.date)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                horizontalAlignment: Text.AlignHCenter
              }
            }
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
}
