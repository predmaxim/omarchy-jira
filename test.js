// node test.js
const fs = require("fs")
const src = fs.readFileSync(__dirname + "/Model.js", "utf8").replace(".pragma library", "")
const M = new Function(src + "; return { normalizeUrl, browseUrl, linkedIssue, boardUrl, searchKeys, foundRows, fieldIds, requestFields, card, board, parseLabels, parsePoints, errorText, boardJql, listRows, linkify, typeKind, richDescription, sizeText, cachePlan, comments }")()
const assert = require("assert")

const cm = M.comments({ comments: [
  { id: 1, author: { displayName: "Ann" }, created: "2026-10-01T09:05:00.000+0300", body: "a", renderedBody: '<p>a <a href="/jira/x">x</a></p>' },
  { id: 2, author: { name: "bob" }, created: "2026-10-01T10:00:00.000+0300", body: "b" }
] }, "https://j.ru/jira", "red")
assert.deepStrictEqual(cm.map(c => c.author), ["bob", "Ann"])
assert.strictEqual(cm[1].time.toISOString(), "2026-10-01T06:05:00.000Z")
assert.ok(cm[1].html.indexOf('href="https://j.ru/jira/x"') >= 0)
assert.strictEqual(cm[0].html, "b")
assert.deepStrictEqual(M.comments(null, "", ""), [])

const H = 3600e3, now = 100 * 24 * H
const cached = (age, refsAge) => ({ version: 1, url: "u", project: "P", savedAt: now - age, refsAt: now - refsAge })
assert.strictEqual(M.cachePlan(null, "u", "P", now), "none")
assert.strictEqual(M.cachePlan(cached(0, 0), "u", "OTHER", now), "none")
assert.strictEqual(M.cachePlan(Object.assign(cached(0, 0), { version: 0 }), "u", "P", now), "none")
assert.strictEqual(M.cachePlan(cached(8 * 24 * H, 0), "u", "P", now), "none")
assert.strictEqual(M.cachePlan(cached(60e3, 60e3), "u", "P", now), "fresh")
assert.strictEqual(M.cachePlan(cached(3 * 60e3, H), "u", "P", now), "issues")
assert.strictEqual(M.cachePlan(cached(60e3, 25 * H), "u", "P", now), "refs")

assert.strictEqual(M.normalizeUrl(" https://jira.x.ru/jira/// "), "https://jira.x.ru/jira")
assert.strictEqual(M.normalizeUrl("jira.x.ru"), "")
assert.strictEqual(M.browseUrl("https://j.ru", "DEMO-1"), "https://j.ru/browse/DEMO-1")
// Links to an issue of this Jira open in the panel; anything else goes to the browser.
assert.strictEqual(M.linkedIssue("https://j.ru/jira/browse/DEMO-12", "https://j.ru/jira"), "DEMO-12")
assert.strictEqual(M.linkedIssue("https://j.ru/jira/browse/demo-12/?focusedCommentId=5#c5", "https://j.ru/jira"), "DEMO-12")
assert.strictEqual(M.linkedIssue("https://j.ru/other/browse/DEMO-12", "https://j.ru/jira"), "")
assert.strictEqual(M.linkedIssue("https://other.ru/jira/browse/DEMO-12", "https://j.ru/jira"), "")
assert.strictEqual(M.linkedIssue("https://j.ru/jira/secure/RapidBoard.jspa?rapidView=42", "https://j.ru/jira"), "")
assert.strictEqual(M.linkedIssue("https://j.ru/jira/browse/DEMO-12", ""), "")
assert.strictEqual(M.boardUrl("https://j.ru/jira", 42), "https://j.ru/jira/secure/RapidBoard.jspa?rapidView=42")

assert.deepStrictEqual(M.searchKeys(" abc-12 ", ["DEMO"], "DEMO"), ["ABC-12"])
assert.deepStrictEqual(M.searchKeys("https://j.ru/browse/TEST-7?x=1", [], "DEMO"), ["TEST-7"])
assert.deepStrictEqual(M.searchKeys("123", ["DEMO", "TEST"], "DEMO"), ["DEMO-123", "TEST-123"])
assert.deepStrictEqual(M.searchKeys("123", [], "DEMO"), ["DEMO-123"])
assert.deepStrictEqual(M.searchKeys("12a", ["DEMO"], "DEMO"), [])
assert.deepStrictEqual(M.searchKeys("", ["DEMO"], "DEMO"), [])
assert.deepStrictEqual(M.foundRows([{ key: "A-5", fields: {} }, { key: "DEMO-5", fields: {} }, { key: "B-5", fields: {} }], {}, null, "DEMO")
  .map(r => r.key + "|" + r.column), ["DEMO-5|", "A-5|", "B-5|"])

