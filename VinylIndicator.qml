import QtQuick
import qs.Commons

// Compact now-playing mark with three theme-aware animation styles.
Item {
  id: root

  property bool running: false
  property string variant: "Vinyl"
  property color foreground: Color.foreground
  property color accent: Color.accent
  property real size: Style.space(16)

  width: size
  height: size

  Item {
    id: record
    anchors.fill: parent
    visible: root.variant !== "Equalizer" && root.variant !== "Pulse"

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
        running: root.running && record.visible
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

  Item {
    id: equalizer
    anchors.fill: parent
    visible: root.variant === "Equalizer"

    readonly property real barWidth: Math.max(2, root.size * 0.17)
    readonly property real gap: root.size * 0.12
    readonly property real contentWidth: barWidth * 3 + gap * 2

    Rectangle {
      x: (parent.width - equalizer.contentWidth) / 2
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.size * 0.1
      width: equalizer.barWidth
      height: root.size * 0.68
      radius: width / 2
      color: root.foreground
      transformOrigin: Item.Bottom

      SequentialAnimation on scale {
        running: root.running && equalizer.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.38; to: 1; duration: 360; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.38; duration: 440; easing.type: Easing.InOutSine }
      }
    }

    Rectangle {
      x: (parent.width - equalizer.contentWidth) / 2 + equalizer.barWidth + equalizer.gap
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.size * 0.1
      width: equalizer.barWidth
      height: root.size * 0.8
      radius: width / 2
      color: root.accent
      transformOrigin: Item.Bottom

      SequentialAnimation on scale {
        running: root.running && equalizer.visible
        loops: Animation.Infinite
        NumberAnimation { from: 0.45; to: 1; duration: 470; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.45; duration: 310; easing.type: Easing.InOutSine }
      }
    }

    Rectangle {
      x: (parent.width - equalizer.contentWidth) / 2 + (equalizer.barWidth + equalizer.gap) * 2
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.size * 0.1
      width: equalizer.barWidth
      height: root.size * 0.62
      radius: width / 2
      color: root.foreground
      transformOrigin: Item.Bottom

      SequentialAnimation on scale {
        running: root.running && equalizer.visible
        loops: Animation.Infinite
        NumberAnimation { from: 1; to: 0.34; duration: 390; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.34; to: 1; duration: 520; easing.type: Easing.InOutSine }
      }
    }
  }

  Item {
    id: pulse
    anchors.fill: parent
    visible: root.variant === "Pulse"

    property real progress: 0

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: Math.max(1, Style.spacing.hairline)
      border.color: root.foreground
      scale: 0.42 + pulse.progress * 0.58
      opacity: root.running ? 0.62 * (1 - pulse.progress) : 0.45
    }

    Rectangle {
      anchors.centerIn: parent
      width: parent.width * 0.38
      height: width
      radius: width / 2
      color: root.accent
    }

    NumberAnimation on progress {
      running: root.running && pulse.visible
      from: 0
      to: 1
      duration: 1300
      loops: Animation.Infinite
      easing.type: Easing.OutCubic
    }
  }
}
