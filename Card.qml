import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The issue card, on the right of the list (Panel.qml). Key, title and link
// copy on click; the fields write straight to Jira and the card rereads
// itself afterwards (Panel.write).
Flickable {
  id: root

  property var jira: null
  readonly property var card: jira ? jira.cardData : null
  readonly property color fg: jira && jira.bar ? jira.bar.foreground : Color.foreground
  readonly property var tr: jira ? jira.tr : function(t) { return t }
  readonly property string ff: jira && jira.bar ? jira.bar.fontFamily : Style.font.family
  property bool attachmentsOpen: false
  property bool commentsOpen: false
  property bool editingSummary: false
  // Only status, assignee, the flag and comments are edited for now; the
  // title, priority, type, story points, epic and labels are read-only. Their editors stay, behind this.
  readonly property bool fullEdit: false

  clip: true
  contentWidth: width
  contentHeight: column.implicitHeight
  boundsBehavior: Flickable.StopAtBounds

  // Dropdown overwrites its own value on a pick, so values are set here
  // each time the issue is (re)read instead of bound.
  function sync() {
    if (!card) return
    statusBox.value = ""
    priorityBox.value = card.priorityId
    typeBox.value = card.typeId
    pointsField.text = card.storyPoints
    epicField.text = card.epic
    labelsField.text = card.labels.join(" ")
  }

  onCardChanged: sync()
  // Another issue: a comment begun on this one doesn't go along.
  Connections {
    target: root.jira
    function onCardKeyChanged() { root.attachmentsOpen = false; root.commentsOpen = false; root.editingSummary = false; commentField.text = ""; root.contentY = 0 }
  }

  Column {
    id: column
    width: root.width
    spacing: Style.space(22)
    visible: root.card !== null

    // ---- Open in the browser and the flag on the left; on the right, back to the card a link came from.
    Item {
      width: parent.width
      height: openButton.implicitHeight

      CardButton {
        id: openButton
        text: root.tr("Open")
        iconText: "󰏌"
        onClicked: root.jira.browse(root.card.key)
      }

      CardButton {
        x: openButton.width + Style.space(8)
        visible: root.jira.ids.flagged !== ""
        text: root.card && root.card.flagged ? root.tr("Remove flag") : root.tr("Add flag")
        iconText: "󰈻"
        selected: !!(root.card && root.card.flagged)
        onClicked: root.jira.setFlag(!root.card.flagged)
      }

      Text {
        anchors.centerIn: parent
        visible: root.jira.copiedNote !== ""
        text: root.jira.copiedNote
        color: Qt.darker(root.fg, 1.4)
        font.family: root.ff
        font.pixelSize: Style.font.body
        font.bold: true
      }

      CardButton {
        readonly property var last: root.jira.cardTrail[root.jira.cardTrail.length - 1]
        anchors.right: parent.right
        visible: !!last
        text: last ? last.key : ""
        iconText: "󰁍"
        tooltipText: root.tr("Back")
        onClicked: root.jira.backCard()
      }
    }

    // ---- Key, title and link: one block, close together.
    Column {
      width: parent.width
      spacing: Style.space(8)

      // A subtask's parent key comes first; a click opens the parent.
      Row {
        // Flagged: the colour of a flagged row in the list, solid.
        Text {
          visible: !!(root.card && root.card.flagged)
          text: "󰈻 " + root.tr("Flagged").toUpperCase() + " · "
          textFormat: Text.PlainText
          font.family: root.ff
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: 1.2
          color: Qt.rgba(root.jira.flagTint.r, root.jira.flagTint.g, root.jira.flagTint.b, 1)
        }

        Text {
          visible: !!(root.card && root.card.parent)
          text: root.card ? root.card.parent + " / " : ""
          textFormat: Text.PlainText
          font.family: root.ff
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: 1.2
          font.underline: parentHover.hovered
          color: root.fg
          HoverHandler { id: parentHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.jira.follow(root.card.parent) }
        }

        Copyable {
          text: root.card ? root.card.key + " · " + root.card.typeName : ""
          copyText: root.card ? root.card.key : ""
          what: "key"
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: 1.2
          color: Qt.darker(root.fg, 1.4)
        }
      }

      // ---- Title: a click copies it, the pencil edits it.
      Item {
        width: parent.width
        height: Math.max(root.editingSummary ? summaryField.implicitHeight : summaryText.implicitHeight, editButton.implicitHeight)

        Copyable {
          id: summaryText
          visible: !root.editingSummary
          anchors.left: parent.left
          anchors.right: editButton.left
          anchors.rightMargin: Style.space(10)
          text: root.card ? root.card.summary : ""
          what: "title"
          wrapMode: Text.Wrap
          font.pixelSize: Style.font.display
          font.bold: true
        }

        TextField {
          id: summaryField
          visible: root.editingSummary
          anchors.left: parent.left
          anchors.right: editButton.left
          anchors.rightMargin: Style.space(10)
          foreground: root.fg
          font.family: root.ff
          font.pixelSize: Style.font.heading
          onAccepted: {
            var t = text.trim()
            root.editingSummary = false
            if (t && t !== root.card.summary) root.jira.update({ summary: t })
          }
          Keys.onEscapePressed: root.editingSummary = false
        }

        CardButton {
          id: editButton
          visible: root.fullEdit
          width: visible ? implicitWidth : 0
          anchors.right: parent.right
          iconText: root.editingSummary ? "󰄬" : "󰏫"
          tooltipText: root.editingSummary ? root.tr("Save") : root.tr("Edit the title")
          onClicked: {
            if (root.editingSummary) { summaryField.accepted(); return }
            summaryField.text = root.card.summary
            root.editingSummary = true
            summaryField.forceActiveFocus()
          }
        }
      }

      Copyable {
        text: root.card ? Model.browseUrl(root.jira.baseUrl, root.card.key) : ""
        what: "link"
        color: Qt.darker(root.fg, 1.4)
        font.pixelSize: Style.font.body
      }
    }

    // ---- The fields over the description: assignee and status, the four
    //      short ones, then reporter and labels.
    Section {
      Column {
        id: fields
        width: parent.width
        spacing: Style.space(22)
        readonly property real gap: Style.space(24)
        readonly property real half: (width - gap) / 2
        readonly property real quarter: (width - gap * 3) / 4

        Row {
          spacing: fields.gap

          Field {
            label: root.tr("Assignee").toUpperCase()
            Column {
              spacing: Style.space(10)
              Value {
                width: fields.half
                text: root.card && root.card.assigneeName || root.tr("Unassigned")
              }
              CardButton {
                visible: root.card && !root.card.mine
                text: root.tr("Assign to me")
                onClicked: root.jira.assignToMe()
              }
            }
          }

          Field {
            label: root.tr("Status").toUpperCase()
            Dropdown {
              id: statusBox
              width: fields.half
              showLabel: false
              foreground: root.fg
              fontFamily: root.ff
              options: root.card ? [{ value: "", label: root.card.statusName }].concat(root.jira.statusMoves.map(function(t) {
                return { value: String(t.id), label: t.to && t.to.name !== t.name ? t.name + " → " + t.to.name : t.name }
              })) : []
              onChanged: function(v) { if (v) root.jira.move(v) }
            }
          }
        }

        Row {
          spacing: fields.gap

          Field {
            label: root.tr("Priority").toUpperCase()
            Value { visible: !root.fullEdit; width: fields.quarter; text: root.card && root.card.priorityName || "—" }
            Dropdown {
              id: priorityBox
              visible: root.fullEdit
              width: fields.quarter
              showLabel: false
              foreground: root.fg
              fontFamily: root.ff
              options: root.jira.priorities
              onChanged: function(v) { if (v !== root.card.priorityId) root.jira.update({ priority: { id: v } }) }
            }
          }

          Field {
            label: root.tr("Type").toUpperCase()
            Value { visible: !root.fullEdit; width: fields.quarter; text: root.card && root.card.typeName || "—" }
            Dropdown {
              id: typeBox
              visible: root.fullEdit
              width: fields.quarter
              showLabel: false
              foreground: root.fg
              fontFamily: root.ff
              // A subtask can only become another subtask type, a standard issue another standard one.
              options: root.card ? root.jira.issueTypes.filter(function(t) { return !!t.subtask === root.card.subtask })
                                     .map(function(t) { return { value: String(t.id), label: t.name } }) : []
              onChanged: function(v) { if (v !== root.card.typeId) root.jira.update({ issuetype: { id: v } }) }
            }
          }

          Field {
            label: root.tr("Story points").toUpperCase() + (root.fullEdit ? " · ENTER" : "")
            visible: root.jira.ids.storyPoints !== ""
            Value { visible: !root.fullEdit; width: fields.quarter; text: root.card && root.card.storyPoints || "—" }
            TextField {
              id: pointsField
              visible: root.fullEdit
              width: fields.quarter
              foreground: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              onAccepted: {
                var v = Model.parsePoints(text)
                if (isNaN(v)) { root.jira.problem = root.tr("Story points must be a number"); return }
                var f = {}
                f[root.jira.ids.storyPoints] = v
                root.jira.update(f)
              }
            }
          }

          Field {
            label: root.tr("Epic").toUpperCase() + (root.fullEdit ? " · ENTER" : "")
            visible: root.jira.ids.epic !== "" && root.card && !root.card.subtask
            // The epic opens here, like a link to an issue.
            Value {
              visible: !root.fullEdit
              width: Math.min(implicitWidth, fields.quarter)
              text: root.card && root.card.epic || "—"
              color: root.card && root.card.epic ? Color.accent : root.fg
              font.underline: epicHover.hovered
              HoverHandler { id: epicHover; enabled: !!(root.card && root.card.epic); cursorShape: Qt.PointingHandCursor }
              TapHandler { enabled: !!(root.card && root.card.epic); onTapped: root.jira.follow(root.card.epic) }
            }
            TextField {
              id: epicField
              visible: root.fullEdit
              width: fields.quarter
              placeholderText: "DEMO-123"
              foreground: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              onAccepted: {
                var f = {}
                f[root.jira.ids.epic] = text.trim().toUpperCase() || null
                root.jira.update(f)
              }
            }
          }
        }

        Row {
          spacing: fields.gap

          Field {
            label: root.tr("Reporter").toUpperCase()
            Value { width: fields.half; text: root.card && root.card.reporterName || "—" }
          }

          Field {
            label: root.tr("Labels").toUpperCase() + (root.fullEdit ? " · ENTER" : "")
            Value { visible: !root.fullEdit; width: fields.half; wrapMode: Text.Wrap; text: root.card && root.card.labels.join(", ") || "—" }
            TextField {
              id: labelsField
              visible: root.fullEdit
              width: fields.half
              placeholderText: root.tr("space-separated")
              foreground: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              onAccepted: root.jira.update({ labels: Model.parseLabels(text) })
            }
          }
        }
      }
    }

    // ---- Description.
    Section {
      visible: !!(root.card && root.card.description)
      TextEdit {
        visible: !!(root.card && root.card.description)
        width: parent.width
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.RichText
        // Jira's own rendering when it came with the issue, else the markup with its links made live.
        text: !root.card ? "" : root.card.descriptionHtml
              ? Model.richDescription(root.card.descriptionHtml, root.jira.baseUrl, String(Color.accent))
              : Model.linkify(root.card.description, String(Color.accent))
        onLinkActivated: function(link) { root.jira.openLink(link) }

        HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
        wrapMode: TextEdit.Wrap
        color: root.fg
        font.family: root.ff
        font.pixelSize: Style.font.title
      }
    }

    // ---- Attachments and subtasks, one block.
    Section {
      visible: !!(root.card && (root.card.attachments.length || root.card.subtasks.length))

      // ---- Attachments: hidden under a button; a
      //      click on a file downloads it (Panel.download).
      Column {
        visible: root.card && root.card.attachments.length > 0
        width: parent.width
        spacing: Style.space(10)

        CardButton {
          text: root.tr("Attachments") + " · " + (root.card ? root.card.attachments.length : 0)
          iconText: root.attachmentsOpen ? "󰅃" : "󰅀"
          onClicked: root.attachmentsOpen = !root.attachmentsOpen
        }

        Repeater {
          model: root.attachmentsOpen && root.card ? root.card.attachments : []

          CursorSurface {
            id: file
            required property var modelData
            readonly property bool busy: !!root.jira.downloading[modelData.id]
            width: parent.width
            implicitHeight: fileName.implicitHeight + Style.space(18)
            foreground: root.fg
            hasCursor: fileMouse.containsMouse

            MouseArea {
              id: fileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: file.busy ? Qt.BusyCursor : Qt.PointingHandCursor
              onClicked: root.jira.download(file.modelData)
            }

            Text {
              id: fileIcon
              x: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: file.busy ? "󰇚" : "󰈔"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.iconLarge
            }

            Text {
              id: fileName
              anchors.left: fileIcon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: fileSize.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: file.modelData.name
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              elide: Text.ElideMiddle
            }

            Text {
              id: fileSize
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: file.busy ? root.tr("downloading…") : Model.sizeText(file.modelData.size, root.tr, Qt.locale().decimalPoint)
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.body
            }
          }
        }
      }

      // ---- Subtasks.
      Column {
        visible: root.card && root.card.subtasks.length > 0
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: root.tr("Subtasks").toUpperCase() + " · " + (root.card ? root.card.subtasks.length : 0)
          color: Qt.darker(root.fg, 1.4)
          font.family: root.ff
          font.pixelSize: Style.font.body
          font.bold: true
          font.letterSpacing: 1.2
        }

        Repeater {
          model: root.card ? root.card.subtasks : []

          CursorSurface {
            id: sub
            required property var modelData
            width: parent.width
            implicitHeight: subText.implicitHeight + Style.space(18)
            foreground: root.fg
            hasCursor: subMouse.containsMouse

            MouseArea {
              id: subMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.jira.follow(sub.modelData.key)
            }

            Text {
              id: subText
              x: Style.space(8)
              width: parent.width - Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: sub.modelData.key + "   " + sub.modelData.summary + "   · " + sub.modelData.status
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              elide: Text.ElideRight
            }
          }
        }
      }
    }

    // ---- Comments: read when opened; a new one goes in alone or with the flag.
    Section {
      Column {
        width: parent.width
        spacing: Style.space(14)

        CardButton {
          text: root.tr("Comments") + (root.jira.comments ? " · " + root.jira.comments.length : "")
          iconText: root.commentsOpen ? "󰅃" : "󰅀"
          onClicked: {
            root.commentsOpen = !root.commentsOpen
            if (root.commentsOpen && root.jira.comments === null) root.jira.loadComments()
          }
        }

        TextField {
          id: commentField
          visible: root.commentsOpen
          width: parent.width
          placeholderText: root.tr("New comment")
          foreground: root.fg
          font.family: root.ff
          font.pixelSize: Style.font.title
          onAccepted: if (text.trim()) { root.jira.comment(text.trim(), false); text = "" }
        }

        Row {
          visible: root.commentsOpen
          spacing: Style.space(10)
          CardButton {
            text: root.tr("Comment")
            iconText: "󰆉"
            enabled: commentField.text.trim() !== ""
            onClicked: commentField.accepted()
          }
          CardButton {
            visible: root.jira.ids.flagged !== "" && root.card && !root.card.flagged
            text: root.tr("Flag and comment")
            iconText: "󰈻"
            enabled: commentField.text.trim() !== ""
            onClicked: { root.jira.comment(commentField.text.trim(), true); commentField.text = "" }
          }
        }

        Repeater {
          model: root.commentsOpen && root.jira.comments ? root.jira.comments : []

          Column {
            required property var modelData
            width: parent.width
            spacing: Style.space(6)
            bottomPadding: Style.space(10)
            Text {
              text: modelData.author + " · " + Qt.formatDateTime(modelData.time, "dd.MM.yyyy hh:mm")
              textFormat: Text.PlainText
              color: Qt.darker(root.fg, 1.4)
              font.family: root.ff
              font.pixelSize: Style.font.body
              font.bold: true
            }
            TextEdit {
              width: parent.width
              readOnly: true
              selectByMouse: true
              textFormat: TextEdit.RichText
              text: modelData.html
              onLinkActivated: function(link) { root.jira.openLink(link) }
              HoverHandler { cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.IBeamCursor }
              wrapMode: TextEdit.Wrap
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
            }
          }
        }

        Text {
          visible: root.commentsOpen && root.jira.comments !== null && root.jira.comments.length === 0
          text: root.tr("No comments")
          color: Qt.darker(root.fg, 1.4)
          font.family: root.ff
          font.pixelSize: Style.font.title
        }
      }
    }
  }

  Text {
    visible: root.card === null
    anchors.centerIn: parent
    text: root.tr("Loading…")
    color: Qt.darker(root.fg, 1.4)
    font.family: root.ff
    font.pixelSize: Style.font.heading
  }

  component Field: Column {
    property string label
    spacing: Style.space(8)
    Text {
      text: parent.label
      color: Qt.darker(root.fg, 1.4)
      font.family: root.ff
      font.pixelSize: Style.font.body
      font.bold: true
      font.letterSpacing: 1.2
    }
  }

  component Value: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.ff
    font.pixelSize: Style.font.title
    elide: Text.ElideRight
  }

  // Text that copies itself (or copyText) on a click.
  component Copyable: Text {
    id: c
    property string copyText: text
    property string what
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.ff
    font.pixelSize: Style.font.title
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.jira.copy(c.copyText, c.what)
    }
  }

  // A block of the card under a rule; inside it the parts are set apart by space only.
  component Section: Column {
    width: parent.width
    spacing: Style.space(22)
    PanelSeparator { foreground: root.fg }
  }

  // The card's buttons: bordered, text and icon one step over the body text.
  component CardButton: Button {
    foreground: root.fg
    fontFamily: root.ff
    fontSize: Style.font.title
    iconSize: Style.font.title
    bordered: true
  }
}