const ids = M.fieldIds([
  { id: "summary", name: "Summary" },
  { id: "customfield_10002", name: "Story Points" },
  { id: "customfield_10008", name: "Epic Link", schema: { custom: "com.pyxis.greenhopper.jira:gh-epic-link" } }
])
assert.deepStrictEqual(ids, { storyPoints: "customfield_10002", epic: "customfield_10008", flagged: "" })
assert.deepStrictEqual(M.fieldIds([{ id: "cf_1", name: "Story point estimate" }, { id: "customfield_10021", name: "Flagged" }]),
  { storyPoints: "cf_1", epic: "", flagged: "customfield_10021" })
assert.ok(M.requestFields(ids).split(",").indexOf("customfield_10002") >= 0)
assert.strictEqual(M.requestFields({ storyPoints: "", epic: "", flagged: "" }).indexOf(",,"), -1)
assert.ok(M.requestFields({ storyPoints: "", epic: "", flagged: "cf_f" }).split(",").indexOf("cf_f") >= 0)

// A flag is the Flagged checkbox field holding any value ("Impediment").
const fids = { storyPoints: "", epic: "", flagged: "cf_f" }
assert.strictEqual(M.card({ key: "E-1", fields: { cf_f: [{ value: "Impediment" }] } }, fids, null).flagged, true)
assert.strictEqual(M.card({ key: "E-1", fields: { cf_f: null } }, fids, null).flagged, false)
assert.strictEqual(M.card({ key: "E-1", fields: {} }, ids, null).flagged, false)

const me = { name: "alice" }
const issue = (key, statusId, assignee, extra) => ({
  key,
  fields: Object.assign({
    summary: "Задача " + key,
    status: { id: statusId, name: "S" + statusId },
    priority: { id: "3", name: "Major" },
    issuetype: { id: "10001", name: "Story", subtask: false },
    labels: ["front"],
    reporter: { name: "boss", displayName: "Начальник" },
    assignee: assignee ? { name: assignee, displayName: assignee.toUpperCase() } : null,
    customfield_10002: 3,
    customfield_10008: "DEMO-100",
    description: null,
    subtasks: [{ key: "DEMO-9", fields: { summary: "под", status: { name: "Open" } } }]
  }, extra)
})

const c = M.card(issue("DEMO-1", "1", "alice"), ids, me)
assert.strictEqual(c.mine, true)
assert.strictEqual(c.storyPoints, "3")
assert.strictEqual(c.epic, "DEMO-100")
assert.strictEqual(c.description, "")
assert.deepStrictEqual(c.labels, ["front"])
assert.deepStrictEqual(c.subtasks, [{ key: "DEMO-9", summary: "под", status: "Open" }])
assert.strictEqual(c.assigneeName, "ALICE")
const nobody = M.card(issue("DEMO-2", "1", null, { priority: null, customfield_10002: null }), ids, me)
assert.strictEqual(nobody.mine, false)
assert.strictEqual(nobody.assigneeName, "")
assert.strictEqual(nobody.storyPoints, "")
assert.strictEqual(nobody.priorityId, "")

// Columns keep board order; an issue whose status is on no column is dropped, as on the board.
const cols = M.board(
  { columnConfig: { columns: [
    { name: "К работе", statuses: [{ id: "1" }] },
    { name: "В работе", statuses: [{ id: "3" }, { id: "4" }] },
    { name: "Пусто", statuses: [] }
  ] } },
  [issue("DEMO-1", "4", "x"), issue("DEMO-2", "1", "alice"), issue("DEMO-3", "1", null), issue("DEMO-4", "77", null)],
  ids, me)
