import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Now-playing section of the clock hub. Playback comes from Omarchy's MPRIS
// service, so this component only owns presentation and which source is in
// view.
//
// With more than one source the card becomes a carousel: one card per player,
// arrows and dots to move between them, and transport buttons that address
// the card's own player instead of whatever the service calls active.
Item {
  id: root

  property var bar: null
  property var mediaService: null
  property bool panelOpen: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal closeRequested()

  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  // Ordered by player key, not by the service's playing-first order: pausing
  // a source must not move its card or shift the dots.
  readonly property var sources: mediaService
    ? Model.orderedMediaSources(mediaService.sourcePlayers, function(player) { return mediaService.playerKey(player) })
    : []
  readonly property bool hasMultipleSources: sources.length > 1

  // The service honors its own preferredPlayerKey only while that player is
  // playing, so a paused source picked here would snap back as soon as
  // anything else plays. The hub keeps the focused source itself; an empty
  // key means "follow whatever is active".
  property string focusedKey: ""

  readonly property int activeIndex: activePlayer ? indexOfPlayer(activePlayer) : -1
  readonly property int focusedIndex: {
    var chosen = indexOfKey(focusedKey)
    if (chosen >= 0) return chosen
    if (activeIndex >= 0) return activeIndex
    return sources.length > 0 ? 0 : -1
  }
  readonly property var focusedPlayer: focusedIndex >= 0 ? sources[focusedIndex] : activePlayer

  property real trackPosition: 0
  property bool userMovingCarousel: false

  implicitWidth: Style.space(270)
  implicitHeight: mediaColumn.implicitHeight

  function indexOfKey(key) {
    if (!mediaService || !key) return -1
    for (var i = 0; i < sources.length; i++) {
      if (mediaService.playerKey(sources[i]) === key) return i
    }
    return -1
  }

  function indexOfPlayer(player) {
    return mediaService && player ? indexOfKey(mediaService.playerKey(player)) : -1
  }

  function focusSource(index) {
    if (!mediaService || index < 0 || index >= sources.length) return

    var player = sources[index]
    if (!player) return

    focusedKey = mediaService.playerKey(player)
    syncPosition()
  }

  // Every transport action goes through here, from the card buttons and from
  // the keyboard. Pinning first matters: pausing a source costs it the
  // service's active-player role, and an unpinned hub would follow that to
  // another card.
  function runActionOn(index, action) {
    if (!mediaService || index < 0 || index >= sources.length) return false

    var player = sources[index]
    if (!player) return false

    focusedKey = mediaService.playerKey(player)
    var handled = mediaService.runAction(action, false, focusedKey)
    if (handled && (action === "next" || action === "previous")) trackPosition = 0
    return handled
  }

  // Toggles the card in view, not whatever the service considers active.
  // Reports back whether it had anything to toggle so the panel can keep the
  // key useful when the hub shows no source at all.
  function togglePlayPause() {
    return runActionOn(focusedIndex, "playPause")
  }

  function stepSource(delta) {
    if (sources.length < 2) return
    focusSource(Model.cycleIndex(Math.max(0, focusedIndex), delta, sources.length))
  }

  function syncCarousel() {
    if (focusedIndex >= 0 && carousel.currentIndex !== focusedIndex) carousel.currentIndex = focusedIndex
  }

  // The service rebuilds its list on every playback change, which resets the
  // view. Restoring the focused card has to be silent, or a pause would look
  // like the carousel turning.
  function restoreCarousel() {
    if (focusedIndex < 0) return
    carousel.currentIndex = focusedIndex
    carousel.positionViewAtIndex(focusedIndex, ListView.SnapPosition)
  }

  function syncPosition() {
    trackPosition = focusedPlayer ? Math.max(0, Number(focusedPlayer.position || 0)) : 0
  }

  function regexEscape(value) {
    return String(value || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  }

  function luaQuote(value) {
    return "\"" + String(value || "").replace(/\\/g, "\\\\").replace(/\"/g, "\\\"") + "\""
  }

  function openMediaSource(player) {
    if (!player) return

    if (player.canRaise) {
      player.raise()
    } else {
      var title = String(player.trackTitle || "").replace(/[\r\n]+/g, " ").trim()
      var desktopEntry = Model.mediaSourceApp(player)
      if (title !== "") {
        var selector = "title:.*" + regexEscape(title) + ".*"
        sourceProcess.command = ["hyprctl", "dispatch", "hl.dsp.focus({ window = " + luaQuote(selector) + " })"]
        sourceProcess.running = true
      } else if (desktopEntry !== "") {
        sourceProcess.command = ["gtk-launch", desktopEntry]
        sourceProcess.running = true
      } else {
        return
      }
    }

    root.closeRequested()
  }

  onFocusedPlayerChanged: syncPosition()
  onFocusedIndexChanged: syncCarousel()
  // A player appearing or disappearing reorders the list, which can move the
  // focused card without changing its key.
  onSourcesChanged: Qt.callLater(restoreCarousel)
  // Reopening the hub should show what is playing, not last session's pick.
  onPanelOpenChanged: {
    if (panelOpen) syncPosition()
    else focusedKey = ""
  }

  Component.onCompleted: syncCarousel()

  Timer {
    interval: 500
    repeat: true
    running: root.panelOpen && root.focusedPlayer !== null && root.focusedPlayer.isPlaying
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  Process {
    id: sourceProcess
    running: false
  }

  Column {
    id: mediaColumn
    width: parent.width
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: Math.max(sectionLabel.implicitHeight, navRow.implicitHeight)

      Text {
        id: sectionLabel
        anchors.centerIn: parent
        text: "NOW PLAYING"
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
        font.bold: true
      }

      Row {
        id: navRow
        visible: root.hasMultipleSources
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        PanelActionButton {
          iconText: "󰅁"
          tooltipText: "Previous source"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          onClicked: root.stepSource(-1)
        }

        PanelActionButton {
          iconText: "󰅂"
          tooltipText: "Next source"
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.body
          onClicked: root.stepSource(1)
        }
      }
    }

    Item {
      width: parent.width
      // Cards are structurally identical, so the placeholder below is also
      // the height reference for every card in the carousel.
      height: placeholderCard.implicitHeight

      MediaSourceCard {
        id: placeholderCard
        visible: root.sources.length === 0
        width: parent.width
        height: parent.height
        player: null
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      ListView {
        id: carousel
        visible: root.sources.length > 0
        anchors.fill: parent
        clip: true
        orientation: ListView.Horizontal
        model: root.sources
        interactive: root.hasMultipleSources
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        highlightMoveDuration: 220
        highlightMoveVelocity: -1
        boundsBehavior: Flickable.StopAtBounds
        // Keep every card alive so swiping never lands on an empty frame.
        cacheBuffer: Math.max(0, width * 4)
        // Only a finished drag or flick changes the focus. currentIndex also
        // moves while dragging and on model resets, which must not count as
        // the user picking a source, so the move has to start at the pointer.
        onDragStarted: root.userMovingCarousel = true
        onFlickStarted: root.userMovingCarousel = true
        onMovementEnded: {
          if (!root.userMovingCarousel) return
          root.userMovingCarousel = false
          root.focusSource(carousel.currentIndex)
        }

        delegate: MediaSourceCard {
          required property var modelData
          required property int index

          width: carousel.width
          height: carousel.height
          player: modelData
          foreground: root.foreground
          fontFamily: root.fontFamily
          // Only the focused card is on screen, so only it gets the polled
          // position. The rest read whatever the player last reported.
          positionSeconds: index === root.focusedIndex
            ? root.trackPosition
            : (modelData ? Math.max(0, Number(modelData.position || 0)) : 0)
          onOpenRequested: root.openMediaSource(modelData)
          onActionRequested: function(action) { root.runActionOn(index, action) }
        }
      }
    }

    Row {
      id: dotsRow
      visible: root.hasMultipleSources
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(6)
      transform: Translate { y: -Style.space(6) }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "p"
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.sources

        Item {
          id: dot
          required property var modelData
          required property int index

          readonly property bool current: index === root.focusedIndex

          width: Style.space(16)
          height: Style.space(16)

          Rectangle {
            anchors.centerIn: parent
            width: Style.space(7)
            height: width
            radius: width / 2
            color: dot.current || dotMouse.containsMouse
              ? root.foreground
              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.28)

            Behavior on color {
              ColorAnimation { duration: 120 }
            }
          }

          MouseArea {
            id: dotMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusSource(dot.index)
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "n"
        color: Qt.darker(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
