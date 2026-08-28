import QtQuick
import qs.Commons
import qs.Ui

// Compact, in-panel mirror of the manifest-backed widget settings.
// The caller owns persistence; this surface only presents the current state.
BorderSurface {
  id: root

  property bool mediaEnabled: true
  property bool agentsEnabled: true
  property bool systemStatusEnabled: true
  property bool calendarEnabled: false
  property bool calendarConnected: false
  property bool calendarCanConnect: false
  property string calendarState: "disabled"
  property string calendarStatus: ""
  property string indicatorStyle: "Equalizer"
  property int cursor: -1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal mediaToggled()
  signal agentsToggled()
  signal systemStatusToggled()
  signal calendarToggled()
  signal calendarConnectRequested()
  signal calendarDisconnectRequested()
  signal indicatorStyleSelected(string style)

  readonly property int indicatorRow: calendarEnabled ? 5 : 4
  readonly property int rowCount: calendarEnabled ? 6 : 5

  implicitWidth: Style.space(250)
  implicitHeight: menuColumn.implicitHeight + Style.space(28)
  radius: Style.cornerRadius
  color: Color.popups.background
  borderSpec: Border.controlSpec("normal", foreground, Color.accent)

  function moveCursor(delta) {
    var current = cursor < 0 ? 0 : cursor
    cursor = (current + delta + rowCount) % rowCount
  }

  function activateCursor() {
    if (cursor === 0) root.mediaToggled()
    else if (cursor === 1) root.agentsToggled()
    else if (cursor === 2) root.systemStatusToggled()
    else if (cursor === 3) root.calendarToggled()
    else if (root.calendarEnabled && cursor === 4) {
      if (root.calendarConnected) root.calendarDisconnectRequested()
      else root.calendarConnectRequested()
    } else if (cursor === root.indicatorRow) root.moveIndicator(1)
  }

  function moveIndicator(delta) {
    var current = indicatorGroup.selectedOptionIndex()
    var next = ((current < 0 ? 0 : current) + delta + indicatorGroup.options.length) % indicatorGroup.options.length
    root.indicatorStyleSelected(indicatorGroup.optionValue(indicatorGroup.options[next]))
  }

  onVisibleChanged: if (!visible) cursor = -1

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
  }

  Column {
    id: menuColumn
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(5)

    Text {
      width: parent.width
      bottomPadding: Style.space(3)
      text: "HUB SECTIONS"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      font.bold: true
    }

    Toggle {
      width: parent.width
      activeFocusOnTab: false
      label: "Media"
      checked: root.mediaEnabled
      foreground: root.foreground
      fontFamily: root.fontFamily
      titleSize: Style.font.body
      hasCursor: root.cursor === 0
      onHovered: function(isHovered) { if (isHovered) root.cursor = 0 }
      onClicked: root.mediaToggled()
    }

    Toggle {
      width: parent.width
      activeFocusOnTab: false
      label: "Agents"
      checked: root.agentsEnabled
      foreground: root.foreground
      fontFamily: root.fontFamily
      titleSize: Style.font.body
      hasCursor: root.cursor === 1
      onHovered: function(isHovered) { if (isHovered) root.cursor = 1 }
      onClicked: root.agentsToggled()
    }

    Toggle {
      width: parent.width
      activeFocusOnTab: false
      label: "System status"
      checked: root.systemStatusEnabled
      foreground: root.foreground
      fontFamily: root.fontFamily
      titleSize: Style.font.body
      hasCursor: root.cursor === 2
      onHovered: function(isHovered) { if (isHovered) root.cursor = 2 }
      onClicked: root.systemStatusToggled()
    }

    Toggle {
      width: parent.width
      activeFocusOnTab: false
      label: "Google Calendar"
      checked: root.calendarEnabled
      foreground: root.foreground
      fontFamily: root.fontFamily
      titleSize: Style.font.body
      hasCursor: root.cursor === 3
      onHovered: function(isHovered) { if (isHovered) root.cursor = 3 }
      onClicked: root.calendarToggled()
    }

    Button {
      visible: root.calendarEnabled
      width: parent.width
      text: root.calendarConnected ? "Disconnect Google Calendar"
        : (root.calendarState === "reauth_required" ? "Reconnect Google Calendar"
          : (root.calendarState === "authorizing" ? "Connecting…"
            : (root.calendarState === "disconnecting" ? "Disconnecting…"
              : "Connect Google Calendar")))
      tooltipText: root.calendarStatus
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      leftAlign: true
      bordered: true
      enabled: root.calendarConnected || root.calendarCanConnect
      hasCursor: root.cursor === 4
      onHovered: function(isHovered) { if (isHovered) root.cursor = 4 }
      onClicked: {
        if (root.calendarConnected) root.calendarDisconnectRequested()
        else root.calendarConnectRequested()
      }
    }

    Text {
      width: parent.width
      topPadding: Style.space(7)
      text: "NOW-PLAYING INDICATOR"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      font.bold: true
    }

    ButtonGroup {
      id: indicatorGroup
      options: ["Vinyl", "Equalizer", "Pulse"]
      value: root.indicatorStyle
      foreground: root.foreground
      background: Color.popups.background
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      focusable: false
      cursorIndex: root.cursor === root.indicatorRow ? selectedOptionIndex() : -1
      onHovered: function(index, isHovered) { if (isHovered) root.cursor = root.indicatorRow }
      onChanged: function(value) { root.indicatorStyleSelected(value) }
    }
  }
}
