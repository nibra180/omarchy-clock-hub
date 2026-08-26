import QtQuick
import qs.Commons

// Minimal now-playing mark: one groove, one label and a small rotating cue.
Item {
  id: root

  property bool running: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real size: Style.space(16)

  width: size
  height: size

  Item {
    id: record
    anchors.fill: parent

    RotationAnimator on rotation {
      running: root.running
      from: 0
      to: 360
      duration: 2800
      loops: Animation.Infinite
    }

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: Qt.darker(root.foreground, 2.7)
      border.width: Style.spacing.hairline
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.5)
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.64
      height: width
      radius: width / 2
      color: "transparent"
      border.width: Style.spacing.hairline
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.28
      height: width
      radius: width / 2
      color: root.accent
    }

    Rectangle {
      x: record.width * 0.7
      y: record.height * 0.17
      width: Math.max(1, Style.spacing.hairline)
      height: width
      radius: width / 2
      color: root.foreground
      opacity: 0.65
    }
  }
}
