#!/usr/bin/env node
// Tests for the two languages — Texte.js.
//
//   node dev/test-texte.js
//
// The interface is English in the source and German through a lookup. Two ways
// that breaks silently, and both are checked here:
//
//   a string that is shown but has no German entry — it would quietly stay
//   English in a German window, and nobody notices one line among a hundred;
//
//   a key that is looked up at runtime rather than written in the QML — the
//   hint bar under the list takes its labels from Model.js, and the card in the
//   bar from its own model, so grepping for t("…") cannot see them. The test
//   asks Model.js for every hint it can produce and checks those too.
//
// Not checked: that the German is good. That needs a reader.

const fs = require("fs")
const path = require("path")

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

function ok(value, what) {
  if (!value) throw new Error(what || "expected something truthy")
}

function equal(actual, expected, what) {
  if (actual !== expected) {
    throw new Error((what || "value") + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual))
  }
}

const src = (name) => fs.readFileSync(path.join(__dirname, "..", "src", name), "utf8")
const laden = (name) => {
  const modul = {}
  new Function("exports", src(name).replace(".pragma library", "") + "\nexports.t = typeof t === 'function' ? t : undefined;\nexports.schluessel = typeof schluessel === 'function' ? schluessel : undefined;\nexports.hintsFor = typeof hintsFor === 'function' ? hintsFor : undefined;")(modul)
  return modul
}

const Texte = laden("Texte.js")
const Model = laden("Model.js")
const schluessel = new Set(Texte.schluessel())

// QML unescapes \uXXXX before the string ever reaches t(), so the dictionary
// holds the character and the source holds the escape. Compare like for like.
function entschluesselt(s) {
  return s.replace(/\\u([0-9a-fA-F]{4})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
          .replace(/\\"/g, '"')
}

function gezeigteTexte() {
  const found = new Set()
  for (const datei of ["Library.qml", "BarWidget.qml"]) {
    const s = src(datei)
    const re = /\bt\("((?:[^"\\]|\\.)*)"\)/g
    let m
    while ((m = re.exec(s)) !== null) found.add(entschluesselt(m[1]))
  }
  return found
}

test("English is handed back untouched", () => {
  equal(Texte.t("Nothing played yet.", "en"), "Nothing played yet.")
  equal(Texte.t("Favorites", "en"), "Favorites")
})

test("German comes back translated", () => {
  equal(Texte.t("Favorites", "de"), "Favoriten")
  equal(Texte.t("Nothing played yet.", "de"), "Noch nichts gespielt.")
})

test("an unknown string falls back to English rather than to nothing", () => {
  equal(Texte.t("Something nobody translated", "de"), "Something nobody translated")
  equal(Texte.t("", "de"), "")
})

test("every string the window shows has a German entry", () => {
  const fehlen = [...gezeigteTexte()].filter(s => s && !schluessel.has(s))
  ok(fehlen.length === 0, "no German for: " + fehlen.map(s => JSON.stringify(s)).join(", "))
})

test("every hint under the list has one too", () => {
  const labels = new Set()
  for (const section of ["radio", "podcast", "broadcast", "favorites", "local", "queue", "history", "settings"]) {
    for (const canGoBack of [false, true]) {
      for (const hint of Model.hintsFor(section, canGoBack)) labels.add(hint.label)
    }
  }
  const fehlen = [...labels].filter(s => !schluessel.has(s))
  ok(fehlen.length === 0, "no German for hint: " + fehlen.join(", "))
})

test("and so does every key hint in the bar card", () => {
  const s = src("BarWidget.qml")
  const block = s.slice(s.indexOf("{taste:"), s.indexOf("]", s.indexOf("{taste:")))
  const woerter = [...block.matchAll(/was: "([^"]+)"/g)].map(m => m[1])
  ok(woerter.length >= 4, "expected the card's key hints, found " + woerter.length)
  const fehlen = woerter.filter(s => !schluessel.has(s))
  ok(fehlen.length === 0, "no German for card hint: " + fehlen.join(", "))
})

test("no entry is empty", () => {
  for (const key of schluessel) {
    ok(Texte.t(key, "de").length > 0, "empty German for " + JSON.stringify(key))
  }
})

if (failures.length) {
  console.error(failures.map(line => "FAIL " + line).join("\n"))
  console.error("\n" + passed + " passed, " + failures.length + " failed")
  process.exit(1)
}
console.log(passed + " passed")
