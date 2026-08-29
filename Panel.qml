import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "steven.otp"
  ipcTarget: "steven.otp"

  property var accounts: []
  property string errorText: ""
  property int selectedIndex: 0
  property string copiedName: ""
  property string pendingCopyName: ""
  property int tickEpoch: Math.floor(Date.now() / 1000)

  readonly property url helperUrl: Qt.resolvedUrl("bin/omarchy-otp")
  readonly property string helperPath: decodeURIComponent(String(helperUrl).replace(/^file:\/\//, ""))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    tickEpoch = Math.floor(Date.now() / 1000)
    controller.show()
    refresh()
  }

  function close() {
    controller.hide()
    if (otpProcess.running) otpProcess.running = false
    accounts = []
    errorText = ""
    pendingCopyName = ""
  }

  function refresh() {
    if (!otpProcess.running) otpProcess.running = true
  }

  function parseAccounts(raw) {
    if (!opened) return
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      accounts = Array.isArray(parsed.accounts) ? parsed.accounts : []
      selectedIndex = Math.max(0, Math.min(selectedIndex, accounts.length - 1))
      errorText = ""
    } catch (error) {
      errorText = "Could not read OTP data."
    }
  }

  function remainingFor(account) {
    var period = Math.max(1, Number(account.period) || 30)
    return period - (tickEpoch % period)
  }

  function codesNeedRefresh() {
    for (var index = 0; index < accounts.length; index++) {
      var account = accounts[index]
      var period = Math.max(1, Number(account.period) || 30)
      if (Math.floor(tickEpoch / period) !== Number(account.counter)) return true
    }
    return false
  }

  function copyAt(index) {
    if (index < 0 || index >= accounts.length || copyProcess.running) return
    selectedIndex = index
    pendingCopyName = String(accounts[index].name || "OTP")
    errorText = ""
    copyProcess.command = [helperPath, "copy", String(accounts[index].index),
      "--clear-after", String(Math.max(0, Number(setting("clipboardClearSeconds", 30)) || 0))]
    copyProcess.running = true
  }

  function openAccountSetup() {
    close()
    if (bar) bar.run("omarchy launch floating terminal with presentation "
      + Util.shellQuote(helperPath) + " add")
  }

  function moveSelection(delta) {
    if (accounts.length === 0) return
    selectedIndex = Math.max(0, Math.min(accounts.length - 1, selectedIndex + delta))
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) refresh()

  Process {
    id: otpProcess
    command: [root.helperPath, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseAccounts(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (String(text || "").trim() !== "") root.errorText = String(text).trim()
    }
  }

  Process {
    id: copyProcess
    onExited: function(exitCode) {
      var failure = String(copyStderr.text || "").trim()
      if (exitCode === 0) {
        root.copiedName = root.pendingCopyName
        copiedTimer.restart()
      } else {
        root.errorText = failure || "Could not copy the code."
      }
      root.pendingCopyName = ""
    }
    stderr: StdioCollector { id: copyStderr; waitForEnd: true }
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: {
      root.tickEpoch = Math.floor(Date.now() / 1000)
      if (root.codesNeedRefresh()) root.refresh()
    }
  }

  Timer {
    id: copiedTimer
    interval: 1400
    onTriggered: root.copiedName = ""
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf084"
    slotSize: Style.bar.statusSlot
    tooltipText: "OTP codes"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.openAccountSetup()
      else if (mouseButton === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onActivateRequested: root.copyAt(root.selectedIndex)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: "OTP Codes"
            meta: root.accounts.length === 1 ? "1 account" : root.accounts.length + " accounts"
            detail: root.copiedName === "" ? "" : "COPIED"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "\uf084"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.errorText === "" && root.accounts.length === 0
            width: parent.width
            text: "No accounts configured yet.\nRight-click the key icon to add one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.35
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.accounts

              CursorSurface {
                id: accountRow
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: rowLayout.implicitHeight + Style.space(16)
                hasCursor: root.selectedIndex === index
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.selectedIndex = accountRow.index
                  onClicked: root.copyAt(accountRow.index)
                }

                RowLayout {
                  id: rowLayout
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(12)

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: accountRow.modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      visible: text !== ""
                      text: accountRow.modelData.issuer || ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    text: accountRow.modelData.displayCode
                    color: root.foreground
                    font.family: "monospace"
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    font.letterSpacing: 1.5
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Text {
                    text: root.remainingFor(accountRow.modelData) + "s"
                    color: root.remainingFor(accountRow.modelData) <= 5 ? Color.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: Style.space(24)
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
              }
            }
          }

          Text {
            visible: root.accounts.length > 0
            width: parent.width
            text: "Click or press Enter to copy  ·  R to refresh"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
