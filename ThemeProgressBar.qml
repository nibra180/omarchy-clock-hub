import QtQuick
import qs.Commons

// Theme-aware progress track. Gradient themes reuse the active Hyprland border
// colors; flat themes fall back to their accent. Urgent state stays semantic.
Rectangle {
  id: root

  property real value: 0
  property color foreground: Color.foreground
  property color urgentColor: Color.urgent
  property color trackColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  property bool urgent: false
  property int animationDuration: 180

  readonly property var activeSpec: Border.hyprlandActiveSpec(Color.accent, 0)
  readonly property var themeColors: activeSpec.gradient && activeSpec.gradient.enabled
    ? activeSpec.gradient.colors : [activeSpec.color || Color.accent]
  readonly property var fillColors: urgent ? [urgentColor] : themeColors

  function clampedValue() {
    return Math.max(0, Math.min(1, Number(value) || 0))
  }

  function stopColor(index) {
    if (!fillColors || fillColors.length === 0) return Color.accent
    return index < fillColors.length ? fillColors[index] : fillColors[fillColors.length - 1]
  }

  function stopPosition(index) {
    var count = fillColors ? fillColors.length : 0
    if (count <= 1) return index === 0 ? 0 : 1
    return index < count ? index / (count - 1) : 1
  }

  implicitWidth: Style.space(120)
  implicitHeight: Style.space(6)
  radius: Style.cornerRadius > 0 ? height / 2 : 0
  color: trackColor
  clip: true

  Rectangle {
    id: fill
    width: Math.round(root.width * root.clampedValue())
    height: parent.height
    radius: parent.radius

    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: root.stopPosition(0); color: root.stopColor(0) }
      GradientStop { position: root.stopPosition(1); color: root.stopColor(1) }
      GradientStop { position: root.stopPosition(2); color: root.stopColor(2) }
      GradientStop { position: root.stopPosition(3); color: root.stopColor(3) }
      GradientStop { position: root.stopPosition(4); color: root.stopColor(4) }
      GradientStop { position: root.stopPosition(5); color: root.stopColor(5) }
      GradientStop { position: root.stopPosition(6); color: root.stopColor(6) }
      GradientStop { position: root.stopPosition(7); color: root.stopColor(7) }
      GradientStop { position: root.stopPosition(8); color: root.stopColor(8) }
      GradientStop { position: root.stopPosition(9); color: root.stopColor(9) }
    }

    Behavior on width {
      NumberAnimation { duration: root.animationDuration; easing.type: Easing.OutCubic }
    }
  }
}
