#!/usr/bin/env node
// Tests for the two discovery adapters — Ard.js and RadioBrowser.js.
//
//   node dev/test-adapters.js
//
// Both talk to a public API over XMLHttpRequest, which is the only Qt-ish
// thing in them, so the tests hand them one of their own and answer with
// trimmed captures of the real responses. That checks two things the window
// depends on: the URL each call asks for, and the rows it turns an answer
// into — including the entries it must drop, such as a station with no
// stream or an episode with no audio.

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

function equal(actual, expected, what) {
  const a = JSON.stringify(actual)
  const b = JSON.stringify(expected)
  if (a !== b) throw new Error((what || "value") + " was " + a + ", expected " + b)
}

function ok(value, what) {
  if (!value) throw new Error((what || "value") + " was falsy")
}

// A single-shot XMLHttpRequest that answers from `answers`, keyed on the URL
// prefix, and records every URL it was asked for.
function loadAdapter(file, answers, asked) {
  const source = fs.readFileSync(path.join(__dirname, "..", "src", file), "utf8")
  function FakeXhr() {
    this.readyState = 0
    this.status = 200
    this.responseText = ""
    this.DONE = 4
  }
  FakeXhr.DONE = 4
  FakeXhr.prototype.open = function (method, url) { this._url = url }
  FakeXhr.prototype.setRequestHeader = function () {}
  FakeXhr.prototype.send = function () {
    asked.push(this._url)
    const key = Object.keys(answers).find(prefix => this._url.indexOf(prefix) >= 0)
    if (key === undefined) {
      this.status = 404
      this.responseText = ""
    } else {
      this.responseText = typeof answers[key] === "string" ? answers[key] : JSON.stringify(answers[key])
    }
    this.readyState = 4
    this.onreadystatechange()
  }

  const exported = file === "Ard.js"
    ? "{ imageUrl, search, episodes, categories, categoryShows, liveStations, toTrack }"
    : "{ topStations, search, countries, toTrack }"
  return new Function("XMLHttpRequest", source + "; return " + exported)(FakeXhr)
}

// ---- ARD Audiothek --------------------------------------------------------

const ardSearch = {
  data: {search: {programSets: {nodes: [
    {
      id: 72633432,
      title: "ARD Radiofeature",
      numberOfElements: 111,
      synopsis: "Das Feature",
      image: {url1X1: "https://img.example/{width}"},
      publicationService: {title: "ARD"}
    }
  ]}}}
}

const ardEpisodes = {
  data: {programSet: {
    title: "ARD Radiofeature",
    items: {nodes: [
      {
        id: 1,
        title: "Nach 9/11",
        duration: 3256,
        image: {url: "https://img.example/ep?w={width}"},
        audios: [{url: "https://audio.example/a.mp3", downloadUrl: "https://audio.example/a-dl.mp3"}]
      },
      {id: 2, title: "Ein Beitrag ohne Ton", audios: []}
    ]}
  }}
}

const ardCategories = {
  data: {editorialCategories: {nodes: [
    {id: 63764892, title: "True Crime", image: {url: "https://img.example/c?w={width}"}}
  ]}}
}

const ardCategory = {
  data: {editorialCategory: {sections: [
    {type: "STAGE", title: null},
    {type: "featured_programset", title: "Top Podcasts", nodes: [
      {id: 1, title: "Show A", image: {}, publicationService: {title: "WDR"}},
      {id: 1, title: "Show A duplicated", image: {}}
    ]},
    {type: "program_sets", title: "Alle Sendungen", programSets: {nodes: [
      {id: 2, title: "Show B", image: {}, organizationName: "SWR"}
    ]}}
  ]}}
}

const ardOrganizations = {
  data: {organizations: {nodes: [
    {
      name: "ARD",
      publicationServices: {nodes: [
        {
          id: "1",
          title: "ARD",
          image: {},
          liveStreams: {items: [{stream: {shortTitle: "9/11: Die Anschläge", streamUrl: "https://live.example/ard.aac"}}]}
        }
      ]}
    },
    {
      name: "SWR",
      publicationServices: {nodes: [
        {id: "2926", title: "SWR1", image: {url: "https://img.example/swr1?w={width}"}, liveStreams: {items: [
          {stream: {shortTitle: "SWR1 Live", streamUrl: "https://live.example/swr1.aac"}},
          {stream: {shortTitle: "second stream", streamUrl: "https://live.example/other.aac"}}
        ]}},
        {id: "2927", title: "SWR2", image: {}, liveStreams: {items: []}}
      ]}
    }
  ]}}
}

test("ARD search asks for program sets and shapes them", () => {
  const asked = []
  const Ard = loadAdapter("Ard.js", {"/search/programsets": ardSearch}, asked)
  let shows = null
  Ard.search("ARD Radiofeature", 5, result => { shows = result })
  ok(asked[0].indexOf("query=ARD%20Radiofeature") > 0, "the query is encoded: " + asked[0])
  ok(asked[0].indexOf("limit=5") > 0, "the limit is passed")
  equal(shows.length, 1)
  equal(shows[0].kind, "show")
  equal(shows[0].title, "ARD Radiofeature")
  equal(shows[0].subtitle, "ARD", "the publication service names the show's home")
  equal(shows[0].art, "https://img.example/448", "the templated width is filled in")
})

