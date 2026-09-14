# SPEC

What the plugin promises, in the order a person meets it.

## The bar

1. The widget is always visible, whether or not anything is playing — it is the
   way into the library, so it cannot depend on there being a track.
2. While something plays it shows the track title, scrolling when it does not
   fit, and cliamp's spectrum beside it, 15 frames a second.
3. Paused, it says `Paused` and the spectrum morphs — the same five rectangles —
   into a pause glyph. It does not swap in a different icon, and it does not
   keep scrolling a title that is not playing.
4. On radio, the title is the song cliamp reports (ICY metadata), not the
   station: MPRIS reports the station as the title, which is the less useful of
   the two, so cliamp's answer wins when it has one.
5. Left click opens the library. Middle click skips. The wheel moves through the
   queue. Right click opens the MPRIS popup, which is the inherited behaviour.

## The library

6. Eight sections: Favorites, Radio, Podcasts, Broadcast, Files, Queue, History,
   Settings. `1`…`8` jump; `Tab` cycles; `←`/`→` move between sidebar and list.
7. Every list is one row shape: artwork, title, subtitle, duration, and the
   actions that apply to that row — play, queue next, star.
8. `⏎` plays a playable row and opens a container row (a show, a topic, a
   country). `⇧⏎` queues instead of playing. `Esc` goes back one level, then
   closes.
9. A section that is loading says so; one that is empty says why it is empty and
   what to press; one that failed shows the failure rather than an empty list.
10. Searching asks the section's own source: cliamp's providers for Radio,
    Podcasts and Files; Radio Browser plus the ARD Audiothek for Broadcast.

## Broadcast

11. The country comes from the system timezone (`/usr/share/zoneinfo/zone1970.tab`),
    not from a hardcoded default, and is switchable from the first row of the
    section and from Settings.
12. Stations come from Radio Browser, most-voted first, dead streams hidden.
13. Where a public broadcaster publishes its own catalogue, it is folded in
    below the stations. Germany gets the ARD Audiothek: its live streams, its
    topics, and the programmes inside them.

## Stars

14. Anything playable can be starred, including entries cliamp has no favorite
    for. Stars persist across restarts.
15. Starring something cliamp knows — a station, a podcast show — also toggles
    cliamp's own favorite or subscription.
16. A starred stream plays from the star without asking its API again.

## cliamp

17. If cliamp is not running when something is asked of it, the plugin starts it
    headless, retries the call, and notifies once. Background polling never
    starts it.
18. Pausing, seeking, volume, EQ, speed, shuffle, repeat and the device are the
    running cliamp's — the TUI sees every change immediately, because there is
    one instance.
19. Only one cliamp can hold the socket. Settings → Hand over to terminal stops
    a background player and opens the terminal one on the current track.
