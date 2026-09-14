---
name: omarchy-cliamp
description: Control music playback on this machine through cliamp — play a station or podcast, read what is playing, manage the queue — via cliamp's v2 IPC, the same socket the Omarchy cliamp plugin uses. Use when asked to play, pause, skip, queue, or report on music or radio here.
---

# Music on this machine, through cliamp

cliamp is the player; the Omarchy plugin is one face for it. Both talk to the
same Unix socket, so anything here is visible in the bar widget, the library
window and the terminal player at once.

    cliamp remote capabilities   # every operation, as JSON

If nothing answers ("cliamp is not running"), start it headless rather than
opening a terminal player: `setsid -f cliamp --daemon`. The plugin does the
same, and the bar picks it up within three seconds.

## Read what is going on

```sh
cliamp remote call runtime.status --wait     # state, track, position, EQ, modes
cliamp remote call queue.list --params '{"limit":50}' --wait
cliamp remote call history --params '{"limit":20}' --wait
```

Sync operations answer with `snapshot` at the top level; async ones answer with
a `job` carrying both `result` and `snapshot`. Always pass `--wait`.

## Play something

```sh
# a station or show cliamp already knows
cliamp remote call provider.catalog --params '{"provider":"radio","limit":500}' --wait
cliamp remote call provider.tracks --params '{"provider":"radio","playlist":"l:12"}' --wait

# anything else: hand it a track
cliamp remote call track.play --params '{"track":{"title":"1LIVE","path":"https://…","stream":true,"realtime":true}}' --wait
cliamp remote call track.queue --params '{"track":{…}}' --wait   # next, instead of now
```

`provider` is one of radio, podcast, local, and whatever remote services the
user has configured (`provider.list`).

## Control it

```sh
cliamp toggle | next | prev | stop
cliamp remote call volume.adjust --params '{"value":-3}' --wait
cliamp remote call seek.absolute --params '{"value":120}' --wait
cliamp remote call repeat --params '{"name":"all"}' --wait
```

## What not to do

- Do not start a second `cliamp` in a terminal while a daemon is running: only
  one instance can hold the socket, and the second one runs blind.
- Do not change the user's queue to answer a question. Reading is `queue.list`;
  `queue.clear` is not a way to "check" anything.
- `vis` and `theme` fail while cliamp runs headless. That is expected.
