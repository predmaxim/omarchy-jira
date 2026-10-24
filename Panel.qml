import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "I18n.js" as I18n

// Jira issues of one project in a modal in the middle of the screen: the
// list on the left, the board's last status first (mine and subtasks can be
// filtered), and the picked issue's card (Card.qml) on the right. Talks to
// Jira through scripts/jira, which keeps the token in the keyring.
Panel {
  id: root
  moduleName: "predmaxim.jira"
  ipcTarget: "predmaxim.jira"

  // Interface text in the system's language (I18n.js).
  readonly property var tr: I18n.translator(I18n.textLanguage(function(name) { return Quickshell.env(name) }))
  readonly property string script: Quickshell.env("HOME") + "/.config/omarchy/plugins/predmaxim.jira/scripts/jira"
  readonly property string baseUrl: Model.normalizeUrl(setting("url", ""))
  readonly property string projectKey: String(setting("project", "")).trim().toUpperCase()
  readonly property bool configured: baseUrl !== "" && projectKey !== ""

  property bool settingsOpen: false
  property string settingsProblem: ""
  property bool loading: false
  property string problem: ""
  property int generation: 0
  property var me: null
  property var ids: ({ storyPoints: "", epic: "" })
  property var boardInfo: null
  property var boardConfig: null
  property var columns: []
  property var priorities: []
  property var issueTypes: []
  // The row (issue or status heading) under the mouse or the arrow keys, like the launcher; -1 — none.
  property int cursorIndex: -1
  readonly property bool hideSubtasks: setting("hideSubtasks", false) === true
  readonly property bool onlyMine: setting("onlyMine", false) === true
  // Statuses folded in the list, by board column name; remembered in shell.json.
  readonly property var collapsed: {
    var c = setting("collapsed", [])
    return Array.isArray(c) ? c : []
  }
  // Search: what the field holds; its hits replace the list, an empty field brings the list back.
  property string query: ""
  property var found: []
  property bool searching: false
  property int searchGeneration: 0
  property var projectKeys: []
  readonly property var rows: root.query ? root.found : Model.listRows(root.columns, root.hideSubtasks, root.onlyMine, root.collapsed)
  readonly property int issueCount: root.query ? root.found.length : root.rows.reduce(function(n, r) { return r.group ? n + r.count : n }, 0)
  // What an issue row reads while its slot holds a heading (the row is hidden then).
  readonly property var blankRow: ({ key: "", summary: "", statusName: "", column: "", typeName: "", priorityName: "",
                                     storyPoints: "", assigneeName: "", mine: false, flagged: false, subtask: false, parent: "" })
  // Flagged issues: a warm yellow over the row. The theme has no yellow of
  // its own to take (its "yellow" can be anything), so this one is fixed.
  readonly property color flagTint: Qt.rgba(1, 0.8, 0.2, 0.16)
  // Issue type icons (Model.typeKind). Fixed colours for the same reason:
  // a theme's "red" or "green" can be any colour.
  readonly property var typeIcons: ({ bug: "󰃤", story: "󰃀", debt: "󱌢", other: "󰄲" })
  readonly property var typeColors: ({ bug: "#e5534b", story: "#57ab5a", debt: "#539bf5" })

  property string cardKey: ""
  property var cardData: null
  property var statusMoves: []
  property var movesCache: ({})
  // The open card's comments: null until the card asks (one request), then until "Refresh".
  property var comments: null
  property bool loaded: false
  // The list on disk (Model.cachePlan): shown at once, reread in the background.
  property real savedAt: 0
  property real refsAt: 0
  property var diskCache: null
  property string copiedNote: ""

  readonly property color dim: Qt.darker(root.bar.foreground, 1.4)

  // One request; `done` gets the parsed body (null for an empty one).
  // A failure lands in `problem` and ends the loading state.
  function api(method, path, body, done) {
    var p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector { waitForEnd: true } stderr: StdioCollector { waitForEnd: true } }', root)
    p.exited.connect(function(code) {
      var out = String(p.stdout.text || "")
      if (code === 0) {
        var parsed = null
        try { parsed = out ? JSON.parse(out) : null } catch (e) {}
        if (done) done(parsed)
      } else {
        root.problem = root.tr(Model.errorText(out, p.stderr.text))
        root.loading = false
        root.searching = false
      }
      p.destroy()
    })
    p.command = [root.script, method, root.baseUrl, path].concat(body === undefined ? [] : [JSON.stringify(body)])
    p.running = true
  }

  // Who I am, the custom field ids, priorities, issue types, the board and
  // its columns are read once per session (the server rate-limits every
  // user); after that a reload is one request for the issues.
  function reload(refs) {
    if (!root.configured) return
    var gen = ++root.generation
    root.problem = ""
    root.loading = true
    if (!refs && root.me && root.boardInfo && root.boardConfig) {
      fetchIssues(gen, root.boardInfo, root.boardConfig, 0, [])
      return
    }
    var key = root.projectKey
    api("GET", "/rest/api/2/priority", undefined, function(d) { root.priorities = (d || []).map(function(p) { return { value: String(p.id), label: p.name } }) })
    api("GET", "/rest/api/2/project/" + key, undefined, function(d) { root.issueTypes = d && d.issueTypes || [] })
    api("GET", "/rest/api/2/myself", undefined, function(me) {
      root.me = me
      api("GET", "/rest/api/2/field", undefined, function(fields) {
        root.ids = Model.fieldIds(fields)
        // ponytail: the project's first board; a "board" setting if a project has several.
        api("GET", "/rest/agile/1.0/board?projectKeyOrId=" + encodeURIComponent(key), undefined, function(boards) {
          var b = boards && boards.values && boards.values[0]
          if (!b) { root.problem = root.tr("Project %1 has no board", key); root.loading = false; return }
          root.boardInfo = b
          root.refsAt = Date.now()
          api("GET", "/rest/agile/1.0/board/" + b.id + "/configuration", undefined, function(config) {
            root.boardConfig = config
            fetchIssues(gen, b, config, 0, [])
          })
        })
      })
    })
  }

  function fetchIssues(gen, b, config, startAt, acc) {
    // renderedFields: the description as Jira draws it, for the card.
    var path = "/rest/agile/1.0/board/" + b.id + "/issue?maxResults=100&expand=renderedFields&startAt=" + startAt
      + "&fields=" + Model.requestFields(root.ids) + "&jql=" + encodeURIComponent(Model.boardJql(b.type))
    api("GET", path, undefined, function(d) {
      if (gen !== root.generation) return
      var page = d && d.issues || []
      acc = acc.concat(page)
      // ponytail: stops at 1000 issues, a board that big needs a filter anyway.
      if (page.length && startAt + page.length < d.total && acc.length < 1000) {
        fetchIssues(gen, b, config, startAt + page.length, acc)
        return
      }
      root.columns = Model.board(config, acc, root.ids, root.me)
      root.loaded = true
      root.loading = false
      root.savedAt = Date.now()
      cacheFile.setText(JSON.stringify({ version: Model.CACHE_VERSION, url: root.baseUrl, project: root.projectKey,
        savedAt: root.savedAt, refsAt: root.refsAt, me: root.me, ids: root.ids, priorities: root.priorities,
        issueTypes: root.issueTypes, boardInfo: root.boardInfo, boardConfig: root.boardConfig, columns: root.columns }))
    })
  }

  // ---- The card.
  function findCard(key) {
    for (var f = 0; f < root.found.length; f++)
      if (root.found[f].key === key) return root.found[f]
    for (var i = 0; i < root.columns.length; i++)
      for (var j = 0; j < root.columns[i].issues.length; j++)
        if (root.columns[i].issues[j].key === key) return root.columns[i].issues[j]
    return null
  }

  // The list already carries every field the card shows, so opening a card
  // costs nothing; only the status moves are asked for, once per issue until
  // "Refresh", and after a pause on the issue (the arrows walk through cards).
  // An issue not in the list (a subtask of one) is read on its own.
  function openCard(key) {
    root.cardKey = key
    root.comments = null
    root.cardData = findCard(key)
    root.statusMoves = root.movesCache[key] || []
    if (!root.cardData) loadCard(true, false)
    if (!root.movesCache[key]) movesTimer.restart()
  }

  Timer { id: movesTimer; interval: 400; onTriggered: if (root.cardKey && !root.movesCache[root.cardKey]) root.loadCard(false, true) }

  // A card picked in the list starts a new trail for "Back".
  function pick(key) {
    if (key === root.cardKey) return
    root.cardTrail = []
    root.openCard(key)
  }

  // ---- Links between cards. A link in the card to an issue of this Jira
  //      searches for it, and its card opens from the hits; the card left
  //      goes on the trail with the list it stood in, for "Back".
  property var cardTrail: []
  property string followKey: ""

  function follow(key) {
    if (!key || key === root.cardKey) return
    root.cardTrail = root.cardTrail.concat([{ key: root.cardKey, query: root.query, found: root.found }])
    root.followKey = key
    searchField.text = key
    searchTimer.stop()
    root.search()
    // A click on a link focuses the card's text; the keys go back to the search, so Esc steps back at once.
    searchField.forceActiveFocus()
  }

  // "Back": the card before the last link, in its own list, its row in the middle of the view.
  function backCard() {
    var last = root.cardTrail[root.cardTrail.length - 1]
    if (!last) return
    root.cardTrail = root.cardTrail.slice(0, -1)
    root.followKey = ""
    searchField.text = last.query
    searchTimer.stop()
    ++root.searchGeneration   // a search still under way is dropped
    root.query = last.query
    root.found = last.found
    root.searching = false
    root.showCard(last.key, ListView.Center)
  }

  // The card, and the list's cursor on its row: the arrows go on from there.
  function showCard(key, mode) {
    root.openCard(key)
    var i = root.rows.findIndex(function(r) { return !r.group && r.key === key })
    if (i < 0) return
    root.cursorIndex = i
    pointerGate.reset()
    Qt.callLater(function() { list.positionViewAtIndex(i, mode) })
  }

  // Up/Down walk the rows (Up past the first one leaves them) and the card
  // follows them; typing stays in the search field. The mouse only lights a
  // row up: on its way to the card it would change the card otherwise.
  function moveCursor(step) {
    var i = Math.max(-1, Math.min(root.rows.length - 1, root.cursorIndex + step))
    root.cursorIndex = i
    pointerGate.reset()
    if (i < 0) return
    list.positionViewAtIndex(i, ListView.Contain)
    if (!root.rows[i].group) root.pick(root.rows[i].key)
  }

  // Enter on a heading folds it, on an issue opens the card, as a click does;
  // with no row picked the field searches.
  function activate() {
    var row = root.rows[root.cursorIndex]
    if (!row) return false
    if (row.group) root.toggleGroup(row.column)
    else root.pick(row.key)
    return true
  }
  function enter(event) { if (!root.activate()) event.accepted = false }

  PointerMoveGate { id: pointerGate; referenceItem: listSurface }

  onRowsChanged: if (root.cursorIndex >= root.rows.length) root.cursorIndex = -1

  function closeCard() {
    root.cardKey = ""
    root.cardData = null
    root.cardTrail = []
    root.followKey = ""
    searchField.forceActiveFocus()
  }

  // Search by key or number, one request a pause in typing: a key as typed,
  // a number in every project — one "key in (…)" query, with validation off
  // so keys that don't exist are skipped instead of failing it. The project
  // list is read once, on the first search by number.
  function search() {
    var text = searchField.text.trim()
    var gen = ++root.searchGeneration
    root.query = text
    root.found = []
    if (!text) { root.searching = false; return }
    if (/^\d+$/.test(text) && !root.projectKeys.length) {
      root.searching = true
      api("GET", "/rest/api/2/project", undefined, function(d) {
        root.projectKeys = (d || []).map(function(p) { return p.key })
        if (gen === root.searchGeneration) root.search()
      })
      return
    }
    var keys = Model.searchKeys(text, root.projectKeys, root.projectKey)
    if (!keys.length) { root.searching = false; return }
    root.searching = true
    root.problem = ""
    api("POST", "/rest/api/2/search", { jql: "key in (" + keys.join(",") + ")", validateQuery: false, maxResults: 100,
                                        fields: Model.requestFields(root.ids).split(","), expand: ["renderedFields"] }, function(d) {
      if (gen !== root.searchGeneration) return
      root.found = Model.foundRows(d && d.issues, root.ids, root.me, root.projectKey)
      root.searching = false
      // A link's issue: its card opens, or, not found, the link is undone from the trail.
      if (root.followKey) {
        var k = root.followKey
        root.followKey = ""
        if (root.findCard(k)) root.showCard(k, ListView.Center)
        else root.cardTrail = root.cardTrail.slice(0, -1)
      }
    })
  }

  Timer { id: searchTimer; interval: 400; onTriggered: root.search() }

  function loadCard(issue, moves) {
    var key = root.cardKey
    if (issue) api("GET", "/rest/api/2/issue/" + key + "?expand=renderedFields&fields=" + Model.requestFields(root.ids), undefined, function(d) {
      if (root.cardKey === key) root.cardData = Model.card(d, root.ids, root.me)
    })
    if (moves) api("GET", "/rest/api/2/issue/" + key + "/transitions", undefined, function(d) {
      var cache = Object.assign({}, root.movesCache)
      cache[key] = d && d.transitions || []
      root.movesCache = cache
      if (root.cardKey === key) root.statusMoves = cache[key]
    })
  }

  // "Refresh": the list, the search hits and the open card, read afresh.
  function refresh() {
    root.movesCache = {}
    root.reload()
    if (root.query) root.search()
    if (root.cardKey) root.loadCard(true, true)
    if (root.comments !== null) root.loadComments()
  }

  function loadComments() {
    var key = root.cardKey
    api("GET", "/rest/api/2/issue/" + key + "/comment?expand=renderedBody", undefined, function(d) {
      if (root.cardKey === key) root.comments = Model.comments(d, root.baseUrl, String(Color.accent))
    })
  }

  // A comment, optionally with the flag set first (Jira's "Add flag and comment").
  // Flagged is a checkbox field whose one option is "Impediment".
  function comment(text, flag) {
    var key = root.cardKey
    var post = function() { root.write("POST", "/rest/api/2/issue/" + key + "/comment", { body: text }) }
    if (!flag) { post(); return }
    var f = {}
    f[root.ids.flagged] = [{ value: "Impediment" }]
    api("PUT", "/rest/api/2/issue/" + key, { fields: f }, post)
  }

  function setFlag(on) {
    var f = {}
    f[root.ids.flagged] = on ? [{ value: "Impediment" }] : null
    root.update(f)
  }

  // After a write the card and the list reread from Jira (the moves too: a
  // new status has other ones).
  function write(method, path, body) {
    root.problem = ""
    api(method, path, body, function() { root.refresh() })
  }

  function update(fields) { write("PUT", "/rest/api/2/issue/" + root.cardKey, { fields: fields }) }
  function move(transitionId) { write("POST", "/rest/api/2/issue/" + root.cardKey + "/transitions", { transition: { id: transitionId } }) }
  function assignToMe() { if (root.me) write("PUT", "/rest/api/2/issue/" + root.cardKey + "/assignee", { name: root.me.name }) }

  function browse(key) {
    Quickshell.execDetached(["xdg-open", Model.browseUrl(root.baseUrl, key)])
    root.close()
  }

  // Links from the card: an issue of this Jira opens here (follow), anything
  // else only if http(s), and the panel steps aside for the browser.
  function openLink(url) {
    var key = Model.linkedIssue(url, root.baseUrl)
    if (key) { root.follow(key); return }
    if (!/^https?:\/\//.test(String(url))) return
    Quickshell.execDetached(["xdg-open", String(url)])
    root.close()
  }

  // Attachments go to the Downloads folder through scripts/jira (the token
  // stays there); a notification says where, and a click on it opens the file.
  property var downloading: ({})

  function download(att) {
    if (root.downloading[att.id]) return
    var busy = Object.assign({}, root.downloading)
    busy[att.id] = true
    root.downloading = busy
    var p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector { waitForEnd: true } stderr: StdioCollector { waitForEnd: true } }', root)
    p.exited.connect(function(code) {
      var path = String(p.stdout.text || "").trim()
      var done = Object.assign({}, root.downloading)
      delete done[att.id]
      root.downloading = done
      if (code === 0 && path)
        Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Jira", "-g", "󰇚", root.tr("Downloaded: %1", att.name), path, "--exec", "xdg-open", path])
      else
        Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Jira", "-g", "󰇚", "-u", "normal", root.tr("Not downloaded: %1", att.name),
                                 root.tr(String(p.stderr.text || "").trim() || "download failed")])
      p.destroy()
    })
    p.command = [root.script, "download", root.baseUrl, att.url, att.name]
    p.running = true
  }

  // Fold or unfold a status. Folding rebuilds the list, which puts the view
  // back at the top: the scroll is restored and the heading kept in sight.
  function toggleGroup(name) {
    var c = root.collapsed.slice(), i = c.indexOf(name)
    if (i >= 0) c.splice(i, 1)
    else c.push(name)
    var y = list.contentY
    root.persist({ collapsed: c })
    Qt.callLater(function() {
      list.contentY = y
      list.returnToBounds()
      for (var j = 0; j < root.rows.length; j++)
        if (root.rows[j].group && root.rows[j].column === name) { list.positionViewAtIndex(j, ListView.Contain); break }
    })
  }

  function copy(text, what) {
    Quickshell.execDetached(["wl-copy", "--", text])
    root.copiedNote = root.tr("Copied: %1", root.tr(what))
    copiedTimer.restart()
  }

  Timer { id: copiedTimer; interval: 1500; onTriggered: root.copiedNote = "" }

  // ---- Settings: address and project inline in shell.json (as the built-in
  //      clock does), the token in the keyring through `jira login`.
  function saveSettings(url, project, token) {
    url = Model.normalizeUrl(url)
    project = String(project).trim().toUpperCase()
    if (!url) { root.settingsProblem = root.tr("An address like https://jira.example.com"); return }
    if (!project) { root.settingsProblem = root.tr("A project key is needed"); return }
    persist({ url: url, project: project })
    if (!token) { finishSettings(); return }
    loginProc.secret = token
    loginProc.command = [root.script, "login", url]
    loginProc.running = true
  }

  // Same write path as the built-in clock: the values land inline on this
  // widget's shell.json entry and come back as root.settings.
  function persist(changes) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    for (var c in changes) entry[c] = changes[c]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function finishSettings() {
    root.settingsOpen = false
    root.settingsProblem = ""
    root.closeCard()
    root.columns = []
    root.me = null
    root.boardInfo = null
    root.boardConfig = null
    root.loaded = false
    root.movesCache = {}
    root.reload()
  }

  Process {
    id: loginProc
    property string secret: ""
    stdinEnabled: true
    stderr: StdioCollector { id: loginErr; waitForEnd: true }
    onStarted: { loginProc.write(secret + "\n"); secret = "" }
    onExited: function(code) {
      if (code === 0) root.finishSettings()
      else root.settingsProblem = root.tr("Token not saved: %1", root.tr(String(loginErr.text || "").trim() || "keyring error"))
    }
  }

  // Esc: settings → out of a card field back to the search → back along the
  // links followed → clear the search → close.
  function back() {
    if (root.settingsOpen && root.configured) { root.settingsOpen = false; searchField.forceActiveFocus() }
    else if (cardPane.activeFocus) searchField.forceActiveFocus()
    else if (root.cardTrail.length) root.backCard()
    else if (searchField.text) searchField.text = ""
    else root.close()
  }

  onOpenedChanged: {
    if (!opened) { root.settingsOpen = false; root.closeCard(); root.cursorIndex = -1; return }
    Qt.callLater(function() { (root.settingsOpen ? urlField : searchField).forceActiveFocus() })
    if (!root.configured) root.settingsOpen = true
    else if (!root.loading) {
      // The cached list shows at once; a stale one is reread in the background.
      var c = root.loaded ? { version: Model.CACHE_VERSION, url: root.baseUrl, project: root.projectKey, savedAt: root.savedAt, refsAt: root.refsAt } : root.diskCache
      var plan = Model.cachePlan(c, root.baseUrl, root.projectKey, Date.now())
      if (plan !== "none" && !root.loaded) {
        var d = root.diskCache
        root.me = d.me; root.ids = d.ids; root.priorities = d.priorities; root.issueTypes = d.issueTypes
        root.boardInfo = d.boardInfo; root.boardConfig = d.boardConfig; root.columns = d.columns
        root.savedAt = d.savedAt; root.refsAt = d.refsAt; root.loaded = true
      }
      if (plan !== "fresh") root.reload(plan === "refs" || plan === "none")
    }
  }

  FileView {
    id: cacheFile
    path: Quickshell.env("HOME") + "/.cache/predmaxim.jira-list.json"
    atomicWrites: true
    printErrors: false
    onLoaded: { try { root.diskCache = JSON.parse(text()) } catch (e) {} }
  }

  onSettingsOpenChanged: if (settingsOpen) {
    urlField.text = root.setting("url", "")
    projectField.text = root.projectKey
    tokenField.text = ""
    root.settingsProblem = ""
    urlField.forceActiveFocus()
  }

  // An icon of its own on the right of the bar: it has no state to light up
  // among the indicators.
  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: "󰌃"
    tooltipText: "Jira"
    onPressed: root.toggle()
  }

  // ---- A modal in the middle of the screen, like the reminder prompt: the
  //      list on the left, the card on the right; a click on the dimmed
  //      screen closes it, Esc steps back. Exclusive keyboard like the
  //      polkit dialog: the card has text fields, and it covers the screen anyway.
  PanelWindow {
    id: modal
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    visible: root.opened
    color: Color.menu.scrim
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "predmaxim-jira"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: listSurface
      anchors.centerIn: parent
      // A fixed size, so the window doesn't jump from one card to the next.
      width: Math.min(Style.space(1400), modal.width - Style.space(80))
      height: Math.min(Style.space(1000), modal.height - Style.space(80))
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent }   // clicks on the list stay on it

      PanelKeyCatcher {
        id: keys
        anchors.fill: parent
        anchors.topMargin: listSurface.contentTopInset
        anchors.rightMargin: listSurface.contentRightInset
        anchors.bottomMargin: listSurface.contentBottomInset
        anchors.leftMargin: listSurface.contentLeftInset
        // The search field keeps its own ↑/↓/Enter, so letters (j/k too) go
        // into it; Esc falls through to here. Tab and Delete do nothing. Keys
        // from a field of the card stay its own: the list mustn't move under
        // a comment being typed.
        onMoveRequested: function(dx, dy) { if (dy && !root.settingsOpen && !cardPane.activeFocus) root.moveCursor(dy) }
        onActivateRequested: if (!root.settingsOpen && !cardPane.activeFocus) root.activate()
        onCloseRequested: root.back()

        PanelHero {
          id: hero
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          title: "Jira · " + root.projectKey
          meta: (root.query ? root.tr("Found") : root.onlyMine ? root.tr("My issues") : root.tr("All issues")) + " · " + root.issueCount
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconComponent: Text {
            text: "󰌃"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
          }
          trailingControl: Row {
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.copiedNote !== ""
              text: root.copiedNote
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.configured && !root.settingsOpen
              iconText: "󰀄"
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
              height: width
              tooltipText: root.onlyMine ? root.tr("All issues") : root.tr("My issues")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              selected: root.onlyMine
              onClicked: root.persist({ onlyMine: !root.onlyMine })
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.configured && !root.settingsOpen
              iconText: "󰙅"
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
              height: width
              tooltipText: root.hideSubtasks ? root.tr("Show subtasks") : root.tr("Hide subtasks")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              selected: root.hideSubtasks
              onClicked: root.persist({ hideSubtasks: !root.hideSubtasks })
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              visible: root.configured && !root.settingsOpen
              iconText: "󰑐"
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
              height: width
              iconSpinning: root.loading
              tooltipText: root.tr("Refresh")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.refresh()
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.settingsOpen ? "󰁍" : "󰒓"
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              width: Math.max(implicitWidth, implicitHeight)   // square, like an icon button
              height: width
              tooltipText: root.settingsOpen ? root.tr("Back") : root.tr("Connection")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.settingsOpen ? root.back() : (root.settingsOpen = true)
            }
          }
        }

        // The heading (icon, title, count) opens the board in the browser;
        // the buttons on the right stay out of it.
        MouseArea {
          anchors.left: hero.left
          anchors.top: hero.top
          anchors.bottom: hero.bottom
          width: hero.width - hero.trailingInset
          enabled: root.boardInfo !== null
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openLink(Model.boardUrl(root.baseUrl, root.boardInfo.id))

          PanelToolTip {
            visible: parent.containsMouse
            text: root.tr("Open the board in the browser")
          }
        }

        // The error, wrapped (PanelHero's detail is a badge, too narrow for it).
        Text {
          id: problemLine
          visible: root.problem !== ""
          anchors.top: hero.bottom
          anchors.topMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? implicitHeight : 0
          wrapMode: Text.Wrap
          text: root.problem
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        Item {
          id: body
          anchors.top: problemLine.visible ? problemLine.bottom : hero.bottom
          anchors.topMargin: Style.space(16)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          // ---- Settings: the whole window, under a rule.
          PanelSeparator {
            id: settingsRule
            visible: root.settingsOpen
            width: parent.width
            foreground: root.bar.foreground
          }

          Column {
            visible: root.settingsOpen
            anchors.top: settingsRule.bottom
            anchors.topMargin: Style.space(18)
            width: Math.min(parent.width, Style.space(620))
            spacing: Style.space(6)

            Caption { text: root.tr("Jira address").toUpperCase() }
            TextField {
              id: urlField
              width: parent.width
              placeholderText: "https://jira.example.ru"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              onAccepted: projectField.forceActiveFocus()
            }

            Caption { text: root.tr("Project key").toUpperCase() }
            TextField {
              id: projectField
              width: parent.width
              placeholderText: "DEMO"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              onAccepted: tokenField.forceActiveFocus()
            }

            Caption { text: root.tr("Personal access token · empty keeps the current one").toUpperCase() }
            TextField {
              id: tokenField
              width: parent.width
              password: true
              placeholderText: root.tr("Profile → Personal Access Tokens → Create token")
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              onAccepted: root.saveSettings(urlField.text, projectField.text, tokenField.text)
            }

            Item { width: 1; height: Style.space(6) }

            Row {
              spacing: Style.space(8)
              Button {
                text: root.tr("Save")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.title
                bordered: true
                onClicked: root.saveSettings(urlField.text, projectField.text, tokenField.text)
              }
              Button {
                visible: root.configured
                text: root.tr("Cancel")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.title
                bordered: true
                onClicked: root.back()
              }
            }

            Text {
              visible: root.settingsProblem !== ""
              text: root.settingsProblem
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
          }

          // ---- The list on the left, the search field over it.
          Item {
            id: listPane
            visible: !root.settingsOpen
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: Style.space(560)

            TextField {
              id: searchField
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              // Borderless, like the launcher and reminder prompts.
              height: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
              leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
              background: null
              placeholderText: root.tr("Issue key or number") + "…"
              placeholderTextColor: Util.alpha(root.bar.foreground, 0.58)
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.heading
              // No caret, like the launcher: the field always holds the keyboard.
              cursorDelegate: Item {}
              onTextEdited: { root.cursorIndex = -1; root.followKey = "" }
              Keys.onUpPressed: root.moveCursor(-1)
              Keys.onDownPressed: root.moveCursor(1)
              Keys.onReturnPressed: function(event) { root.enter(event) }
              Keys.onEnterPressed: function(event) { root.enter(event) }
              onTextChanged: text.trim() ? searchTimer.restart() : root.search()
              onAccepted: { searchTimer.stop(); root.search() }
            }

            PanelSeparator {
              id: separator
              anchors.top: searchField.bottom
              anchors.topMargin: Style.space(16)
              width: parent.width
              foreground: root.bar.foreground
            }

            // Last status first.
            ListView {
              id: list
              anchors.top: separator.bottom
              anchors.topMargin: Style.space(18)
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              clip: true
              spacing: Style.space(4)
              boundsBehavior: Flickable.StopAtBounds
              model: root.rows

              // A row is a status heading (a click folds or unfolds it) or an issue.
              delegate: Column {
                id: entry
                required property var modelData
                required property int index
                width: ListView.view.width

                Item {
                  visible: !!entry.modelData.group
                  width: parent.width
                  height: groupTitle.implicitHeight + (entry.index === 0 ? Style.space(16) : Style.space(48))

                  MouseArea {
                    id: groupArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) { if (pointerGate.moved(groupArea, mouse)) root.cursorIndex = entry.index }
                    onClicked: root.toggleGroup(entry.modelData.column)
                  }

                  CursorSurface {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(2)
                    height: groupTitle.implicitHeight + Style.space(12)
                    foreground: root.bar.foreground
                    hasCursor: root.cursorIndex === entry.index
                  }

                  PanelSeparator {
                    visible: entry.index > 0
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(18)
                    width: parent.width
                    foreground: root.bar.foreground
                  }

                  Caption {
                    id: groupTitle
                    x: Style.space(10)
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(8)
                    text: (entry.modelData.collapsed ? "󰅂 " : "󰅀 ") + String(entry.modelData.column).toUpperCase() + " · " + entry.modelData.count
                  }
                }

                CursorSurface {
                  id: row
                  visible: !entry.modelData.group
                  readonly property var modelData: entry.modelData.group ? root.blankRow : entry.modelData
                  width: parent.width
                  implicitHeight: Math.max(Style.space(58), rowText.implicitHeight + Style.spacing.rowPaddingX * 2)
                  foreground: root.bar.foreground
                  // The issue open in the card is the selected row (the accent); the
                  // cursor paints the others.
                  current: root.cardKey === modelData.key
                  hasCursor: root.cursorIndex === entry.index && !current

                  Rectangle {
                    visible: row.modelData.flagged
                    anchors.fill: parent
                    radius: row.radius
                    color: root.flagTint
                  }

                  // Mine: a bar in the accent at the left edge.
                  Rectangle {
                    visible: row.modelData.mine && !root.onlyMine
                    x: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: parent.height - Style.space(20)
                    radius: width / 2
                    color: Color.accent
                  }

                  MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) { if (pointerGate.moved(rowArea, mouse)) root.cursorIndex = entry.index }
                    onClicked: root.pick(row.modelData.key)
                  }

                  Text {
                    id: typeIcon
                    x: Style.space(14)
                    width: Style.space(24)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    readonly property string kind: Model.typeKind(row.modelData.typeName)
                    text: root.typeIcons[kind]
                    color: root.typeColors[kind] || root.dim
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.iconLarge

                    HoverHandler { id: typeHover }
                    PanelToolTip {
                      visible: typeHover.hovered
                      text: row.modelData.typeName
                    }
                  }

                  Column {
                    id: rowText
                    x: typeIcon.x + typeIcon.width + Style.space(12)
                    width: parent.width - x - Style.space(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(5)

                    Item {
                      width: parent.width
                      height: rowMeta.implicitHeight

                      Caption {
                        id: rowMeta
                        anchors.left: parent.left
                        anchors.right: rowStatus.left
                        anchors.rightMargin: Style.space(10)
                        elide: Text.ElideRight
                        text: [(row.modelData.flagged ? "󰈻 " : "") + (row.modelData.parent ? row.modelData.parent + " / " : "") + row.modelData.key, row.modelData.priorityName,
                               row.modelData.storyPoints ? row.modelData.storyPoints + " SP" : "",
                               root.onlyMine ? "" : row.modelData.assigneeName].filter(Boolean).join(" · ")
                      }

                      Caption {
                        id: rowStatus
                        anchors.right: parent.right
                        visible: row.modelData.statusName.toUpperCase() !== row.modelData.column.toUpperCase()
                        width: visible ? Math.min(implicitWidth, parent.width * 0.4) : 0
                        elide: Text.ElideRight
                        text: row.modelData.statusName.toUpperCase()
                      }
                    }

                    Text {
                      width: parent.width
                      textFormat: Text.PlainText
                      text: (row.modelData.subtask ? "↳ " : "") + row.modelData.summary
                      color: root.bar.foreground
                      font.family: root.bar.fontFamily
                      font.pixelSize: Style.font.heading
                      wrapMode: Text.Wrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }

            Text {
              visible: root.rows.length === 0
              anchors.centerIn: list
              text: root.problem ? ""
                  : root.query ? (root.searching ? root.tr("Searching…")
                                  : Model.searchKeys(root.query, ["X"], "X").length ? root.tr("Nothing found") : root.tr("A key like ABC-12 or a number"))
                  : root.loading ? root.tr("Loading…") : root.tr("No issues")
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.heading
            }
          }

          PanelSeparator {
            id: divider
            visible: !root.settingsOpen
            anchors.left: listPane.right
            anchors.leftMargin: Style.space(18)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            foreground: root.bar.foreground
          }

          // ---- The picked issue's card on the right. A focus scope: its
          //      activeFocus says a field of the card holds the keys.
          FocusScope {
            id: cardPane
            visible: !root.settingsOpen
            anchors.left: divider.right
            anchors.leftMargin: Style.space(24)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            Card {
              id: cardView
              anchors.fill: parent
              visible: root.cardKey !== ""
              jira: root
            }

            Text {
              visible: root.cardKey === ""
              anchors.centerIn: parent
              text: root.tr("Pick an issue")
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.heading
            }
          }
        }
      }
    }
  }

  component Caption: Text {
    color: root.dim
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
    font.letterSpacing: 1.2
  }
}
