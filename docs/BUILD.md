# Building iPlayer935 for the iPod touch 5

This project targets the 32-bit `iPod5,1` on iOS 9.3.5. The build uses the iPhoneOS 9.3 SDK from the official [theos/sdks GitHub releases](https://github.com/theos/sdks/releases); `scripts/build.sh` downloads it only if it is absent and checks SHA-256 before extraction. Current Apple ld misreads the SDK’s old universal text stubs as simulator libraries, so `scripts/prepare_legacy_sdk.py` creates a separate device-target SDK copy with current TAPI. It also adds seven standard libc exports omitted from the upstream `libSystem` stub.

Install the host tools once with Homebrew:

```sh
brew install llvm ldid libimobiledevice ideviceinstaller
```

Build the IPA:

```sh
./scripts/build.sh
```

Install an already-built IPA over USB without rebuilding:

```sh
./scripts/install.sh
```

Build, install, and request a launch through the device debug service:

```sh
./scripts/build.sh --install-and-launch
```

Both install options read `ProductType` and `ProductVersion` from the connected device and stop unless they are exactly `iPod5,1` and `9.3.5`. Installation uses `ideviceinstaller`; AppSync Unified must already be installed on the jailbroken device. `--install-and-launch` uses `idevicedebug` and requires the matching Developer Disk Image to be mounted. The script does not restore or erase the device.

The output is `deliverables/iPlayer935.ipa`. `CLANG`, `LDID`, `IDEVICEINFO`, and `IDEVICEINSTALLER` can override the corresponding tool paths. If the matching Developer Disk Image is not mounted, `--install-and-launch` installs successfully but `idevicedebug` cannot launch; open the app from the iPod home screen instead.

## Additional audio decoders

`scripts/codec-build.sh` fetches the pinned upstream FFmpeg4.4.4 release from
https://ffmpeg.org/releases/ffmpeg-4.4.4.tar.xz and verifies SHA256
`e80b380d595c809060f66f96a5d849511ef4a76a26b76eacf5778b94c3570309`.
Only FLAC/Vorbis/Opus decoding, FLAC/Ogg demuxing and file/HTTP/TCP inputs are
included. GPL, version3 and nonfree components, encoders, programs, assembly and
external codec dependencies are disabled. Four static libraries are built for
armv7/iOS9.3.5 with `-marm`, and separately arm64/macOS for host tests. Compiled
codecs and source caches live under `build/codecs` and `build/cache`; normal app
builds preserve them. No runtime external executable is installed on the iPod.

`./scripts/test-codecs.sh` checks real decoding of synthetic test fixtures.
`./Tests/run-pcm-tests.sh` exercises the local PCM HTTP bridge and range seeking.
`./scripts/source-kit.sh` packages app/dependency source, build scripts and
relinkable objects in `deliverables/iPlayer935-source.zip`. The pinned FFmpeg
source archive and LGPL notices are also in `deliverables/codec-source`.
See upstream license information: https://ffmpeg.org/legal.html.

## Release assets

Prebuilt IPA and matching source/relinking archives are distributed through [GitHub Releases](https://github.com/neura-neura/iplayer935/releases), rather than committed to Git. Download the IPA to `deliverables/iPlayer935.ipa` before using `scripts/install.sh`. The source archive contains all three README translations, dependency sources, app/SMB object files and the matching FFmpeg static libraries. The original pinned FFmpeg archive and dependency license notices also remain in the repository. Checksums accompany each release.


The local library requests read-only access to `/var/mobile/Media/` and its canonical `/private/var/mobile/Media/` alias in the ad-hoc entitlements. Actual access depends on the device jailbreak configuration; Documents and MediaPlayer provide the regular app/system library paths. No write entitlement is added.


## Separate iOS 6.1.3 target (local development)

`./scripts/build.sh --ios6` builds `deliverables/iPlayer935-iOS6.ipa`; `./scripts/install.sh --ios6` installs only onto iPod5,1 / iOS 6.1.3. The default commands continue to target iOS 9.3.5. Both use the same bundle ID so settings survive updates on the same device. The regular IPA is not overwritten by the iOS 6 build.

The legacy target defines `IP_IOS6` and force-includes `IPLegacyCompatibility.h` only for Objective-C sources. All legacy implementations and call-site branches compile out of the default target. Legacy menus use UIAlertView/UIActionSheet, search uses UISearchBar, edge navigation uses a bounded pan gesture, remote events use UIResponder, and AVPlayer gain uses an AVAudioMix. FFmpeg is rebuilt with deployment 6.1.3 in a separate `build/codecs/ios-armv7-ios6` prefix. All app/vendor objects remain ARM, not Thumb.

Legacy output, objects and license/source staging are under `build/ios6`; the stable target keeps its existing paths and version. Both IPA targets are local and unpublished during validation. Do not interpret successful installation or codec decoding as completed playback/UI validation.


Legacy database regression: run `./Tests/run-ios6-database-tests.sh` to test against the actual SQLite 3.7.13 engine on the Mac. It caches a checksum-verified public-domain amalgamation from sqlite.org under ignored build/cache. This is a host database/Store test, not an iOS UIKit emulator. The legacy app uses iOS's SQLite, with rollback journaling and deferred UI reads during bulk commits; see https://www.sqlite.org/wal.html for the pre-3.11 WAL limitation.

Legacy bulk scans prepare title sorting first. Other metadata sort indexes are created by the background query worker when first requested and retained on disk. The scan completion callback waits for its asynchronous save and propagates persistence errors; the UI reports saving progress during that phase.

Legacy player gain regression: `./Tests/run-ios6-player-gain-tests.sh` exercises the isolated audio-mix adapter against macOS AVFoundation. It verifies deferred track loading and independent deck gain state; actual legacy audio output still requires device testing.
