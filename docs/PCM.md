# Unsupported audio format streaming

`IPPCMServer` decodes FLAC, Vorbis, and Opus with the bundled FFmpeg decoders. Starting with build11, `IPPCMPlayer` sends signed 16-bit PCM directly to AudioQueue through three bounded buffers. Decoding and SMB reads run on a serial background queue. A song is never materialized in a complete local file. The older WAV HTTP endpoint remains available for regression tests; production software-codec playback no longer uses it.

The output retains the source sample rate and mono layout for mono sources; other layouts are mixed to stereo. WAV length accounts for codec priming and trailing padding so the advertised byte range matches decoded PCM.

Vorbis and Opus seek requests reopen the decoder and decode forward from the beginning to preserve sample-exact output. Native FLAC uses the bounded byte-probe path described under build23, with sequential decoding as a fallback. FFmpeg 4.4 timestamp-based FLAC binary seeking remains disabled because it can crash even with an index. All paths keep memory bounded and run on the decoder’s serial background queue.

Host tests use synthetic seven-second sine fixtures in `Tests/fixtures` and compare deep byte ranges against a full decode for each format. A 240-second FLAC fixture exercises near-tail range seeks through a file-backed IPSMB test double. `Tests/run-pcm-tests.sh` builds against the native FFmpeg archives under `build/codecs/macos-arm64`; `Tests/run-pcm-avfoundation-tests.sh` checks streamed and local WAV asset playability and duration.

## Direct SMB input (build10)

Software-decoded network tracks use FFmpeg custom AVIO callbacks backed by the read-only IPSMB client. Compressed input no longer passes through a second loopback HTTP server. Reads are capped at 64 KiB and byte seeks update the logical SMB offset; file size is exposed through AVSEEK_SIZE. Native AVPlayer formats retain their original direct HTTP bridge. WAV output to AVPlayer remains local HTTP. `diagnosticSnapshot` reports decoder metadata and the last eight request summaries with numeric byte ranges, status, elapsed time, byte count, and error code; it contains no source URL or credentials.

Build11 reopens and decodes forward for every FLAC seek, because the FFmpeg4.4 binary-seek crash also occurred with an index present. Deep seeks may be slower; sequential startup does not read to the end. A240-second synthetic FLAC is tested through the mock SMB callbacks near EOF.

## AudioQueue output (build11)

Build10 hardware diagnostics showed AVPlayer opening the initial PCM range, then requesting the WAV tail and receiving no audio bytes. The user reported NSURLErrorDomain -1 with underlying -1005. Direct AudioQueue output removes these HTTP probes and starts with sequential decoding. MP3/M4A keep the existing AVPlayer path. Player UI and lock-screen controls use common duration, elapsed, and playing properties for both outputs. The silent on-device codec check now tests the direct decoder API, without an HTTP WAV asset. Real playback still requires confirmation on the iPod.

`tests/run-pcm-player-tests.sh` uses a silent AudioQueue test double with the real player/decoder to verify prefill, refill during pause, resume, draining every queued buffer before EOF, and disposal for all three codecs. This does not validate physical audio output.

## Metadata (build12)

Decoder preparation copies standard text tags from container/audio-stream dictionaries and a bounded attached picture. `IPPCMPlayer.metadata` exposes the result after startup. `IPStore` downsizes artwork on its persistence queue and merges only metadata fields into the selected track, preserving favorites and existing fields when tags are absent. `decoded-metadata.json` persists the small override map; playback does not freeze or rewrite the whole library. The FLAC fixture `tagged.flac` verifies UTF-8 text, track-number parsing, and attached-picture extraction.


## Interactive seeking (build23)

Native FLAC seeks use at most twelve interpolated byte probes through the existing seekable AVIO input, then decode forward from a preceding frame to the exact requested sample. The parser’s next-frame offset minus packet size supplies the real frame position after a byte seek; packet.pos alone is unreliable here. This bypasses FFmpeg’s unsafe timestamp binary-search route. Short prefix seeks, unsupported inputs, or failed probes retain sequential fallback. Compressed reads remain capped at64KiB; no full audio file or PCM cache is created for seeking.

IPPCMPlayer tracks requested playback separately from actual AudioQueue activity. Generation checks discard stale seek jobs; rapid seeks retain the latest target and resume intent, while pause/play during seeking updates that intent. Stopping invalidates pending work. The UI shows «Buscando…», and automatic crossfade cannot start during a seek.

Tests/run-flac-seek-tests.sh compares exact PCM samples at forward/backward targets for local and SMB-stub input, including a240-second fixture. Deep seeks verify bounded probe counts and fewer source bytes than a sequential scan. Additional runs cover tagged FLAC and stereo24-bit audio with changing compression. AudioQueue simulation covers consecutive seeks, pause/play during a seek, and stop during a seek for FLAC, Vorbis and Opus. These host checks do not measure physical iPod timing or audio output.
