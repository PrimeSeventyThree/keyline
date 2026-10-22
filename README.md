# Keyline

A native macOS client for Outline access keys (`ss://` and `ssconf://`), written in
Swift. The VPN runs as a NetworkExtension packet tunnel inside a system extension,
using the Go client core from [Outline](https://github.com/OutlineFoundation/outline-apps).
Keyline is distributed as a signed, notarized DMG.

Keyline is an independent project and is not affiliated with or endorsed by the
Outline Foundation or Jigsaw. See [NOTICE](NOTICE).

**Status:** early development. See [docs/PLAN.md](docs/PLAN.md).

## Requirements

- macOS 12 or later (runtime)
- Xcode 26 or later
- Go (any recent version; the build script downloads and uses the pinned Go 1.25 toolchain)

## Building

```sh
git clone --recurse-submodules git@github.com:PrimeSeventyThree/keyline.git
cd keyline
core/build-xcframework.sh     # builds build/core/Tun2socks.xcframework from the Go core
open Keyline.xcodeproj
```

To check that it compiles without signing:

```sh
xcodebuild -project Keyline.xcodeproj -scheme Keyline -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Running the tunnel needs a signed build installed in `/Applications`, because macOS
only activates system extensions from there.

## Layout

| Path | Contents |
|---|---|
| `App/` | SwiftUI app: main window and menu bar item |
| `TunnelExtension/` | Packet tunnel system extension |
| `Shared/` | Code compiled into both targets |
| `core/` | Script that builds the Go core into an xcframework |
| `third_party/outline-apps/` | Upstream Outline, pinned as a git submodule |

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
