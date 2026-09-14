// Radio Browser: a community directory of live radio for every country, no
// key and no account. It is the worldwide fallback behind the broadcast
// section — country-specific adapters (ARD for DE) layer on top of it.

var BASE = "https://de1.api.radio-browser.info/json"
var AGENT = "omarchy-cliamp"

function getJson(path, onDone, onError) {
  var xhr = new XMLHttpRequest()
  xhr.open("GET", BASE + path)
  xhr.setRequestHeader("Accept", "application/json")
  xhr.setRequestHeader("User-Agent", AGENT)
  xhr.onreadystatechange = function () {
    if (xhr.readyState !== XMLHttpRequest.DONE) return
    if (xhr.status < 200 || xhr.status >= 300) {
      if (onError) onError("Radio Browser: HTTP " + xhr.status)
      return
    }
    try {
      onDone(JSON.parse(xhr.responseText))
    } catch (e) {
      if (onError) onError("Radio Browser: unreadable response")
    }
  }
  xhr.send()
}

function stationFrom(node) {
  var tags = (node.tags || "").split(",").filter(function (tag) { return tag }).slice(0, 3).join(" · ")
  return {
    kind: "live",
    id: node.stationuuid,
    title: node.name ? node.name.trim() : "",
    subtitle: [node.country, tags].filter(function (part) { return part }).join(" · "),
    art: node.favicon || "",
    url: node.url_resolved || node.url || "",
    votes: node.votes || 0
  }
}

function topStations(countryCode, limit, onDone, onError) {
  var path = "/stations/bycountrycodeexact/" + encodeURIComponent(countryCode)
    + "?limit=" + (limit || 60) + "&order=votes&reverse=true&hidebroken=true"
  getJson(path, function (nodes) {
    onDone((nodes || []).map(stationFrom).filter(function (station) { return station.url !== "" }))
  }, onError)
}

function search(query, countryCode, limit, onDone, onError) {
  var path = "/stations/search?name=" + encodeURIComponent(query)
    + "&limit=" + (limit || 40) + "&order=votes&reverse=true&hidebroken=true"
  getJson(path, function (nodes) {
    var stations = (nodes || []).map(stationFrom).filter(function (station) { return station.url !== "" })
    // Home country first — the same search from Berlin and from Lisbon should
    // not open with the same list.
    if (countryCode) {
      stations.sort(function (a, b) {
        var aHome = (a.subtitle || "").indexOf(countryCode) === 0 ? 1 : 0
        var bHome = (b.subtitle || "").indexOf(countryCode) === 0 ? 1 : 0
        return bHome - aHome
      })
    }
    onDone(stations)
  }, onError)
}

function countries(onDone, onError) {
  getJson("/countries?order=stationcount&reverse=true&hidebroken=true", function (nodes) {
    onDone((nodes || []).filter(function (node) { return node.iso_3166_1 }).map(function (node) {
      return {
        kind: "country",
        id: node.iso_3166_1,
        title: node.name || node.iso_3166_1,
        subtitle: (node.stationcount || 0) + " stations",
        art: ""
      }
    }))
  }, onError)
}

function toTrack(entry) {
  return {
    title: entry.title,
    artist: entry.subtitle || "",
    path: entry.url,
    album_art_url: entry.art || "",
    station: entry.title,
    stream: true,
    realtime: true
  }
}
