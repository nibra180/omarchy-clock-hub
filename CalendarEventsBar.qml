import QtQuick
import qs.Commons
import qs.Ui

// Compact presentation for the selected day's calendar events. The caller
// owns fetching and authentication; this component only renders state and
// forwards actions.
BorderSurface {
  id: root

  property date selectedDate: new Date()
  property var events: []
  property int totalEventCount: 0
  property string state: "ready"
  property date lastUpdated: new Date(0)
  property bool refreshing: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal connectRequested()
  signal refreshRequested()
  signal reconnectRequested()

  readonly property string normalizedState: String(state || "ready").toLowerCase().replace(/_/g, "-")
  readonly property var eventList: events && typeof events.length === "number" ? events : []
  readonly property var visibleEvents: eventList.slice(0, 3)
  readonly property int effectiveEventCount: Math.max(eventList.length, Math.max(0, totalEventCount))
  readonly property int overflowCount: Math.max(0, effectiveEventCount - visibleEvents.length)
  readonly property bool connectState: normalizedState === "disconnected"
    || normalizedState === "missing-client" || normalizedState === "missingclient"
  readonly property bool reconnectState: normalizedState === "reauth"
    || normalizedState === "reauth-required"
  readonly property bool keyringState: normalizedState === "keyring"
    || normalizedState === "keyring-unavailable" || normalizedState === "keyring-locked"
  readonly property bool offlineState: normalizedState === "offline"
  readonly property bool checkingState: normalizedState === "checking"
  readonly property bool authorizingState: normalizedState === "authorizing"
  readonly property bool disconnectingState: normalizedState === "disconnecting"
  readonly property bool loadingState: normalizedState === "loading"
    || checkingState || authorizingState || disconnectingState
  readonly property bool showEvents: visibleEvents.length > 0
    && (normalizedState === "ready" || offlineState || loadingState)

  width: parent ? parent.width : implicitWidth
  implicitWidth: Style.space(700)
  implicitHeight: Style.space(48)
  radius: Style.cornerRadius
  color: Style.normalFillFor(root.foreground, Color.accent)
  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
  clip: true

  property date statusNow: new Date()

  function validDate(value) {
    return value instanceof Date && !isNaN(value.getTime())
  }

  function selectedDateLabel() {
    if (!validDate(selectedDate)) return "--- -- ---"
    var locale = Qt.locale("en_US")
    var weekday = locale.dayName(selectedDate.getDay(), Locale.ShortFormat).toUpperCase()
    var month = locale.monthName(selectedDate.getMonth(), Locale.ShortFormat).toUpperCase()
    return weekday + " " + selectedDate.getDate() + " " + month
  }

  function eventTitle(event) {
    if (!event) return "Busy"
    var value = event.summary !== undefined ? event.summary : event.title
    var title = String(value || "").replace(/[\r\n]+/g, " ").trim()
    return title !== "" ? title : "Busy"
  }

  function eventTime(event) {
    if (event && event.allDay === true) return "ALL DAY"
    var start = event && event.start !== undefined ? new Date(event.start) : new Date(NaN)
    return validDate(start) ? Qt.formatTime(start, Locale.ShortFormat) : "--:--"
  }

  function updateAge() {
    if (!validDate(lastUpdated) || lastUpdated.getTime() <= 0) return ""
    var seconds = Math.max(0, Math.floor((statusNow.getTime() - lastUpdated.getTime()) / 1000))
    if (seconds < 60) return "JUST NOW"
    if (seconds < 3600) return Math.floor(seconds / 60) + "M AGO"
    if (seconds < 86400) return Math.floor(seconds / 3600) + "H AGO"
    return Math.floor(seconds / 86400) + "D AGO"
  }

  function stateCaption() {
    if (offlineState) {
      var age = updateAge()
      return age === "" ? "OFFLINE" : "OFFLINE · " + age
    }
    if (authorizingState) return "AUTHORIZING"
    if (disconnectingState) return "DISCONNECTING"
    if (checkingState) return "CHECKING"
    if (loadingState) return "LOADING"
    if (refreshing) return "UPDATING"
    return ""
  }

  function stateMessage() {
    if (connectState) {
      return normalizedState === "disconnected" ? "Calendar disconnected" : "OAuth client file missing"
    }
    if (reconnectState) return "Sign-in expired"
    if (keyringState) return "Keyring unavailable"
    if (offlineState) {
      var age = updateAge()
      return age === "" ? "Offline" : "Offline · updated " + age.toLowerCase()
    }
    if (authorizingState) return "Waiting for sign-in…"
    if (disconnectingState) return "Disconnecting…"
    if (checkingState) return "Checking calendar…"
    if (loadingState) return "Loading events…"
    if (normalizedState === "error") return "Calendar unavailable"
    if (normalizedState === "disabled") return "Calendar disabled"
    return "No events"
  }

  function overflowTooltip() {
    var lines = []
    for (var i = visibleEvents.length; i < eventList.length; i++)
      lines.push(eventTime(eventList[i]) + "  "
        + eventTitle(eventList[i]).replace(/</g, "‹").replace(/>/g, "›"))

    var unavailable = effectiveEventCount - eventList.length
    if (unavailable > 0) lines.push("+" + unavailable + " more")
    return lines.join("\n")
  }

  Timer {
    interval: 60000
    repeat: true
    running: root.offlineState && root.visible
    onTriggered: root.statusNow = new Date()
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.controlPaddingX
    anchors.rightMargin: Style.spacing.sm
    anchors.topMargin: Style.spacing.sm
    anchors.bottomMargin: Style.spacing.sm

    Item {
      id: dateBlock
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.space(104)

      Column {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.spacing.md
        spacing: Style.spacing.xxs

        Text {
          width: parent.width
          text: root.selectedDateLabel()
          textFormat: Text.PlainText
          color: Style.selectedStateColor(root.foreground, Color.accent)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          font.letterSpacing: 0.5
          elide: Text.ElideRight
        }

        Text {
          visible: text !== ""
          width: parent.width
          text: root.showEvents ? root.stateCaption() : ""
          textFormat: Text.PlainText
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

    Rectangle {
      id: dateSeparator
      anchors.left: dateBlock.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Style.spacing.hairline
      color: root.foreground
      opacity: 0.14
    }

    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.xs

      Button {
        visible: root.connectState
        text: "Connect"
        tooltipText: root.normalizedState === "disconnected"
          ? "Connect Google Calendar" : "Set up Google Calendar"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.sm
        bordered: true
        enabled: root.normalizedState === "disconnected" && !root.refreshing
        onClicked: root.connectRequested()
      }

      Button {
        visible: root.reconnectState
        text: "Reconnect"
        tooltipText: "Reconnect Google Calendar"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.spacing.md
        verticalPadding: Style.spacing.sm
        bordered: true
        enabled: !root.refreshing
        onClicked: root.reconnectRequested()
      }

      Button {
        visible: !root.connectState && !root.reconnectState
          && !root.keyringState && !root.disconnectingState
        iconText: "󰑐"
        tooltipText: root.refreshing ? "Refreshing calendar" : "Refresh calendar"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.icon
        horizontalPadding: Style.spacing.sm
        verticalPadding: Style.spacing.sm
        iconSpinning: root.refreshing || root.loadingState
        enabled: !root.refreshing && !root.loadingState
        onClicked: root.refreshRequested()
      }
    }

    Item {
      id: contentArea
      anchors.left: dateSeparator.right
      anchors.leftMargin: Style.spacing.controlGap
      anchors.right: actionRow.left
      anchors.rightMargin: Style.spacing.controlGap
      anchors.top: parent.top
      anchors.bottom: parent.bottom

      Text {
        anchors.fill: parent
        visible: !root.showEvents
        text: root.stateMessage()
        textFormat: Text.PlainText
        color: root.normalizedState === "ready"
          ? Qt.darker(root.foreground, 1.35) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.italic: root.normalizedState === "ready"
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      Row {
        id: eventRow
        anchors.fill: parent
        visible: root.showEvents
        spacing: Style.spacing.md

        readonly property int slotCount: root.visibleEvents.length
        readonly property int gapCount: Math.max(0, slotCount - 1) + (overflow.visible ? 1 : 0)
        readonly property real slotsWidth: Math.max(0,
          width - overflow.width - gapCount * spacing)

        Repeater {
          model: root.visibleEvents

          BorderSurface {
            required property var modelData

            width: eventRow.slotCount > 0 ? eventRow.slotsWidth / eventRow.slotCount : 0
            height: eventRow.height
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            clip: true

            Text {
              id: eventTimeLabel
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: root.eventTime(modelData)
              textFormat: Text.PlainText
              color: Style.selectedStateColor(root.foreground, Color.accent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              anchors.left: eventTimeLabel.right
              anchors.leftMargin: Style.spacing.sm
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: root.eventTitle(modelData)
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        Item {
          id: overflow
          visible: root.overflowCount > 0
          width: visible ? Style.space(34) : 0
          height: eventRow.height

          Text {
            anchors.centerIn: parent
            text: "+" + root.overflowCount
            textFormat: Text.PlainText
            color: overflowMouse.containsMouse
              ? Style.hoverStateColor(root.foreground, Color.accent)
              : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          MouseArea {
            id: overflowMouse
            anchors.fill: parent
            hoverEnabled: true
          }

          PanelToolTip {
            visible: overflowMouse.containsMouse
            text: root.overflowTooltip()
            fontFamily: root.fontFamily
          }
        }
      }
    }
  }
}
