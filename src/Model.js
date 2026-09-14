.pragma library

// Pure shaping for the window: no Qt types in here, so dev/test-model.js can
// run it under node. Everything the list renders goes through these.

// ---- formatting ----------------------------------------------------------

function formatDuration(secs) {
  if (!secs || secs < 0) return ""
  var total = Math.round(secs)
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var seconds = total % 60
  var mm = hours ? (minutes < 10 ? "0" + minutes : String(minutes)) : String(minutes)
  var ss = seconds < 10 ? "0" + seconds : String(seconds)
  return (hours ? hours + ":" : "") + mm + ":" + ss
}

function joinParts(parts, separator) {
  return (parts || []).filter(function (part) { return part }).join(separator || " · ")
}

// ---- rows ----------------------------------------------------------------

function headerRow(title) {
  return {kind: "header", title: title, subtitle: "", art: "", header: true}
}

function playlistRows(result, provider) {
  var lists = (result && result.playlists) || []
  return lists.map(function (entry) {
    return {
      kind: "playlist",
      provider: provider,
      id: entry.id,
      title: entry.name || "",
      subtitle: entry.section || (entry.track_count ? entry.track_count + " episodes" : ""),
      art: "",
      favoritable: entry.favoritable === true,
      count: entry.track_count || 0
    }
  })
}

function trackRows(result) {
  var tracks = (result && result.tracks) || []
  return tracks.map(function (track, index) {
    return {
      kind: track.feed ? "feed" : "track",
      track: track,
      index: index,
      title: track.title || track.station || track.path || "",
      subtitle: track.artist || track.album || "",
      art: track.album_art_url || "",
      duration: track.duration_secs || 0,
      feedPath: track.path
    }
  })
}

function queueRows(result) {
  var rows = trackRows(result)
  for (var i = 0; i < rows.length; i++) rows[i].kind = "queued"
  return rows
}

function historyRows(result) {
  var entries = (result && result.history) || []
  return entries.map(function (entry) {
    var track = entry.track || {}
    var when = String(entry.played_at || "").replace("T", " ").replace("Z", "")
    return {
      kind: "track",
      track: track,
      title: track.title || track.path || "",
      subtitle: joinParts([track.artist || track.station || "", when]),
      art: track.album_art_url || ""
    }
  })
}

// ---- favorites -----------------------------------------------------------

// One stable key per thing worth starring. Playable entries key on their URL,
// provider playlists on provider + id, so the same station starred from Radio
// and from Broadcast is one entry.
function favoriteKey(row) {
  if (!row || row.header) return ""
  if (row.kind === "playlist") return "playlist:" + row.provider + ":" + row.id
  if (row.kind === "feed") return "feed:" + (row.feedPath || "")
  if (row.kind === "show") return "show:ard:" + row.id
  if (row.kind === "category" || row.kind === "country" || row.kind === "country-picker") return ""
  var path = row.url || (row.track && row.track.path) || ""
  return path ? "track:" + path : ""
}

function favoriteEntry(row, track) {
  var key = favoriteKey(row)
  if (!key) return null
  return {
    key: key,
    kind: row.kind,
    title: row.title || "",
    subtitle: row.subtitle || "",
    art: row.art || "",
    provider: row.provider || "",
    id: row.id || "",
    feedPath: row.feedPath || "",
    track: track || row.track || null,
    added_at: new Date().toISOString()
  }
}

function favoriteRows(entries) {
  return (entries || []).map(function (entry) {
    var row = {
      kind: entry.kind,
      title: entry.title,
      subtitle: entry.subtitle,
      art: entry.art,
      provider: entry.provider,
      id: entry.id,
      feedPath: entry.feedPath,
      track: entry.track,
      starred: true
    }
    // A starred ARD or Radio Browser stream comes back as a plain track so it
    // plays without asking its API again.
    if (entry.track && (entry.kind === "live" || entry.kind === "episode")) row.kind = "track"
    return row
  })
}

function isStarred(index, key) {
  return !!(key && index && index[key])
}

function indexFavorites(entries) {
  var index = {}
  for (var i = 0; i < (entries || []).length; i++) {
    if (entries[i] && entries[i].key) index[entries[i].key] = entries[i]
  }
  return index
}

function toggleFavorite(entries, row, track) {
  var list = (entries || []).slice()
  var key = favoriteKey(row)
  if (!key) return {entries: list, starred: false, changed: false}
  for (var i = 0; i < list.length; i++) {
    if (list[i].key === key) {
      list.splice(i, 1)
      return {entries: list, starred: false, changed: true}
    }
  }
  var entry = favoriteEntry(row, track)
  if (!entry) return {entries: list, starred: false, changed: false}
  list.unshift(entry)
  return {entries: list, starred: true, changed: true}
}

// ---- keyboard navigation -------------------------------------------------

function firstSelectable(rows) {
  for (var i = 0; i < (rows || []).length; i++) if (!rows[i].header) return i
  return 0
}

function lastSelectable(rows) {
  for (var i = (rows || []).length - 1; i >= 0; i--) if (!rows[i].header) return i
  return 0
}

// Move by `delta` selectable rows, skipping section headers and stopping at
// the ends rather than wrapping — wrapping in a long list loses the reader.
function nextIndex(rows, current, delta) {
  var list = rows || []
  if (!list.length) return 0
  var step = delta > 0 ? 1 : -1
  var remaining = Math.abs(delta)
  var index = current
  while (remaining > 0) {
    var candidate = index + step
    while (candidate >= 0 && candidate < list.length && list[candidate].header) candidate += step
    if (candidate < 0 || candidate >= list.length) break
    index = candidate
    remaining--
  }
  if (index < 0 || index >= list.length) return current
  if (list[index] && list[index].header) return current
  return index
}

function filterRows(rows, needle) {
  if (!needle) return rows || []
  var lower = String(needle).toLowerCase()
  return (rows || []).filter(function (row) {
    if (row.header) return true
    return (row.title || "").toLowerCase().indexOf(lower) >= 0
        || (row.subtitle || "").toLowerCase().indexOf(lower) >= 0
  })
}

// Contextual hints for the bar above the transport.
function hintsFor(section, canGoBack) {
  var list = [{key: "↑↓", label: "move"}]
  if (section === "queue") list.push({key: "⏎", label: "play"}, {key: "del", label: "remove"})
  else if (section === "settings") list.push({key: "⏎", label: "apply"})
  else list.push({key: "⏎", label: "play"}, {key: "⇧⏎", label: "queue next"}, {key: "f", label: "star"})
  list.push({key: "←→", label: "nav / list"},
            {key: "/", label: "search"},
            {key: "space", label: "play/pause"},
            {key: "esc", label: canGoBack ? "back" : "close"},
            {key: "?", label: "keys"})
  return list
}
