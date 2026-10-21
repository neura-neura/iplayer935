# SMB read and streaming layer

`Sources/IPSMB.h` exposes a synchronous read-only client. Call it from a background queue: libsmb2's synchronous operations block while network work completes. Each file is opened with `O_RDONLY`; the wrapper has no write, create, rename, or delete entry points. Method input paths are relative to the configured `root`; listed entries return share-relative paths including that root. Components containing `..`, `:` or backslashes are rejected.

`Sources/IPHTTPServer.h` provides the optional AVPlayer bridge. It binds only to `127.0.0.1` on an OS-assigned port, serves only its returned audio URL, and streams requested byte ranges through `IPSMB` in 64 KiB blocks. It supplies a matching MIME type for common audio extensions and does not stage a complete copy of the media file. Call `stop` when playback no longer needs the URL.

## Pinned library and license

The vendored source is the upstream `libsmb2-6.2` tag, resolved to commit `d67e213a5c4e7e4969fd81f0b95e4ca5831fbba1` in `Vendor/libsmb2`. Upstream describes libsmb2 as an SMB2/SMB3 userspace client with synchronous and asynchronous APIs, and licenses the client library under LGPL 2.1; preserve the included `COPYING` and `LICENCE-LGPL-2.1.txt` files when distributing it. See the [upstream project README](https://github.com/sahlberg/libsmb2/tree/d67e213a5c4e7e4969fd81f0b95e4ca5831fbba1) and [public API header](https://github.com/sahlberg/libsmb2/blob/d67e213a5c4e7e4969fd81f0b95e4ca5831fbba1/include/smb2/libsmb2.h).

The wrapper uses upstream's `smb2_connect_share`, `smb2_opendir`/`smb2_readdir`, `smb2_open`, `smb2_pread`, `smb2_stat`, and `smb2_set_timeout` APIs. Its 20-second command timeout and `SMB2_VERSION_ANY` negotiation allow the server to select an SMB2 or SMB3 dialect. Authentication is explicitly set to NTLMSSP; libsmb2's built-in NTLMSSP implementation avoids platform Kerberos dependencies.

## Build requirements

Build the C library for the app's iOS 9 armv7 target and add its static archive to the app target. Include `Vendor/libsmb2/include` for the Objective-C wrapper and provide the generated `config.h` include directory required by upstream C sources. The upstream CMake source list is in `Vendor/libsmb2/lib/CMakeLists.txt`; for this iOS use, build its `smb2` target with GSSAPI/Kerberos disabled (`ENABLE_GSSAPI=OFF`, `ENABLE_LIBKRB5=OFF`) so it uses the builtin NTLMSSP implementation. Use the iOS SDK and armv7 compiler/linker settings for every C source; link the resulting archive and the system networking libraries needed by the Apple toolchain. No OpenSSL dependency is needed because libsmb2 includes its crypto implementations. Add `Sources/IPSMB.m` and, when AVPlayer byte-range streaming is desired, `Sources/IPHTTPServer.m` to the Objective-C app target.

The upstream CMake project has no checked-in generated `config.h`; its configure checks produce it in the build directory. This wrapper source has not changed the app's build scripts. Ensure the target enables ARC or otherwise performs equivalent Objective-C object management.
