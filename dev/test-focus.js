#!/usr/bin/env node
// Guards the one thing about this window that nothing else can see: whether a
// key ever reaches it.
//
//   node dev/test-focus.js
//
// Library.qml handles Escape, /, the arrows and the section digits on a plain
// Item with `focus: true`. That only becomes active focus if every focus scope
// above it passes it on — and Loader is a focus scope. A Loader without
// `focus: true` therefore swallows the entire keyboard, silently: the window
// still opens, still draws, still takes the mouse, and no key does anything.
// It shipped that way once, when the library moved into two Loaders for the
// overlay and the ordinary window.
//
// Cheap to check, and it costs nothing to keep checking: read the file, find
// the Loaders that host the library, insist each one says focus: true.

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

const app = fs.readFileSync(path.join(__dirname, "..", "src", "App.qml"), "utf8")

// Every Loader block, from "Loader {" to the line that closes it at the same
// indent. Good enough for a file we write ourselves, and it keeps the test
// free of a QML parser.
function loaders(source) {
  const found = []
  const lines = source.split("\n")
  for (let i = 0; i < lines.length; i++) {
    const start = lines[i].match(/^(\s*)Loader \{\s*$/)
    if (!start) continue
    const indent = start[1]
    const block = []
    for (let j = i + 1; j < lines.length; j++) {
      if (lines[j] === indent + "}") break
      block.push(lines[j])
    }
    found.push(block.join("\n"))
  }
  return found
}

test("both surfaces host the library in a Loader", () => {
  const hosting = loaders(app).filter(block => /sourceComponent:\s*libraryComponent/.test(block))
  ok(hosting.length === 2, "expected the overlay and the window, found " + hosting.length)
})

test("a Loader around the library passes the keyboard on", () => {
  for (const block of loaders(app)) {
    if (!/sourceComponent:\s*libraryComponent/.test(block)) continue
    ok(/^\s*focus: true\s*$/m.test(block),
       "a Loader holding the library has no `focus: true` - Escape and every other key would do nothing")
  }
})

test("the library still expects the focus it is handed", () => {
  const library = fs.readFileSync(path.join(__dirname, "..", "src", "Library.qml"), "utf8")
  ok(/id: keyCatcher/.test(library), "keyCatcher is gone - this test is watching the wrong thing")
  const catcher = library.slice(library.indexOf("id: keyCatcher"))
  ok(/^\s*focus: true\s*$/m.test(catcher.slice(0, 600)), "keyCatcher no longer asks for focus")
  ok(/Qt\.Key_Escape/.test(catcher), "Escape is no longer handled where this test looks")
})

if (failures.length) {
  console.error(failures.map(line => "FAIL " + line).join("\n"))
  console.error("\n" + passed + " passed, " + failures.length + " failed")
  process.exit(1)
}
console.log(passed + " passed")
