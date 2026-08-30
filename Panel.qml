import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "flathack.otp"
  ipcTarget: "flathack.otp"

  property var accounts: []
  property string errorText: ""
  property int selectedIndex: 0
  property string focusSection: "accounts"
  property bool cursorActive: false
  property string filterText: ""
  property string actionStatus: ""
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  property int tickEpoch: Math.floor(Date.now() / 1000)

  readonly property url helperUrl: Qt.resolvedUrl("bin/omarchy-otp")
  readonly property string helperPath: decodeURIComponent(String(helperUrl).replace(/^file:\/\//, ""))

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property var filteredAccounts: {
    var query = filterText.trim().toLowerCase()
    var result = []
    for (var index = 0; index < accounts.length; index++) {
      var account = accounts[index]
      var haystack = (String(account.name || "") + " "
        + String(account.issuer || "")).toLowerCase()
      if (query === "" || haystack.indexOf(query) !== -1)
        result.push({ account: account })
    }
    return result
  }

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
    actionStatus = ""
    deleteConfirmOpen = false
    deleteTarget = null
    cursorActive = false
    filterText = ""
  }

  function refresh() {
    if (!otpProcess.running) otpProcess.running = true
  }

  function parseAccounts(raw) {
    if (!opened) return
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      accounts = Array.isArray(parsed.accounts) ? parsed.accounts : []
      selectedIndex = Math.max(0, Math.min(selectedIndex, filteredAccounts.length - 1))
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
    if (index < 0 || index >= filteredAccounts.length || copyProcess.running) return
    var entry = filteredAccounts[index]
    cursorActive = true
    focusSection = "accounts"
    selectedIndex = index
    errorText = ""
    copyProcess.command = [helperPath, "copy", String(entry.account.id),
      "--clear-after", String(Math.max(0, Number(setting("clipboardClearSeconds", 30)) || 0))]
    copyProcess.running = true
  }

  function openAccountSetup() {
    close()
    if (bar) bar.run("omarchy launch floating terminal with presentation "
      + Util.shellQuote(helperPath) + " add")
  }

  function moveSelection(delta) {
    if (!cursorActive) {
      cursorActive = true
      focusSection = filteredAccounts.length > 0 ? "accounts" : "header"
      selectedIndex = 0
      return
    }

    if (focusSection === "header") {
      if (delta > 0 && filteredAccounts.length > 0) {
        focusSection = "accounts"
        selectedIndex = 0
      }
      return
    }

    if (filteredAccounts.length === 0 || selectedIndex + delta < 0) {
      focusSection = "header"
      return
    }

    selectedIndex = Math.min(filteredAccounts.length - 1, selectedIndex + delta)
  }

  function activateSelection() {
    if (!cursorActive) return
    if (focusSection === "header") openAccountSetup()
    else copyAt(selectedIndex)
  }

  function requestDeleteSelected() {
    if (!cursorActive || focusSection !== "accounts"
        || selectedIndex < 0 || selectedIndex >= filteredAccounts.length
        || removeProcess.running) return

    var account = filteredAccounts[selectedIndex].account
    deleteTarget = {
      id: String(account.id),
      name: String(account.name || "OTP account")
    }
    deleteConfirm.selectedIndex = 1
    deleteConfirmOpen = true
    Qt.callLater(root.focusFilter)
  }

  function cancelDelete() {
    deleteConfirmOpen = false
    deleteTarget = null
    deleteConfirm.selectedIndex = 1
    Qt.callLater(root.focusFilter)
  }

  function confirmDelete() {
    var target = deleteTarget
    deleteConfirmOpen = false
    deleteTarget = null
    if (!target || removeProcess.running) return

    errorText = ""
    removeProcess.command = [helperPath, "remove", String(target.id), "--yes"]
    removeProcess.running = true
  }

  function focusFilter() {
    searchField.forceActiveFocus()
  }

  function resetScroll() {
    if (accountList) accountList.positionViewAtBeginning()
  }

  function revealSelection() {
    if (!accountList || !cursorActive || focusSection !== "accounts" || selectedIndex < 0) return
    accountList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      focusSection = "accounts"
      selectedIndex = 0
      cursorActive = false
      refresh()
      Qt.callLater(root.resetScroll)
      Qt.callLater(root.focusFilter)
    }
  }

  onFilteredAccountsChanged: {
    selectedIndex = Math.max(0, Math.min(selectedIndex, filteredAccounts.length - 1))
    if (filteredAccounts.length === 0 && focusSection === "accounts") cursorActive = false
    else Qt.callLater(root.revealSelection)
  }

  onSelectedIndexChanged: Qt.callLater(root.revealSelection)
  onFocusSectionChanged: {
    if (focusSection === "header") Qt.callLater(root.resetScroll)
    else Qt.callLater(root.revealSelection)
  }

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
        root.actionStatus = "COPIED"
        actionTimer.restart()
      } else {
        root.errorText = failure || "Could not copy the code."
      }
    }
    stderr: StdioCollector { id: copyStderr; waitForEnd: true }
  }

  Process {
    id: removeProcess
    onExited: function(exitCode) {
      var failure = String(removeStderr.text || "").trim()
      if (exitCode === 0) {
        root.actionStatus = "DELETED"
        actionTimer.restart()
        root.refresh()
      } else root.errorText = failure || "Could not delete the account."
      Qt.callLater(root.focusFilter)
    }
    stderr: StdioCollector { id: removeStderr; waitForEnd: true }
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
    id: actionTimer
    interval: 1400
    onTriggered: root.actionStatus = ""
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
    focusTarget: searchField
    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onActivateRequested: root.activateSelection()
      onDeleteRequested: root.requestDeleteSelected()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "/") root.focusFilter()
        else if (text === "r" || text === "R") root.refresh()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
            width: parent.width
            title: "OTP Codes"
            meta: root.filterText === ""
              ? (root.accounts.length === 1 ? "1 account" : root.accounts.length + " accounts")
              : root.filteredAccounts.length + " of " + root.accounts.length + " accounts"
            detail: root.actionStatus
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
            trailingControl: Component {
              PanelActionButton {
                iconText: "\uf067"
                tooltipText: "Add account"
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.headerHasCursor
                onHasCursorChanged: if (hasCursor) root.resetScroll()
                onHovered: function(on) {
                  if (on) {
                    root.cursorActive = true
                    root.focusSection = "header"
                  }
                }
                onClicked: root.openAccountSetup()
              }
            }
        }

        TextField {
            id: searchField
            width: parent.width
            placeholderText: "Filter accounts…"
            foreground: root.foreground
            font.family: root.fontFamily
            text: root.filterText
            onTextChanged: {
              root.filterText = text
              root.focusSection = "accounts"
              root.selectedIndex = 0
              root.cursorActive = root.filteredAccounts.length > 0
              Qt.callLater(root.resetScroll)
            }
            Keys.onPressed: function(event) {
              if (root.deleteConfirmOpen) {
                deleteConfirm.handleKey(event)
                event.accepted = true
              } else if (event.key === Qt.Key_Delete) {
                root.requestDeleteSelected()
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (!root.cursorActive && root.filteredAccounts.length > 0) {
                  root.cursorActive = true
                  root.focusSection = "accounts"
                  root.selectedIndex = 0
                }
                root.activateSelection()
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (text !== "") text = ""
                else keyCatcher.forceActiveFocus()
                event.accepted = true
              } else {
                event.accepted = false
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
            text: "No accounts configured yet.\nUse the + button to add one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 1.35
        }

        Text {
            visible: root.errorText === "" && root.accounts.length > 0
              && root.filteredAccounts.length === 0
            width: parent.width
            text: "No matching accounts."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
        }

        ListView {
            id: accountList
            width: parent.width
            height: Math.min(contentHeight, Style.space(360))
            spacing: Style.space(6)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            ScrollBar.vertical: ScrollBar {
              policy: root.filteredAccounts.length > 7
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }

            model: root.filteredAccounts
            currentIndex: root.cursorActive && root.focusSection === "accounts"
              ? root.selectedIndex : -1
            onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(keepCurrentVisible)

            function keepCurrentVisible() {
              if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain)
            }

          delegate: CursorSurface {
              id: accountRow
                required property var modelData
                required property int index
                width: ListView.view.width
                height: rowLayout.implicitHeight + Style.space(16)
                hasCursor: root.cursorActive && root.focusSection === "accounts"
                  && root.selectedIndex === index
                foreground: root.foreground

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: {
                    root.cursorActive = true
                    root.focusSection = "accounts"
                    root.selectedIndex = accountRow.index
                  }
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
                      text: accountRow.modelData.account.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      visible: text !== ""
                      text: accountRow.modelData.account.issuer || ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }

                  Text {
                    text: accountRow.modelData.account.displayCode
                    color: root.foreground
                    font.family: "monospace"
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    font.letterSpacing: 1.5
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Text {
                    text: root.remainingFor(accountRow.modelData.account) + "s"
                    color: root.remainingFor(accountRow.modelData.account) <= 5 ? Color.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: Style.space(24)
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
            }
        }

        Text {
            visible: root.accounts.length > 0
            width: parent.width
            text: "Type to filter  ·  Enter to copy  ·  Delete to remove"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
        }
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 20
        opened: root.deleteConfirmOpen
        message: "Delete " + ((root.deleteTarget && root.deleteTarget.name) || "this account")
          + "? This cannot be undone."
        cancelText: "Cancel"
        confirmText: "Delete"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelDelete()
        onConfirmed: root.confirmDelete()
      }
    }
  }
}