test("ARD episodes keep their audio and drop what has none", () => {
  const asked = []
  const Ard = loadAdapter("Ard.js", {"/programsets/": ardEpisodes}, asked)
  let episodes = null
  Ard.episodes("72633432", "ARD Radiofeature", 60, result => { episodes = result })
  equal(episodes.length, 1, "the episode without audio is not offered")
  equal(episodes[0].url, "https://audio.example/a.mp3")
  equal(episodes[0].duration, 3256)
  equal(episodes[0].subtitle, "ARD Radiofeature", "the show names the episode")
})

test("ARD categories become rows", () => {
  const Ard = loadAdapter("Ard.js", {"/editorialcategories": ardCategories}, [])
  let categories = null
  Ard.categories(result => { categories = result })
  equal(categories.length, 1)
  equal(categories[0].kind, "category")
  equal(categories[0].title, "True Crime")
})

test("a category's sections collapse into one list without repeats", () => {
  const Ard = loadAdapter("Ard.js", {"/editorialcategories/": ardCategory}, [])
  let shows = null
  Ard.categoryShows("63764892", result => { shows = result })
  equal(shows.map(show => show.title), ["Show A", "Show B"], "the duplicate id appears once")
})

test("live stations name themselves after the programme when the service cannot", () => {
  const Ard = loadAdapter("Ard.js", {"/organizations": ardOrganizations}, [])
  let stations = null
  Ard.liveStations(result => { stations = result })
  equal(stations.length, 2, "one per service that has a stream")
  equal(stations[0].title, "9/11: Die Anschläge", "the ARD service is named after itself, so use the programme")
  equal(stations[0].subtitle, "ARD")
  equal(stations[1].title, "SWR1", "a real station name is kept")
  equal(stations[1].subtitle, "SWR · SWR1 Live")
  equal(stations[1].url, "https://live.example/swr1.aac", "the first stream is the station")
})

test("an ARD row becomes a cliamp track", () => {
  const Ard = loadAdapter("Ard.js", {}, [])
  const live = Ard.toTrack({kind: "live", title: "SWR1", subtitle: "SWR", url: "https://live.example/swr1.aac"})
  equal(live.station, "SWR1")
  ok(live.realtime, "live radio is realtime, so cliamp does not try to seek it")
  ok(live.stream)

  const episode = Ard.toTrack({kind: "episode", title: "Nach 9/11", subtitle: "ARD Radiofeature", url: "https://a", duration: 3256.4})
  equal(episode.duration_secs, 3256, "a fractional duration is rounded")
  equal(episode.album, "ARD Radiofeature")
  ok(!episode.realtime, "an episode is not live")
})

test("ARD failures are reported, not swallowed", () => {
  const Ard = loadAdapter("Ard.js", {}, [])
  let error = ""
  Ard.categories(() => { throw new Error("must not succeed") }, message => { error = message })
  ok(error.indexOf("404") > 0, "the status makes it into the message: " + error)
})

// ---- Radio Browser --------------------------------------------------------

const rbStations = [
  {stationuuid: "a", name: " MANGORADIO ", country: "Germany", tags: "music,variety,extra,more", url_resolved: "https://stream.example/mango", favicon: "https://img.example/mango.png", votes: 12},
  {stationuuid: "b", name: "Broken", country: "Germany", tags: "", url_resolved: "", url: "", votes: 1}
]

test("Radio Browser asks for the country's most-voted stations", () => {
  const asked = []
  const RadioBrowser = loadAdapter("RadioBrowser.js", {"/stations/bycountrycodeexact/": rbStations}, asked)
  let stations = null
  RadioBrowser.topStations("DE", 60, result => { stations = result })
  ok(asked[0].indexOf("/stations/bycountrycodeexact/DE") > 0, asked[0])
  ok(asked[0].indexOf("order=votes") > 0, "most-voted first")
  ok(asked[0].indexOf("hidebroken=true") > 0, "no dead streams")
  equal(stations.length, 1, "a station with no playable url is dropped")
  equal(stations[0].title, "MANGORADIO", "the name is trimmed")
  equal(stations[0].subtitle, "Germany · music · variety · extra", "country plus the first three tags")
})

test("search puts the home country first", () => {
  const answer = [
    {stationuuid: "1", name: "Far", country: "Portugal", url_resolved: "https://a", votes: 50},
    {stationuuid: "2", name: "Near", country: "Germany", url_resolved: "https://b", votes: 1}
  ]
  const RadioBrowser = loadAdapter("RadioBrowser.js", {"/stations/search": answer}, [])
  let stations = null
  RadioBrowser.search("radio", "Germany", 40, result => { stations = result })
  equal(stations.map(station => station.title), ["Near", "Far"], "home first, despite fewer votes")
})

test("countries without an ISO code are not offered", () => {
  const RadioBrowser = loadAdapter("RadioBrowser.js", {"/countries": [
    {name: "Germany", iso_3166_1: "DE", stationcount: 3000},
    {name: "Nowhere", stationcount: 2}
  ]}, [])
  let countries = null
  RadioBrowser.countries(result => { countries = result })
  equal(countries.length, 1)
  equal(countries[0].id, "DE")
  equal(countries[0].subtitle, "3000 stations")
})

test("a Radio Browser row becomes a live cliamp track", () => {
  const RadioBrowser = loadAdapter("RadioBrowser.js", {}, [])
  const track = RadioBrowser.toTrack({title: "1LIVE", subtitle: "Germany · rock", url: "https://live", art: "https://img"})
  equal(track.station, "1LIVE")
  equal(track.path, "https://live")
  ok(track.realtime && track.stream)
})

if (failures.length) {
  console.error(failures.map(line => "FAIL " + line).join("\n"))
  console.error("\n" + passed + " passed, " + failures.length + " failed")
  process.exit(1)
}
console.log(passed + " passed")
