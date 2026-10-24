.pragma library

// Jira Server/Data Center, REST api/2 and agile/1.0.

function normalizeUrl(url) {
  var u = String(url || "").trim().replace(/\/+$/, "")
  return /^https?:\/\/[^\s/]+/.test(u) ? u : ""
}

function browseUrl(base, key) {
  return base + "/browse/" + key
}

// The issue a link points at on this Jira (…/browse/KEY), or "" for any other link.
function linkedIssue(url, base) {
  var m = /^(https?:\/\/.+)\/browse\/([A-Za-z][A-Za-z0-9_]*-\d+)\/?(?:[?#].*)?$/.exec(String(url || ""))
  return m && base && normalizeUrl(m[1]) === base ? m[2].toUpperCase() : ""
}

// What the search field holds → issue keys to look up: a key as typed (also
// inside a pasted link), or a bare number in every project (the current one
// alone while the project list isn't known).
function searchKeys(text, projects, current) {
  var t = String(text || "").trim().toUpperCase()
  var m = t.match(/[A-Z][A-Z0-9_]*-\d+/)
  if (m) return [m[0]]
  if (!/^\d+$/.test(t)) return []
  return (projects && projects.length ? projects : [current]).map(function(p) { return p + "-" + t })
}

// Search hits as list rows (no status heading), the current project first.
function foundRows(issues, ids, me, project) {
  var own = function(r) { return r.key.indexOf(project + "-") === 0 ? 0 : 1 }
  return (issues || []).map(function(issue) {
    var r = card(issue, ids, me)
    r.column = ""
    return r
  }).sort(function(a, b) { return own(a) - own(b) || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0) })
}

function boardUrl(base, boardId) {
  return base + "/secure/RapidBoard.jspa?rapidView=" + boardId
}

// Story points and the epic link are custom fields with ids that differ per server.
function fieldIds(fields) {
  var ids = { storyPoints: "", epic: "", flagged: "" }
  ;(fields || []).forEach(function(f) {
    var name = String(f.name || "").toLowerCase()
    var custom = f.schema && f.schema.custom || ""
    if (!ids.storyPoints && (name === "story points" || name === "story point estimate")) ids.storyPoints = f.id
    if (!ids.epic && (custom === "com.pyxis.greenhopper.jira:gh-epic-link" || name === "epic link")) ids.epic = f.id
    if (!ids.flagged && name === "flagged") ids.flagged = f.id
  })
  return ids
}

function requestFields(ids) {
  return ["summary", "status", "priority", "issuetype", "labels", "reporter", "assignee", "description", "subtasks", "parent", "attachment"]
    .concat([ids.storyPoints, ids.epic, ids.flagged].filter(Boolean)).join(",")
}

function person(p) {
  return p ? (p.displayName || p.name || "") : ""
}

function card(issue, ids, me) {
  var f = issue.fields || {}
  var points = ids.storyPoints ? f[ids.storyPoints] : null
  return {
    key: issue.key,
    summary: f.summary || "",
    statusId: f.status ? String(f.status.id) : "",
    statusName: f.status ? f.status.name : "",
    priorityId: f.priority ? String(f.priority.id) : "",
    priorityName: f.priority ? f.priority.name : "",
    typeId: f.issuetype ? String(f.issuetype.id) : "",
    typeName: f.issuetype ? f.issuetype.name : "",
    subtask: !!(f.issuetype && f.issuetype.subtask),
    labels: f.labels || [],
    storyPoints: points === null || points === undefined ? "" : String(points),
    epic: ids.epic && f[ids.epic] ? String(f[ids.epic]) : "",
    reporterName: person(f.reporter),
    assigneeName: person(f.assignee),
    mine: !!(f.assignee && me && f.assignee.name === me.name),
    flagged: !!(ids.flagged && f[ids.flagged] && f[ids.flagged].length),
    description: f.description || "",
    // Jira's own rendering of the wiki markup (expand=renderedFields), when asked for.
    descriptionHtml: issue.renderedFields && issue.renderedFields.description || "",
    parent: f.parent ? f.parent.key : "",
    attachments: (f.attachment || []).map(function(a) {
      return { id: String(a.id), name: a.filename, size: a.size || 0, url: a.content }
    }),
    subtasks: (f.subtasks || []).map(function(s) {
      var sf = s.fields || {}
      return { key: s.key, summary: sf.summary || "", status: sf.status ? sf.status.name : "" }
    })
  }
}

// Board columns in the board's order, issues in rank order within each.
function board(config, issues, ids, me) {
  var cols = (config && config.columnConfig && config.columnConfig.columns || []).map(function(c) {
    return { name: c.name, statuses: (c.statuses || []).map(function(s) { return String(s.id) }), issues: [] }
  })
  ;(issues || []).forEach(function(issue) {
    var c = card(issue, ids, me)
    for (var i = 0; i < cols.length; i++)
      if (cols[i].statuses.indexOf(c.statusId) >= 0) { cols[i].issues.push(c); break }
  })
  return cols.map(function(c) { return { name: c.name, issues: c.issues } })
}

// Scrum: the running sprint. Kanban: open work plus two weeks of done.
// ponytail: fixed window, a setting if two weeks turns out wrong.
function boardJql(type) {
  return type === "scrum" ? "sprint in openSprints()" : "resolution is EMPTY OR resolved >= -14d"
}

// The list as rows: the board's last status first, each status a heading
// row (with its count and whether it's collapsed) followed by its issues in
// rank order. A collapsed status is its heading alone; a status the filters
// leave empty drops out. Issue rows are copies of the cards plus `column`.
function listRows(groups, hideSubtasks, onlyMine, collapsed) {
  var shut = collapsed || [], out = []
  ;(groups || []).slice().reverse().forEach(function(g) {
    var issues = g.issues.filter(function(i) { return !(hideSubtasks && i.subtask || onlyMine && !i.mine) })
    if (!issues.length) return
    var isShut = shut.indexOf(g.name) >= 0
    out.push({ group: true, column: g.name, count: issues.length, collapsed: isShut })
    if (isShut) return
    issues.forEach(function(i) {
      var item = { column: g.name }
      for (var k in i) item[k] = i[k]
      out.push(item)
    })
  })
  return out
}

// Jira labels have no spaces, so spaces and commas both separate.
function parseLabels(text) {
  var seen = {}
  return String(text || "").split(/[\s,]+/).filter(function(l) {
    if (!l || seen[l]) return false
    return (seen[l] = true)
  })
}

// Empty clears the field; anything else must be a number (a comma is a decimal point).
function parsePoints(text) {
  var t = String(text || "").trim().replace(",", ".")
  return t === "" ? null : (/^\d+(\.\d+)?$/.test(t) ? Number(t) : NaN)
}

function errorText(body, stderr) {
  try {
    var j = JSON.parse(body)
    var parts = (j.errorMessages || []).slice()
    for (var k in j.errors || {}) parts.push(k + ": " + j.errors[k])
    if (parts.length) return parts.join("; ")
  } catch (e) {}
  var err = String(stderr || "").trim()
  // 429 is either the per-user rate limit, or a token Jira didn't recognise:
  // such a request isn't refused but goes on as Anonymous, which is blocked.
  if (/error: 429\b/.test(err))
    return "429: rate limit, or the token wasn't accepted — refresh in a minute"
  return err || "unknown error"
}

function escapeHtml(t) {
  return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// The description as rich text with clickable links: Jira's [text|url],
// [text|url|smart-link] and [url], and bare http(s) URLs. Everything else
// is escaped, so the text can't inject markup; only http(s) becomes a link.
function linkify(text, color) {
  var re = /\[([^\[\]|]*)\|(https?:\/\/[^\]|\s]+)(?:\|[^\]]*)?\]|\[(https?:\/\/[^\]\s]+)\]|https?:\/\/[^\s<>"\[\]]+/g
  var out = "", last = 0, m
  function link(url, label) {
    return '<a href="' + escapeHtml(url) + '" style="color:' + color + '">' + escapeHtml(label) + "</a>"
  }
  while ((m = re.exec(String(text || "")))) {
    out += escapeHtml(text.slice(last, m.index))
    if (m[2]) out += link(m[2], m[1] || m[2])
    else if (m[3]) out += link(m[3], m[3])
    else {
      // Sentence punctuation right after a bare URL stays text.
      var url = m[0].replace(/[.,;:!?)]+$/, "")
      out += link(url, url) + escapeHtml(m[0].slice(url.length))
    }
    last = re.lastIndex
  }
  return (out + escapeHtml(String(text || "").slice(last))).replace(/\r?\n/g, "<br>")
}

