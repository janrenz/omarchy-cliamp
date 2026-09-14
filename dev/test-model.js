#!/usr/bin/env node
// Tests for Model.js — the shaping the window binds to.
//
//   node dev/test-model.js
//
// Model.js is deliberately free of Qt types so it can run here: which rows a
// response becomes, what a star keys on, and where the cursor lands are all
// decisions worth checking without a compositor in the way.

const fs = require("fs")
const path = require("path")

const source = fs
  .readFileSync(path.join(__dirname, "..", "src", "Model.js"), "utf8")
  .replace(".pragma library", "")

const Model = new Function(
  source +
    "; return { formatDuration, joinParts, headerRow, playlistRows, trackRows, queueRows, " +
    "historyRows, favoriteKey, favoriteEntry, favoriteRows, isStarred, indexFavorites, " +
    "toggleFavorite, firstSelectable, lastSelectable, nextIndex, filterRows, hintsFor }"
)()

let passed = 0
const failures = []

function test(name, body) {
  try {
    body()
    passed++
  } catch (error) {
    failures.push(name + ": " + error.message)
  }
}

function equal(actual, expected, what) {
  const a = JSON.stringify(actual)
  const b = JSON.stringify(expected)
  if (a !== b) throw new Error((what || "value") + " was " + a + ", expected " + b)
}

function ok(value, what) {
  if (!value) throw new Error((what || "value") + " was falsy")
}

// ---- formatting ----------------------------------------------------------

test("durations read as a player writes them", () => {
  equal(Model.formatDuration(0), "", "nothing for an unknown length")
  equal(Model.formatDuration(59), "0:59")
  equal(Model.formatDuration(61), "1:01")
  equal(Model.formatDuration(3256), "54:16")
  equal(Model.formatDuration(3700), "1:01:40")
})

test("joinParts drops the empty halves", () => {
  equal(Model.joinParts(["ARD", ""]), "ARD")
  equal(Model.joinParts(["", ""]), "")
  equal(Model.joinParts(["a", "b"], " — "), "a — b")
})

// ---- rows ----------------------------------------------------------------

test("a provider catalogue becomes playlist rows", () => {
  const rows = Model.playlistRows({
    playlists: [
      {id: "l:1", name: "SomaFM Beat Blender", provider: "radio"},
      {id: "c:feed", name: "Weltspiegel", section: "Top Shows (DE)", track_count: 12, favoritable: true}
    ]
  }, "radio")
  equal(rows.length, 2)
  equal(rows[0].kind, "playlist")
  equal(rows[0].title, "SomaFM Beat Blender")
  equal(rows[1].subtitle, "Top Shows (DE)", "the section wins over the count")
  ok(rows[1].favoritable, "favoritable carries through")
  ok(!rows[0].favoritable, "and is not invented")
})

test("a feed track is a feed row, a plain one is a track row", () => {
  const rows = Model.trackRows({
    tracks: [
      {title: "ARD Radiofeature", path: "https://example.org/feed.xml", feed: true, stream: true},
      {title: "Nach 9/11", artist: "ARD Radiofeature", path: "https://example.org/a.mp3", duration_secs: 3256}
    ]
  })
  equal(rows[0].kind, "feed")
  equal(rows[0].feedPath, "https://example.org/feed.xml")
  equal(rows[1].kind, "track")
  equal(rows[1].duration, 3256)
  equal(rows[1].index, 1, "the queue index is the position in the answer")
})

test("queue rows keep their index so queue.play can name one", () => {
  const rows = Model.queueRows({tracks: [{title: "a", path: "a"}, {title: "b", path: "b"}]})
  equal(rows.map(r => r.kind), ["queued", "queued"])
  equal(rows[1].index, 1)
})

test("history unwraps the played_at envelope", () => {
  const rows = Model.historyRows({
    history: [
      {track: {title: "SomaFM Indie Pop Rocks!", path: "https://example.org/s"}, played_at: "2026-09-14T15:00:49Z"}
    ]
  })
  equal(rows[0].title, "SomaFM Indie Pop Rocks!")
  equal(rows[0].subtitle, "2026-09-14 15:00:49")
  ok(rows[0].track, "the track survives, so the row can be played again")
})

test("a row with nothing playable still renders", () => {
  const rows = Model.trackRows({tracks: [{path: "https://example.org/x"}]})
  equal(rows[0].title, "https://example.org/x", "the path is the last resort title")
})

// ---- favorites -----------------------------------------------------------

test("a star keys on the thing, not on where it was found", () => {
  const fromRadio = {kind: "track", track: {path: "https://ice6.somafm.com/indiepop-128-mp3"}}
  const fromBroadcast = {kind: "live", url: "https://ice6.somafm.com/indiepop-128-mp3", votes: 3}
  equal(Model.favoriteKey(fromRadio), Model.favoriteKey(fromBroadcast), "one station, one key")
})

