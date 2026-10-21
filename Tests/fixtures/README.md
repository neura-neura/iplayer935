Synthetic 7 second mono sine-tone fixtures, generated locally for decoder and seek tests.
No commercial music or user media is included.

`long-tone.flac` is a synthetic 240-second mono sine used to verify near-tail seeking over the file-backed SMB test double. It has no explicit seek table, covering the sequential decode fallback.

Generation (FFmpeg CLI, codecs available in host installation):
ffmpeg -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=7' -c:a flac tone.flac
ffmpeg -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=7' -c:a libvorbis tone.ogg
ffmpeg -f lavfi -i 'sine=frequency=440:sample_rate=44100:duration=7' -c:a libopus tone.opus


`tone.mp3` is a synthetic 2-second 880Hz sine at64kbps, used to verify native AVFoundation opening of cached local MP3 and typed hard links. It is included in the silent on-device asset check; no audio is played by that check.
Generation: ffmpeg -f lavfi -i 'sine=frequency=880:duration=2' -c:a libmp3lame -b:a 64k tone.mp3
