import QtQuick
import qs.Commons
import qs.Ui

// Compact, in-panel mirror of the manifest-backed section settings.
// The caller owns persistence; this surface only presents the current state.
BorderSurface {
  id: root

  property bool mediaEnabled: true
  property bool agentsEnabled: true
  property bool systemStatusEnabled: true
  property int cursor: -1
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal mediaToggled()
  signal agentsToggled()
  signal systemStatusToggled()

  readonly property int rowCount: 3

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
  }
}
