import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One MPRIS source as a full card: artwork, track text, progress, transport.
// The card only reports which action was pressed. MediaHub owns the call into
// the service so that acting on a card and pinning it stay one step.
//
// Card height must not depend on which player is shown: MediaHub sizes every
// card in its carousel from a single instance. The album line and the source
// label therefore keep their slot when empty, and the artist line always has
// text to show.
Item {
  id: root

  property var player: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real positionSeconds: 0

  signal openRequested()
  signal actionRequested(string action)

  readonly property bool hasTrack: player !== null && !!(player.trackTitle || player.trackArtist)
  readonly property string title: player === null
    ? "Nothing playing"
    : (Model.mediaSourceLabel(player) || "Unknown title")
  readonly property string artist: player === null
    ? "Start playback in a media app"
    : (hasTrack
      ? (player.trackArtist || "Unknown artist")
      : (Model.mediaSourceDetail(player) || "No track information"))
  readonly property string album: player !== null && player.trackAlbum ? player.trackAlbum : ""
  readonly property string artUrl: player !== null && player.trackArtUrl ? player.trackArtUrl : ""
  readonly property string sourceName: player === null
    ? ""
    : (player.identity || Model.mediaSourceApp(player) || "Media")
  readonly property real trackLength: player !== null ? Math.max(0, Number(player.length || 0)) : 0
  readonly property bool playing: player !== null && !!player.isPlaying

  implicitWidth: Style.space(270)
  implicitHeight: cardColumn.implicitHeight

  function runAction(action) {
    if (!player) return
    root.actionRequested(action)
  }

  // Line metrics for the caption-sized slots below. Measuring an item that
  // always has text keeps those slots at a constant height.
  Text {
    id: captionMetrics
    visible: false
    text: "M"
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    id: cardColumn
    width: parent.width
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: Style.space(210)

      BorderSurface {
        id: cover
        anchors.centerIn: parent
        width: Style.space(200)
        height: width
        radius: Style.cornerRadius
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

        MouseArea {
          anchors.fill: parent
          enabled: root.player !== null
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.openRequested()
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

      Item {
        width: parent.width
        height: captionMetrics.implicitHeight

        Text {
          anchors.fill: parent
          text: root.album
          color: Qt.darker(root.foreground, 1.65)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(24)

      ThemeProgressBar {
        id: progressTrack
        visible: root.trackLength > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(4)
        value: Math.min(1, root.positionSeconds / Math.max(1, root.trackLength))
        foreground: root.foreground
        trackColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
        animationDuration: 450
      }

      Text {
        visible: root.trackLength > 0
        anchors.left: parent.left
        anchors.top: progressTrack.bottom
        anchors.topMargin: Style.space(2)
        text: Model.mediaTimeLabel(root.positionSeconds)
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: root.trackLength > 0
        anchors.right: parent.right
        anchors.top: progressTrack.bottom
        anchors.topMargin: Style.space(2)
        text: Model.mediaTimeLabel(root.trackLength)
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
        enabled: root.player && root.player.canGoPrevious
        opacity: enabled ? 1 : 0.35
        onClicked: root.runAction("previous")
      }

      Button {
        iconText: root.playing ? "󰏤" : "󰐊"
        tooltipText: root.playing ? "Pause" : "Play"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.iconLarge
        horizontalPadding: Style.spacing.panelGap
        enabled: root.player && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
        opacity: enabled ? 1 : 0.35
        onClicked: root.runAction("playPause")
      }

      Button {
        iconText: "󰒭"
        tooltipText: "Next"
        foreground: root.foreground
        fontFamily: root.fontFamily
        iconSize: Style.font.iconLarge
        enabled: root.player && root.player.canGoNext
        opacity: enabled ? 1 : 0.35
        onClicked: root.runAction("next")
      }
    }

    Item {
      width: parent.width
      height: captionMetrics.implicitHeight

      Text {
        anchors.fill: parent
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
}
