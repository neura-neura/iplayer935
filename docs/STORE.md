# IPStore

`IPStore` is the persistence boundary for profiles, an offline library, playlists,
Keychain credentials, and user-requested downloads. It uses ARC and Foundation,
Security, and AVFoundation APIs available on iOS 9. Model data is stored as an
atomic JSON document under Application Support; SMB passwords are stored in the
generic-password Keychain and are never written to the JSON document.

The first launch creates only the fictional **Example Music Server** profile: host
`music.example.invalid`, share `Music`, root `Sample Library`, and username
`music-user`. It has no password and cannot start background scans until configured. Profile
dictionaries use `id`, `endpointIdentity`, `name`, `host`, `share`, `root`, and
`username`. Changing a profile endpoint through `setEndpoint:forProfileID:error:`
rotates its endpoint identity and marks its prior tracks unavailable remotely,
while keeping downloaded copies and playlist references. This prevents a stale
library entry from being streamed against a different server or root.

Tracks are dictionaries keyed by a SHA-256 ID derived from profile ID, endpoint
identity, normalized root, and root-relative `path`. They also include
`profileID`, `endpointIdentity`, `title`, `artist`, `album`, `genre`, `duration`,
`trackNumber`, `artwork`, `favorite`, `extension`, `size`, and (for unplayable
file types) `unsupportedReason`. Scan preserves user metadata and favorites
across refreshes. Remote scans read AV metadata through the local streaming
bridge and use the filename when tags are absent. Playlist dictionaries contain `id`,
`name`, and ordered `trackIDs`; M3U/M3U8 imports accept relative paths or SMB/UNC
references matching the active host, share, and root, and discard traversal or
out-of-root references.

Completed downloads live in Application Support/IPStore/Downloads. A bounded
256 KiB chunk is copied at a time to a `.part` file, which is renamed only after
the complete byte count matches the server. Failed or interrupted partial files
are removed. Downloads are explicit; scans never download media. The default
cache limit is 2 GiB and can be changed through `cacheLimitBytes`.
Artwork files live separately under Application Support/IPStore/Artwork, so
clearing audio downloads does not remove the library's artwork.

Playlist imports decode UTF-8 (including BOM) and Windows-1252, read at most
8 MiB, preserve reference order, and report unmatched or unsafe entries through
the progress callback. The scan treats MP3, M4A, AAC, WAV, AIFF, CAF, M4B, and
MP4 as player-supported; FLAC, OGG, Opus, WMA, and raw ALAC entries are retained
with an explanatory unsupported reason.

`scanProfile:progress:completion:` and `downloadTracks:progress:completion:`
run serially on the store's background queue. Progress and completion blocks
are delivered on the main queue. The arrays are mutable for existing UIKit
screens; call `save` after direct UI edits.

## Large collections

`scanProfile` commits the filename-based index and imported playlists first. `enrichProfile` explicitly fills metadata on a separate serial queue; updates commit in batches of 25, checkpointing JSON every 250 and on completion/cancel. `refreshMetadataForTrack` enriches the selected track; playback/download/profile changes cancel bulk enrichment. A same-size previously enriched track keeps its metadata on rescan. `metadataPendingCountForProfile` reports outstanding work.

Persistence uses deeply immutable snapshots on a dedicated queue. `flushPersistence` drains only that queue, never the SMB queue; the app calls it before background suspension. Playlist membership/order uses sets and maps for large libraries. JSON remains a lightweight single-file store; extremely large libraries still require device profiling for peak scan memory and save latency.

Favorites use `setFavorite:forTrack:` and a small atomic `favorites.json` override map keyed by stable track ID. Toggling avoids a full library snapshot; overrides apply at startup and rescan, including explicit false. `IPFavoriteChanged` updates visible rows without reordering the whole library.


Desde compilación19, el almacenamiento canónico es library.sqlite. Los apartados anteriores describen el formato legado de migración; los JSON se conservan como respaldo. Véase [SQLITE.md](SQLITE.md) para lectura por bloques, persistencia incremental y retorno a18.


## Fictional starter profile (build28)

An `exampleProfileSeeded` flag is persisted in JSON/SQLite state, including background preparation snapshots. On the first load after this update, the app appends one fictional profile to existing profiles. A new installation starts with that profile only. Existing IDs, endpoint identities, credentials, default/last server choices, library rows and caches are not replaced. Ready SQLite libraries update only the small state record using updateState:, without reading or rewriting track records. The legacy JSON path carries the flag into normal saves and conversion without overwriting its rollback backup during deferred loading. Deleting the example after saving does not reseed it.

The starter profile contains `isExample=true`; no password is seeded. Opening it shows the editor, and scans, metadata work and connection tests are blocked until configured. Changing its host clears the example marker. Removing an unchanged example skips all unrelated track metadata and cache traversal. Its name, host, share, root and username are deliberately fictional English values; explanatory UI text is available in all three interface languages.


## Built-in Local library

`IPLocalLibrary` discovers system music through MediaPlayer and readable audio beneath the app Documents folder and `/var/mobile/Media`. The synthetic `local-library-v1` profile is outside editable SMB profiles; attempts to delete it or assign credentials/endpoints are rejected. Scanning never modifies source audio, traverses symlinks or contacts SMB. Photos and system media bookkeeping are skipped; iTunes items without a playable asset URL remain explicitly unavailable.

Discovery runs on the serial store worker. Cached rows appear immediately, scans coalesce and automatic checks are throttled to 60 seconds while visible. MediaPlayer change notifications invalidate that throttle. File identity uses a SHA-256 of the canonical path; native iTunes identity uses the unsigned persistent ID. Size/mtime or system metadata revision changes invalidate cached tags. Unchanged metadata, artwork, favorites and first discovery time survive refresh. Missing files become hidden tombstones, preserving references; unreadable paths retain prior entries with a warning. Metadata extraction uses the existing bounded worker, not a new full eager pass.

The local query combines native files with completed manual downloads and automatic-cache membership using original track IDs, avoiding duplicate rows and copies. SQLite keeps paging, search and sorting; cache membership is a temporary indexed table updated only when IDs change. Older cache manifests acquire track IDs from bounded database pages without redownloading audio. Files outside the accessible roots and protected/cloud-only items are not supported.
