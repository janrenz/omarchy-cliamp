// ARD Audiothek REST client.
//
// cliamp's podcast provider goes through Apple's directory, which carries ARD
// shows but not the Audiothek's own curation, and none of the ARD live radio
// streams. This talks to api.ardaudiothek.de directly and hands cliamp plain
// track objects via track.play / track.queue.

var BASE = "https://api.ardaudiothek.de"

function getJson(url, onDone, onError) {
  var xhr = new XMLHttpRequest()
  xhr.open("GET", url)
  xhr.setRequestHeader("Accept", "application/json")
  xhr.onreadystatechange = function () {
    if (xhr.readyState !== XMLHttpRequest.DONE) return
    if (xhr.status < 200 || xhr.status >= 300) {
      if (onError) onError("ARD Audiothek: HTTP " + xhr.status)
      return
    }
    try {
      onDone(JSON.parse(xhr.responseText))
    } catch (e) {
      if (onError) onError("ARD Audiothek: unreadable response")
    }
  }
  xhr.send()
}

// Image URLs are templated on {width}; ask for something a card can use.
function imageUrl(image, width) {
  if (!image) return ""
  var url = image.url1X1 || image.url || ""
  return url.replace("{width}", String(width || 448))
}

function showFrom(node) {
  return {
    kind: "show",
    id: String(node.id),
    title: node.title || "",
    subtitle: (node.publicationService && node.publicationService.title) || node.organizationName || "ARD",
    synopsis: node.synopsis || "",
    art: imageUrl(node.image, 448),
    count: node.numberOfElements || 0
  }
}

function episodeFrom(node, showTitle) {
  var audios = node.audios || []
  var url = audios.length ? (audios[0].url || audios[0].downloadUrl || "") : ""
  var service = (node.publicationService && node.publicationService.title) || ""
  return {
    kind: "episode",
    id: String(node.id),
    title: node.title || "",
    subtitle: showTitle || (node.programSet && node.programSet.title) || service,
    synopsis: node.synopsis || "",
    art: imageUrl(node.image, 448),
    duration: node.duration || 0,
    published: node.publishDate || "",
    url: url
  }
}

function search(query, limit, onDone, onError) {
  if (!query) { onDone([]); return }
  var url = BASE + "/search/programsets?query=" + encodeURIComponent(query) + "&limit=" + (limit || 24)
  getJson(url, function (payload) {
    var sets = payload.data && payload.data.search && payload.data.search.programSets
    var nodes = (sets && sets.nodes) || []
    onDone(nodes.map(showFrom))
  }, onError)
}

function episodes(showId, showTitle, limit, onDone, onError) {
  var url = BASE + "/programsets/" + encodeURIComponent(showId) + "?limit=" + (limit || 60)
  getJson(url, function (payload) {
    var set = payload.data && payload.data.programSet
    var nodes = (set && set.items && set.items.nodes) || []
    var title = showTitle || (set && set.title) || ""
    onDone(nodes.map(function (n) { return episodeFrom(n, title) }).filter(function (e) { return e.url !== "" }))
  }, onError)
}

function categories(onDone, onError) {
  getJson(BASE + "/editorialcategories", function (payload) {
    var cats = payload.data && payload.data.editorialCategories
    var nodes = (cats && cats.nodes) || []
    onDone(nodes.map(function (n) {
      return {
        kind: "category",
        id: String(n.id),
        title: n.title || "",
        subtitle: "Rubrik",
        art: imageUrl(n.image, 448)
      }
    }))
  }, onError)
}

// A category answers with editorial sections; collect every program set they
// carry, in the order the Audiothek presents them, without duplicates.
function categoryShows(categoryId, onDone, onError) {
  var url = BASE + "/editorialcategories/" + encodeURIComponent(categoryId) + "?limit=30"
  getJson(url, function (payload) {
    var category = payload.data && payload.data.editorialCategory
    var sections = (category && category.sections) || []
    var shows = []
    var seen = {}
    for (var i = 0; i < sections.length; i++) {
      var buckets = [sections[i].nodes || [], (sections[i].programSets && sections[i].programSets.nodes) || []]
      for (var b = 0; b < buckets.length; b++) {
        for (var j = 0; j < buckets[b].length; j++) {
          var node = buckets[b][j]
          if (!node || !node.id || !node.title || seen[node.id]) continue
          seen[node.id] = true
          shows.push(showFrom(node))
        }
      }
    }
    onDone(shows)
  }, onError)
}

// Live radio across every ARD broadcaster.
function liveStations(onDone, onError) {
  getJson(BASE + "/organizations", function (payload) {
    var orgs = (payload.data && payload.data.organizations && payload.data.organizations.nodes) || []
    var stations = []
    for (var i = 0; i < orgs.length; i++) {
      var services = (orgs[i].publicationServices && orgs[i].publicationServices.nodes) || []
      for (var j = 0; j < services.length; j++) {
        var service = services[j]
        var items = (service.liveStreams && service.liveStreams.items) || []
        for (var k = 0; k < items.length; k++) {
          var stream = items[k].stream
          if (!stream || !stream.streamUrl) continue
          var serviceTitle = service.title || ""
          var programme = stream.shortTitle || stream.sender || ""
          var generic = serviceTitle === "" || serviceTitle === orgs[i].name
          stations.push({
            kind: "live",
            id: service.id + ":" + k,
            title: generic && programme ? programme : serviceTitle,
            subtitle: orgs[i].name + (!generic && programme && programme !== serviceTitle ? " · " + programme : ""),
            art: imageUrl(service.image, 448),
            url: stream.streamUrl
          })
          break // one live stream per service is the station itself
        }
      }
    }
    onDone(stations)
  }, onError)
}

// cliamp TrackInfo, as ipc/protocol.go defines it.
function toTrack(entry) {
  var track = {
    title: entry.title,
    artist: entry.subtitle || "ARD",
    path: entry.url,
    album_art_url: entry.art || "",
    stream: true
  }
  if (entry.kind === "live") {
    track.station = entry.title
    track.realtime = true
  } else {
    track.album = entry.subtitle || ""
    if (entry.duration) track.duration_secs = Math.round(entry.duration)
  }
  return track
}