test("rows with nothing to star have no key", () => {
  equal(Model.favoriteKey({kind: "category", id: "42"}), "")
  equal(Model.favoriteKey({kind: "country", id: "DE"}), "")
  equal(Model.favoriteKey({kind: "header", header: true}), "")
})

test("toggling adds once and removes once", () => {
  const row = {kind: "live", title: "1LIVE", url: "https://example.org/1live", votes: 9}
  const added = Model.toggleFavorite([], row, {title: "1LIVE", path: "https://example.org/1live"})
  ok(added.starred, "first toggle stars")
  equal(added.entries.length, 1)
  ok(added.entries[0].track, "the playable track is stored, so playback needs no second lookup")

  const removed = Model.toggleFavorite(added.entries, row)
  ok(!removed.starred, "second toggle unstars")
  equal(removed.entries.length, 0)
})

test("toggling an unstarrable row changes nothing", () => {
  const result = Model.toggleFavorite([], {kind: "category", id: "1"})
  ok(!result.changed)
  equal(result.entries.length, 0)
})

test("starred streams come back as plain tracks", () => {
  const entries = [
    {key: "track:x", kind: "live", title: "1LIVE", track: {path: "x"}},
    {key: "playlist:podcast:c:feed", kind: "playlist", title: "Weltspiegel", provider: "podcast", id: "c:feed"}
  ]
  const rows = Model.favoriteRows(entries)
  equal(rows[0].kind, "track", "a live stream plays without asking its API again")
  equal(rows[1].kind, "playlist", "a playlist still opens as a playlist")
  ok(rows.every(row => row.starred), "everything in here is starred by definition")
})

test("the index answers isStarred", () => {
  const index = Model.indexFavorites([{key: "track:x"}])
  ok(Model.isStarred(index, "track:x"))
  ok(!Model.isStarred(index, "track:y"))
  ok(!Model.isStarred(index, ""), "an unstarrable row is never starred")
})

// ---- keyboard navigation -------------------------------------------------

const navRows = [
  {title: "Top stations", header: true},
  {title: "MANGORADIO"},
  {title: "1LIVE"},
  {title: "ARD live", header: true},
  {title: "SWR3"}
]

test("the cursor never lands on a section header", () => {
  equal(Model.firstSelectable(navRows), 1)
  equal(Model.nextIndex(navRows, 2, 1), 4, "stepping past a header skips it")
  equal(Model.nextIndex(navRows, 4, -1), 2, "and skips it going back")
})

test("the cursor stops at the ends instead of wrapping", () => {
  equal(Model.nextIndex(navRows, 4, 1), 4, "already last")
  equal(Model.nextIndex(navRows, 1, -1), 1, "already first")
  equal(Model.nextIndex(navRows, 1, 8), 4, "a page jump lands on the last row")
  equal(Model.lastSelectable(navRows), 4)
})

test("an empty list has nowhere to go", () => {
  equal(Model.nextIndex([], 0, 1), 0)
  equal(Model.firstSelectable([]), 0)
})

test("filtering keeps the headers that frame the results", () => {
  const rows = Model.filterRows(navRows, "swr")
  equal(rows.map(row => row.title), ["Top stations", "ARD live", "SWR3"])
  equal(Model.filterRows(navRows, "").length, navRows.length, "no filter, no filtering")
})

test("filtering reads the subtitle too", () => {
  const rows = Model.filterRows([{title: "1LIVE", subtitle: "Germany · rock"}], "germany")
  equal(rows.length, 1)
})

// ---- hints ---------------------------------------------------------------

test("hints say what the section can do", () => {
  const queue = Model.hintsFor("queue", false).map(hint => hint.label)
  ok(queue.indexOf("remove") >= 0, "the queue can remove")
  ok(queue.indexOf("star") < 0, "and has nothing to star")

  const radio = Model.hintsFor("radio", false).map(hint => hint.label)
  ok(radio.indexOf("star") >= 0)
  ok(radio.indexOf("queue next") >= 0)
})

test("escape says what it will do", () => {
  equal(Model.hintsFor("radio", true).filter(h => h.key === "esc")[0].label, "back")
  equal(Model.hintsFor("radio", false).filter(h => h.key === "esc")[0].label, "close")
})

// ---- report --------------------------------------------------------------

if (failures.length) {
  console.error(failures.map(line => "FAIL " + line).join("\n"))
  console.error("\n" + passed + " passed, " + failures.length + " failed")
  process.exit(1)
}
console.log(passed + " passed")
