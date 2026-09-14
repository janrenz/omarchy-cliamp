.pragma library

// Deutsch und Englisch, in einer Datei.
//
// Der Schlüssel ist der englische Satz, so wie er im Quelltext steht. Das hat
// zwei Gründe: der Quelltext bleibt lesbar — `t("Nothing played yet.")` sagt,
// was dasteht, während `t("history.empty")` erst nachgeschlagen werden muss —
// und eine fehlende Übersetzung fällt nicht aus, sondern auf Englisch zurück.
// Ein englischer Satz an deutscher Stelle ist ein Schönheitsfehler; ein leerer
// Knopf wäre einer, den man erst im Betrieb bemerkt.
//
// Nicht übersetzt wird, was kein Text ist, sondern ein Wert: die Namen der
// Equalizer-Vorgaben und die Wiederholmodi gehen so an cliamp zurück, wie sie
// hereinkamen, und Sendernamen gehören dem, der sie vergeben hat.
//
// Geprüft von dev/test-texte.js: jedes t() im Quelltext muss hier einen Eintrag
// haben, und jeder Eintrag hier muss im Quelltext vorkommen.

var DE = {
  // ---- Bereiche -----------------------------------------------------------
  "Favorites": "Favoriten",
  "Radio": "Radio",
  "Podcasts": "Podcasts",
  "Broadcast": "Rundfunk",
  "Files": "Dateien",
  "Queue": "Warteschlange",
  "History": "Verlauf",
  "Settings": "Einstellungen",

  "Everything you starred": "Alles, was du markiert hast",
  "cliamp's own station list": "cliamps eigene Senderliste",
  "Apple directory and RSS": "Apple-Verzeichnis und RSS",
  "Live radio worldwide": "Radio aus aller Welt, live",
  "Saved and local playlists": "Gespeicherte und lokale Wiedergabelisten",
  "What plays next": "Was als Nächstes läuft",
  "Recently played": "Zuletzt gespielt",
  "Output, sound, session": "Ausgabe, Klang, Sitzung",

  // ---- Suche und Listen ---------------------------------------------------
  "Search stations and shows…": "Sender und Sendungen suchen…",
  "Search podcasts…": "Podcasts suchen…",
  "Search stations…": "Sender suchen…",
  "Search your library…": "Deine Dateien durchsuchen…",
  "Filter…": "Filtern…",
  "loading…": "lädt…",
  "Top stations · ": "Top-Sender · ",
  "Country · ": "Land · ",
  "Broadcast · ": "Rundfunk · ",
  " item": " Eintrag",
  " items": " Einträge",

  // ---- Leere Bereiche -----------------------------------------------------
  "Nothing matches this filter.": "Nichts passt zu diesem Filter.",
  "Nothing starred yet. Press f on a station, a show or an episode and it lands here.":
    "Noch nichts markiert. Drücke f auf einem Sender, einer Sendung oder einer Folge, dann landet sie hier.",
  "The queue is empty. Play something from Radio or Broadcast.":
    "Die Warteschlange ist leer. Spiel etwas aus Radio oder Rundfunk.",
  "Nothing played yet.": "Noch nichts gespielt.",
  "No saved playlists yet. cliamp's playlist command makes them.":
    "Noch keine gespeicherten Wiedergabelisten. cliamps Befehl playlist legt sie an.",
  "Nothing here yet. Press / to search.": "Noch nichts hier. Drücke / zum Suchen.",

  // ---- Bedienung ----------------------------------------------------------
  "Play  ·  ⏎": "Abspielen  ·  ⏎",
  "Play next  ·  ⇧⏎": "Als Nächstes  ·  ⇧⏎",
  "Star  ·  f": "Markieren  ·  f",
  "Remove star  ·  f": "Markierung entfernen  ·  f",
  "Previous  ·  p": "Zurück  ·  p",
  "Next  ·  n": "Weiter  ·  n",
  "Louder  ·  +": "Lauter  ·  +",
  "Quieter  ·  −": "Leiser  ·  −",
  "Stop": "Stopp",
  "Play / pause  ·  space": "Play/Pause  ·  Leertaste",
  "Repeat · ": "Wiederholen · ",
  "Shuffle": "Zufall",

  // ---- Tastenhinweise (klein geschrieben wie im Englischen) ---------------
  "move": "bewegen",
  "play": "spielen",
  "remove": "entfernen",
  "queue next": "als Nächstes",
  "star": "markieren",
  "nav / list": "Navigation / Liste",
  "search": "suchen",
  "play/pause": "Play/Pause",
  "back": "zurück",
  "close": "schließen",
  "apply": "übernehmen",
  "keys": "Tasten",
  "window": "Fenster",
  "settings": "Einstellungen",

  // ---- Hilfe --------------------------------------------------------------
  "Keyboard": "Tastatur",
  "Any key closes this.": "Jede Taste schließt das hier.",
  "Move through the list": "Durch die Liste gehen",
  "Switch section": "Bereich wechseln",
  "Search this section": "In diesem Bereich suchen",
  "Favorite station / subscribe to show": "Sender markieren / Sendung abonnieren",
  "Next / previous track": "Nächster / voriger Titel",
  "Volume by 1 dB": "Lautstärke um 1 dB",
  "Seek 10s (when seekable)": "10 s springen, wo es geht",
  "Back, then close": "Zurück, dann schließen",
  "First / last entry": "Erster / letzter Eintrag",
  "Remove from the queue": "Aus der Warteschlange nehmen",
  "Queue next instead": "Stattdessen als Nächstes einreihen",
  "Play, or open a show": "Abspielen oder Sendung öffnen",
  "Play / pause": "Play / Pause",
  "This help": "Diese Hilfe",

  // ---- Einstellungen ------------------------------------------------------
  "OUTPUT": "AUSGABE",
  "EQUALIZER": "EQUALIZER",
  "PLAYBACK": "WIEDERGABE",
  "DISCOVERY": "ENTDECKEN",
  "WINDOW": "FENSTER",
  "SESSION": "SITZUNG",
  "LANGUAGE": "SPRACHE",
  "shuffle": "Zufall",
  "mono": "Mono",
  "spectrum": "Spektrum",
  "repeat ": "Wiederholen ",
  "Floating overlay": "Schwebend über allem",
  "Normal window": "Normales Fenster",
  "Title in the bar": "Titel in der Leiste",
  "Spectrum only": "Nur Spektrum",
  "System": "System",
  "English": "English",
  "German": "Deutsch",
  "Broadcast country · ": "Rundfunkland · ",
  "Detected from your timezone. Podcast charts follow cliamp's own setting in ~/.config/cliamp/config.toml.":
    "Aus deiner Zeitzone erkannt. Die Podcast-Charts folgen cliamps eigener Einstellung in ~/.config/cliamp/config.toml.",
  "An overlay sits above everything and closes when you click away from it. A normal window is one Hyprland tiles and keeps on its workspace — opening it again focuses the one you have rather than making a second. Switching reopens the window. The bar can show what is playing or just the spectrum — with the title gone, clicking it plays and pauses, and the card comes up while you rest on it.":
    "Die Überlagerung liegt über allem und geht zu, wenn du daneben klickst. Das normale Fenster ist eines, das Hyprland kachelt und auf seinem Arbeitsbereich behält — wer es erneut öffnet, bekommt das vorhandene statt eines zweiten. Ein Wechsel öffnet das Fenster neu. Die Leiste zeigt entweder, was läuft, oder nur das Spektrum — ohne Titel schaltet ein Klick Play/Pause, und die Karte kommt, während der Zeiger darauf ruht.",
  "The interface follows your system language unless you pick one here.":
    "Die Oberfläche folgt deiner Systemsprache, solange du hier keine wählst.",
  "Hand over to terminal": "An das Terminal übergeben",
  "Only one cliamp can hold the socket. Handing over stops the background player and opens the terminal one on the current track.":
    "Nur ein cliamp kann den Socket halten. Beim Übergeben hört der Spieler im Hintergrund auf, und das Terminal übernimmt den laufenden Titel.",
  "Reconnect": "Neu verbinden",
  "󰄬  cliamp · connected": "󰄬  cliamp · verbunden",
  "󰄬  cliamp · background": "󰄬  cliamp · im Hintergrund",
  "󰅖  cliamp · offline": "󰅖  cliamp · offline",

  // ---- Leiste -------------------------------------------------------------
  "Nothing playing": "Nichts läuft",
  "Paused": "Pausiert",
  "Media source": "Medienquelle",
  "Open window": "Fenster öffnen"
}

/** Der englische Text, oder seine deutsche Entsprechung. */
function t(text, sprache) {
  if (sprache !== "de") return text
  var uebersetzt = DE[text]
  return uebersetzt === undefined ? text : uebersetzt
}

/** Für den Test: was hier steht, ohne es von außen ändern zu können. */
function schluessel() {
  var liste = []
  for (var k in DE) liste.push(k)
  return liste
}
