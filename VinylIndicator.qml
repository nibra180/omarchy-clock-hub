import QtQuick
import qs.Commons

// Minimal now-playing mark: one ring, a rotating radius and an accent center.
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

    Rectangle {
      id: outerRing
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: Math.max(1, Style.spacing.hairline)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.38)
    }

    Item {
      id: rotatingRadius
      anchors.fill: parent

      RotationAnimator on rotation {
        running: root.running
        from: 0
        to: 360
        duration: 2800
        loops: Animation.Infinite
      }

      Rectangle {
        x: parent.width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width / 2 - outerRing.border.width)
        height: Math.max(2, Style.spacing.hairline * 2)
        radius: height / 2
        color: root.foreground
        opacity: 0.9
      }
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.38
      height: width
      radius: width / 2
      color: root.accent
    }
  }
}