assert.deepStrictEqual(cols.map(c => c.name), ["К работе", "В работе", "Пусто"])
assert.deepStrictEqual(cols.map(c => c.issues.map(i => i.key)), [["DEMO-2", "DEMO-3"], ["DEMO-1"], []])
assert.strictEqual(cols[0].issues[0].mine, true)

assert.deepStrictEqual(M.parseLabels(" a, b  c,,a "), ["a", "b", "c"])
assert.deepStrictEqual(M.parseLabels(""), [])
assert.strictEqual(M.parsePoints(""), null)
assert.strictEqual(M.parsePoints("2,5"), 2.5)
assert.ok(isNaN(M.parsePoints("abc")))

assert.strictEqual(M.errorText('{"errorMessages":["Нет прав"],"errors":{"summary":"пусто"}}', ""), "Нет прав; summary: пусто")
assert.strictEqual(M.errorText("<html>502</html>", "curl: (22) error 502"), "curl: (22) error 502")
assert.strictEqual(M.errorText("", ""), "unknown error")
// 429 without Jira's JSON: the token was not accepted and the request went in as Anonymous, which this server blocks.
assert.ok(M.errorText("<html>429</html>", "curl: (22) The requested URL returned error: 429").indexOf("token wasn't accepted") >= 0)

assert.strictEqual(M.boardJql("scrum"), "sprint in openSprints()")
assert.strictEqual(M.boardJql("kanban"), "resolution is EMPTY OR resolved >= -14d")

// The list: last status first (rank kept inside a status), a heading row per status
// with its count; a collapsed status is its heading alone; subtasks and others'
// issues hidden on request; a status left empty is gone.
const groups = [
  { name: "A", issues: [{ key: "E-1", subtask: false, mine: true }, { key: "E-2", subtask: true, mine: true }] },
  { name: "B", issues: [] },
  { name: "C", issues: [{ key: "E-3", subtask: true, mine: false }, { key: "E-4", subtask: false, mine: false }] }
]
const show = rows => rows.map(r => r.group ? (r.collapsed ? "+" : "-") + r.column + r.count : r.key)
assert.deepStrictEqual(show(M.listRows(groups, false, false, [])), ["-C2", "E-3", "E-4", "-A2", "E-1", "E-2"])
assert.deepStrictEqual(show(M.listRows(groups, true, false, [])), ["-C1", "E-4", "-A1", "E-1"])
assert.deepStrictEqual(show(M.listRows(groups, false, true, [])), ["-A2", "E-1", "E-2"])
assert.deepStrictEqual(show(M.listRows(groups, true, true, [])), ["-A1", "E-1"])
assert.deepStrictEqual(show(M.listRows(groups, false, false, ["C"])), ["+C2", "-A2", "E-1", "E-2"])
assert.deepStrictEqual(show(M.listRows(groups, false, false, null)), ["-C2", "E-3", "E-4", "-A2", "E-1", "E-2"])
// Issue rows know their column; the cards themselves are not changed.
assert.deepStrictEqual(M.listRows(groups, false, false, []).filter(r => !r.group).map(r => r.column), ["C", "C", "A", "A"])
assert.strictEqual(groups[0].issues[0].column, undefined)
// Description links: bare URLs and Jira's [text|url] / [url]; everything else escaped.
assert.strictEqual(M.linkify("см. https://a.ru/x?a=1&b=2.", "#fff"),
  'см. <a href="https://a.ru/x?a=1&amp;b=2" style="color:#fff">https://a.ru/x?a=1&amp;b=2</a>.')
assert.strictEqual(M.linkify("[Макет|https://figma.com/f/1] и [https://b.ru]", "#fff"),
  '<a href="https://figma.com/f/1" style="color:#fff">Макет</a> и <a href="https://b.ru" style="color:#fff">https://b.ru</a>')
assert.strictEqual(M.linkify("[Док|https://c.ru/d|smart-link]", "#fff"), '<a href="https://c.ru/d" style="color:#fff">Док</a>')
assert.strictEqual(M.linkify("<b>x</b>\nстрока (http://h.ru/p)", "#fff"),
  '&lt;b&gt;x&lt;/b&gt;<br>строка (<a href="http://h.ru/p" style="color:#fff">http://h.ru/p</a>)')
