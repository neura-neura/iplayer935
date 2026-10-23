# iOS 6 compatibility validation (local development)

The iOS 6.1.3 target shares the existing library, playlists, favorites, queue,
cache, translations and decoder implementations with iOS 9. Its UIKit,
remote-event and AVPlayer volume adapters are isolated behind `IP_IOS6`.
The presence of a shared implementation is not evidence of a physical test.
No iOS 6 release has been published. The iOS 9 default target remains unchanged.

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
| Automatic cache | Queue prefetch, eviction, cancellation, complete-file and restart regressions | Device report contains 29 complete cached files; full Wi-Fi-off queue/session journey still needs explicit confirmation |
| Queue / restoration / shuffle | Stable IDs, shuffle permutations, original-order restoration, position and lazy queue regressions | Full kill/relaunch/offline journey pending |
| Search / metadata sorting | Database queries tested with old SQLite engine | User confirmed artist search and changing sort |
| Favorites / multiselection | Bulk persistence, notifications, identities, deduplication regression | User confirmed favorites and multiple-song selection |
| Playlists / M3U | Reference resolution, imported order, duplicates, persistence regression | Imported playlist present; user confirmed creating a playlist and adding selected songs |
| Local | Filesystem discovery, unchanged refresh, missing files, read-only source, remote-cache exclusion regression | User confirmed local MP3/Ogg/Opus fixtures play and Ogg/Opus seek; native iTunes item test still pending |
| Three languages | Translation-key coverage, format placeholders, fallback and persisted preference regression | Full iOS 6 settings/tab/player journey pending |
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
2. Native iTunes media needs a separate check with a song imported into this
   particular device. The three local synthetic test files remain in Documents;
   they are not player downloads or automatic cache. No preexisting media was
   replaced.
3. Switch Spanish/English/Simplified Chinese while playing; check tabs, menus,
   player, persisted choice and uninterrupted audio. Restore the preferred
   language afterward.
4. With known complete cached songs, disable Wi-Fi, advance, pause, fully quit
   and reopen. Verify current title, position and queue; resume and advance.
   Reenable Wi-Fi afterward.

For the historical fixes and per-build evidence, see [VALIDATION.md](VALIDATION.md).
Keep updates in local Git until publication is explicitly requested again.