// The list shows the issue type as an icon: bugs, stories, and tech debt /
// architecture get their own, everything else a plain one.
function typeKind(name) {
  var n = String(name || "").toLowerCase()
  if (/ошибк|bug|дефект/.test(n)) return "bug"
  if (/story|истори/.test(n)) return "story"
  if (/техдолг|технический долг|tech.?debt|архитектур|architecture/.test(n)) return "debt"
  return "other"
}

// Jira's rendered description for a rich-text view: server-relative links
// made absolute and coloured, images dropped (they'd need the token).
function richDescription(html, base, color) {
  var origin = (String(base).match(/^https?:\/\/[^\/]+/) || [""])[0]
  return String(html || "")
    .replace(/<img\b[^>]*>/gi, "")
    .replace(/<a\b([^>]*?)href="\//gi, '<a$1href="' + origin + "/")
    .replace(/<a\b/gi, '<a style="color:' + color + '"')
}

// tr translates the unit (I18n), point is the locale's decimal separator.
function sizeText(bytes, tr, point) {
  var units = ["B", "KB", "MB", "GB"], n = Number(bytes) || 0, u = 0
  while (n >= 1024 && u < units.length - 1) { n /= 1024; u++ }
  return String(u ? Number(n.toFixed(1)) : n).replace(".", point || ".") + " " + (tr ? tr(units[u]) : units[u])
}

// The list cached on disk: what an open of the panel does with it.
// "none" — no usable cache (another Jira or project, an old format, a week
// old); "refs" — reread everything in the background (the reference data —
// me, fields, board — is a day old); "issues" — reread the list alone
// (over two minutes old); "fresh" — nothing.
var CACHE_VERSION = 1
function cachePlan(cache, url, project, now) {
  var min = 60e3
  if (!cache || cache.version !== CACHE_VERSION || cache.url !== url || cache.project !== project) return "none"
  if (now - cache.savedAt > 7 * 24 * 60 * min) return "none"
  if (now - cache.refsAt > 24 * 60 * min) return "refs"
  return now - cache.savedAt > 2 * min ? "issues" : "fresh"
}

// An issue's comments (expand=renderedBody), newest first, as rich text.
// Jira's "+0300" offset gets the colon a JS date needs.
function comments(d, base, color) {
  return (d && d.comments || []).map(function(c) {
    return {
      id: String(c.id),
      author: person(c.author),
      time: new Date(String(c.created || "").replace(/([+-]\d\d)(\d\d)$/, "$1:$2")),
      html: c.renderedBody ? richDescription(c.renderedBody, base, color) : linkify(c.body, color)
    }
  }).reverse()
}