assert.strictEqual(M.linkify("[не ссылка] javascript:alert(1)", "#fff"), "[не ссылка] javascript:alert(1)")
// Issue type → the icon's kind, by name (types are named per server, often in Russian).
assert.deepStrictEqual(["Bug", "Дефект", "Story", "История", "Architecture", "Технический долг", "Tech debt", "Task", "Sub-task", ""].map(M.typeKind),
  ["bug", "bug", "story", "story", "debt", "debt", "debt", "other", "other", "other"])
// Jira's rendered description: kept as HTML, links absolute and coloured, images out (they need the token).
assert.strictEqual(M.card({ key: "E-1", fields: { description: "*a*" }, renderedFields: { description: "<p><b>a</b></p>" } }, ids, null).descriptionHtml, "<p><b>a</b></p>")
assert.strictEqual(M.card({ key: "E-1", fields: {} }, ids, null).descriptionHtml, "")
assert.strictEqual(M.richDescription('<p>см. <a href="/jira/browse/E-2" class="issue-link">E-2</a>, <a href="https://x.ru">x</a> <img src="/jira/images/icons/emoticons/smile.png" alt="(smile)"></p>', "https://j.ru/jira", "#0f0"),
  '<p>см. <a style="color:#0f0" href="https://j.ru/jira/browse/E-2" class="issue-link">E-2</a>, <a style="color:#0f0" href="https://x.ru">x</a> </p>')
// Attachments: name, size, download address.
const att = M.card({ key: "E-1", fields: { attachment: [{ id: "77", filename: "ТЗ.pdf", size: 1536000, mimeType: "application/pdf", content: "https://j.ru/jira/secure/attachment/77/%D0%A2%D0%97.pdf" }] } }, ids, null).attachments
assert.deepStrictEqual(att, [{ id: "77", name: "ТЗ.pdf", size: 1536000, url: "https://j.ru/jira/secure/attachment/77/%D0%A2%D0%97.pdf" }])
assert.deepStrictEqual(M.card({ key: "E-1", fields: {} }, ids, null).attachments, [])
assert.ok(M.requestFields(ids).split(",").indexOf("attachment") >= 0)
assert.deepStrictEqual([0, 900, 1536, 1536000, 3 * 1024 * 1024 * 1024].map(b => M.sizeText(b)), ["0 B", "900 B", "1.5 KB", "1.5 MB", "3 GB"])
// Interface language: LC_ALL, then LC_MESSAGES, then LANG; a language without a table is English.
const isrc = fs.readFileSync(__dirname + "/I18n.js", "utf8").replace(".pragma library", "")
const I = new Function(isrc + "; return { TABLES, textLanguage, translator }")()
const envOf = o => n => o[n]
assert.strictEqual(I.textLanguage(envOf({ LANG: "en_US.UTF-8" })), "en")
assert.strictEqual(I.textLanguage(envOf({ LANG: "en_US.UTF-8", LC_MESSAGES: "ru_RU.UTF-8" })), "ru")
assert.strictEqual(I.textLanguage(envOf({ LC_ALL: "de_DE.UTF-8", LC_MESSAGES: "ru_RU.UTF-8" })), "en")
assert.strictEqual(I.textLanguage(envOf({})), "en")
const ru = I.translator("ru"), en = I.translator("en")
assert.strictEqual(ru("Copied: %1", ru("key")), "Скопировано: номер")
assert.strictEqual(en("Copied: %1", en("key")), "Copied: key")
assert.strictEqual(M.sizeText(1536, ru, ","), "1,5 КБ")
// Every tr("…") in the QML, and every message the script can show, has a Russian line.
const keys = ["Panel.qml", "Card.qml"].flatMap(f => [...fs.readFileSync(__dirname + "/" + f, "utf8").matchAll(/\btr\("((?:[^"\\]|\\.)*)"/g)].map(m => m[1]))
const shown = [...fs.readFileSync(__dirname + "/scripts/jira", "utf8").matchAll(/echo "([^"$]*)" >&2/g)].map(m => m[1])
assert.ok(keys.length > 30, "found " + keys.length + " tr() calls")
const missing = keys.concat(shown, ["B", "KB", "MB", "GB", "unknown error"]).filter(k => !(k in I.TABLES.ru))
assert.deepStrictEqual(missing, [])
console.log("ok")
