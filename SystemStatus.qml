import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Adapted from Asked Dashboard's system metrics (MIT, cucu0628).
// Sampling stops with the panel, so the closed hub has no polling cost.
Item {
  id: root

  property var bar: null
  property bool running: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real cpuUsage: 0
  property real memoryUsage: 0
  property real diskUsage: 0

  signal closeRequested()

  implicitHeight: Style.space(108)

  function clamp(value) {
    return Math.max(0, Math.min(100, Number(value) || 0))
  }

  function refresh() {
    if (!systemProcess.running) systemProcess.running = true
  }

  function openBtop() {
    if (!bar) return
    bar.run("omarchy launch or focus tui btop")
    root.closeRequested()
  }

  Timer {
    interval: 3000
    running: root.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: systemProcess
    command: [
      "bash",
      "-lc",
      "read _ u n s i w irq sirq st _ < /proc/stat; "
        + "t1=$((u+n+s+i+w+irq+sirq+st)); z1=$((i+w)); sleep 0.25; "
        + "read _ u n s i w irq sirq st _ < /proc/stat; "
        + "t2=$((u+n+s+i+w+irq+sirq+st)); z2=$((i+w)); d=$((t2-t1)); "
        + "if ((d>0)); then cpu=$((100*(d-(z2-z1))/d)); else cpu=0; fi; "
        + "mem=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0)printf \"%.0f\",100*(t-a)/t;else print 0}' /proc/meminfo); "
        + "disk=$(df -P / | awk 'NR==2{gsub(/%/,\"\",$5);print $5}'); "
        + "printf '%s %s %s\\n' \"$cpu\" \"$mem\" \"$disk\""
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var values = String(text || "").trim().split(/\s+/)
        if (values.length < 3) return
        root.cpuUsage = root.clamp(values[0])
        root.memoryUsage = root.clamp(values[1])
        root.diskUsage = root.clamp(values[2])
      }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Style.spacing.hairline
    color: root.foreground
    opacity: 0.12
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(8)

    Item {
      width: parent.width
      height: Math.max(statusTitle.implicitHeight, btopButton.implicitHeight)

      Text {
        id: statusTitle
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "SYSTEM STATUS"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
      }

      PanelActionButton {
        id: btopButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰍛"
        tooltipText: "Open btop"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openBtop()
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(24)

      SystemMetric {
        width: (parent.width - parent.spacing * 2) / 3
        label: "CPU"
        icon: "󰍛"
        value: root.cpuUsage
      }

      SystemMetric {
        width: (parent.width - parent.spacing * 2) / 3
        label: "MEMORY"
        icon: "󰘚"
        value: root.memoryUsage
      }

      SystemMetric {
        width: (parent.width - parent.spacing * 2) / 3
        label: "DISK"
        icon: "󰋊"
        value: root.diskUsage
      }
    }
  }

  component SystemMetric: Item {
    id: metric
    property string label: ""
    property string icon: ""
    property real value: 0

    height: Style.space(48)

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(7)

      OpticalGlyph {
        width: Style.space(18)
        height: Style.space(18)
        anchors.verticalCenter: parent.verticalCenter
        text: icon
        color: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.title
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: label
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.letterSpacing: 1
        font.bold: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(90)
        horizontalAlignment: Text.AlignRight
        text: Math.round(value) + "%"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }

    ThemeProgressBar {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(7)
      value: root.clamp(metric.value) / 100
      foreground: root.foreground
      animationDuration: 250
    }
  }
}
