import QtQuick
import qs.Commons
import qs.Ui

// Compact now-playing card for the clock hub. Playback is provided by
// Omarchy's existing MPRIS service, so this component only owns presentation.
Item {
  id: root

  property var bar: null
  property var mediaService: null
  property bool panelOpen: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: hasMedia ? (activePlayer.trackTitle || "Unknown title") : "Nothing playing"
  readonly property string artist: hasMedia ? (activePlayer.trackArtist || "Unknown artist") : "Start playback in a media app"
  readonly property string album: hasMedia && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: hasMedia && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string sourceName: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "Media") : "Media"
  readonly property real trackLength: activePlayer ? Math.max(0, Number(activePlayer.length || 0)) : 0

  property real trackPosition: 0

  implicitWidth: Style.space(270)
  implicitHeight: mediaColumn.implicitHeight

  function syncPosition() {
    trackPosition = activePlayer ? Math.max(0, Number(activePlayer.position || 0)) : 0
  }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + (rest < 10 ? "0" : "") + rest
  }

  function runAction(action) {
    if (!mediaService || !activePlayer) return
    mediaService.runAction(action, false, mediaService.playerKey(activePlayer))
  }

  onActivePlayerChanged: syncPosition()
  onPanelOpenChanged: if (panelOpen) syncPosition()

  Timer {
    interval: 500
    repeat: true
    running: root.panelOpen && root.activePlayer !== null && root.activePlayer.isPlaying
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  Column {
    id: mediaColumn
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: Style.space(10)

    Text {
      width: parent.width
      text: "NOW PLAYING"
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
    }

    Item {
      width: parent.width
      height: Style.space(210)

      BorderSurface {
        id: cover
        anchors.centerIn: parent
        width: Style.space(200)
        height: width
        radius: Style.cornerRadius > 0 ? Style.space(16) : 0
        clip: true
        color: Style.normalFillFor(root.foreground, Color.accent)
        borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

        Image {
          anchors.fill: parent
          anchors.margins: cover.borderLeft + Style.space(2)
          source: root.artUrl
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          visible: source !== ""
        }

        Text {
          anchors.centerIn: parent
          visible: root.artUrl === ""
          text: "󰝚"
          color: Qt.darker(root.foreground, 1.35)
          font.family: root.fontFamily
          font.pixelSize: Style.space(72)
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: root.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: root.artist
        color: Qt.darker(root.foreground, 1.35)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }

      Text {
        visible: root.album !== ""
        width: parent.width
        text: root.album
        color: Qt.darker(root.foreground, 1.65)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }

    Item {
      visible: root.trackLength > 0
      width: parent.width
      height: visible ? Style.space(24) : 0

      Rectangle {
        id: progressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(4)
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

        Rectangle {
          height: parent.height
          width: parent.width * Math.min(1, root.trackPosition / Math.max(1, root.trackLength))
          radius: parent.radius
          color: Style.selectedStateColor(root.foreground, Color.accent)

          Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        anchors.left: parent.left
        anchors.top: progressTrack.bottom
        anchors.topMargin: Style.space(2)
        text: root.formatTime(root.trackPosition)
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.right: parent.right
        anchors.top: progressTrack.bottom
        anchors.topMargin: Style.space(2)
        text: root.formatTime(root.trackLength)
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)

      Button {
        iconText: "󰒮"
        tooltipText: "Previous"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.iconLarge
        enabled: root.activePlayer && root.activePlayer.canGoPrevious
        opacity: enabled ? 1 : 0.35
        onClicked: root.runAction("previous")
      }

      Button {
        iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
        tooltipText: root.activePlayer && root.activePlayer.isPlaying ? "Pause" : "Play"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.iconLarge
        horizontalPadding: Style.spacing.panelGap
        enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
        opacity: enabled ? 1 : 0.35
        onClicked: root.runAction("playPause")
      }

      Button {
        iconText: "󰒭"
        tooltipText: "Next"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.iconLarge
        enabled: root.activePlayer && root.activePlayer.canGoNext
        opacity: enabled ? 1 : 0.35
        onClicked: root.runAction("next")
      }
    }

    Text {
      visible: root.activePlayer !== null
      width: parent.width
      text: root.sourceName.toUpperCase()
      color: Qt.darker(root.foreground, 1.8)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }
}
