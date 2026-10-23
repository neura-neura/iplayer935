# iOS 6 compatibility validation

The iOS 6.1.3 target shares the existing library, playlists, favorites, queue,
cache, translations and decoder implementations with iOS 9. Its UIKit,
remote-event and AVPlayer volume adapters are isolated behind `IP_IOS6`.
The presence of a shared implementation is not evidence of a physical test.
The two release IPAs target their respective iOS versions separately. The iOS 9 default target retains its existing behavior.

## Current evidence — build 42

| Feature | Host/implementation evidence | iPod touch 5 / iOS 6 evidence |
| --- | --- | --- |
| Servers and SMB | Profiles, endpoint identity and persistence regression | User confirmed saving server, connection and directory reading |
| Large library | SQLite 3.7.13 atomic scan, paging, search and lazy sort indexes | User confirmed 25k library and MP3 playback |
| Persistent tags and covers | Bounded indexing, cover repair, restart and pause regressions | User confirmed tag cache completed after build 42 |
| MP3 transport | Native cached MP3 typed-link checks | User confirmed play, pause, next and seeking |
| FLAC | Decoder, AudioQueue simulation and near-tail seek regressions | User confirmed seek forward/back and crossfade |
| Ogg / Opus | Real decoding and seek/PCM regressions | On-device fixtures decode nonzero PCM; user confirmed local Ogg/Opus playback and seeking |
| Crossfade | Curves, duration, flags and independent deck gains | User confirmed FLAC crossfade |
| Persistent appearance | Isolated silver/black UIKit surfaces | User confirmed both variants and persistence |
| Manual downloads | Download, persistence, cache promotion and separation regressions | User confirmed downloads work after tag caching finished |
| Automatic cache | Queue prefetch, eviction, cancellation, complete-file and restart regressions | User confirmed advancing offline through two upcoming tracks whose complete cache files were verified |
| Queue / restoration / shuffle | Stable IDs, shuffle permutations, original-order restoration, position and lazy queue regressions | User confirmed current song, position and queue survive full quit/relaunch, resume offline and advance through verified cached tracks |
| Search / metadata sorting | Database queries tested with old SQLite engine | User confirmed artist search and changing sort |
| Favorites / multiselection | Bulk persistence, notifications, identities, deduplication regression | User confirmed favorites and multiple-song selection |
| Playlists / M3U | Reference resolution, imported order, duplicates, persistence regression | Imported playlist present; user confirmed creating a playlist and adding selected songs |
| Local | Filesystem discovery, unchanged refresh, missing files, read-only source, remote-cache exclusion regression | User confirmed local MP3/Ogg/Opus fixtures play and Ogg/Opus seek; User also confirmed native iTunes-imported song discovery, metadata/artwork, playback and seeking |
| Three languages | Translation-key coverage, format placeholders, fallback and persisted preference regression | User confirmed English/Simplified Chinese tabs, menus and player, uninterrupted audio and persisted selection |
| Lock screen / background / headphones | Legacy remote event adapter and interruption/route handlers present | User confirmed locked-screen playback and system pause/next controls; headphone controls/disconnect not tested (no headphones available) |
| AirPlay | Native MPVolumeView route control retained | Requires available receiver; untested |

All 15 `Tests/run-*.sh` runners passed in this audit, including actual
SQLite 3.7.13 database/Store tests and the isolated legacy AVPlayer gain test.
Logs are in ignored `build/ios6-audit42/`. Most portable host tests execute
shared implementations; they do not emulate iOS 6 UIKit or its media stack.
The device report identifies build 42, iOS 6.1.3, 25,156 records, three manual
downloads and 29 automatic-cache entries. These are observations, not throughput
or memory benchmarks.

## Pending device checks

1. Test headphone controls and pause on disconnect when headphones become
   available. Test AirPlay only when a receiver is available.

For the historical fixes and per-build evidence, see [VALIDATION.md](VALIDATION.md).
Publication of both targets was subsequently authorized by the user; the validation limits above still apply.


## Offline advance confirmation

After the read-only verification of complete cache files, the user confirmed
both upcoming tracks played with Wi-Fi disabled. This closes the pending
known-cached-track advance check; it does not imply that uncached songs are
available offline. No app rebuild, cache replacement or queue changes were
needed.


## Native iTunes playback confirmation

The user confirmed that `YOU, You, you` by San Holo appears in Local with its
metadata and artwork, plays correctly and supports seeking. The MP3 was imported
into this device's native music library through Apple Music/Finder, separately
from the synthetic Documents fixtures and player downloads. Headphone controls,
pause on unplug and AirPlay remain untested; no accessory compatibility claim
is inferred from the other successful checks.
