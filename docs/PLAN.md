# Keyline development plan

Keyline is a native macOS client for Outline access keys. It matches the features of the
official Outline client (OutlineFoundation/outline-apps) and adds launch at login and
split tunneling. It ships as a Developer ID–signed, notarized DMG with Sparkle updates
from GitHub Releases.

## Decisions

| Topic | Decision |
|---|---|
| Name and IDs | Keyline. App `ca.pulsbeat.keyline`; extension `ca.pulsbeat.keyline.tunnel`; app group `49DY4CP2B4.group.ca.pulsbeat.keyline`; team Pulsbeat Media Inc. (`49DY4CP2B4`) |
| Minimum macOS | 12 Monterey. 11 is ruled out because the Go core needs Go 1.25, which requires macOS 12. |
| Language | Swift (Swift 5 mode). The only Objective-C is the headers gomobile generates. |
| UI | SwiftUI main window plus an AppKit menu bar item (`MenuBarExtra` needs macOS 13) |
| VPN | NetworkExtension packet tunnel in a **system extension**, which Developer ID distribution requires |
| Tunnel core | Upstream Go core (`client/go`, built on outline-sdk), via `gomobile bind -target=macos`. Upstream is a submodule pinned to a commit on `main`. |
| Distribution | DMG only, signed with Developer ID, notarized and stapled. No Mac App Store build for now. |
| Updates | Sparkle 2, with the appcast and DMGs on GitHub Releases |
| Crash reports | MetricKit. Reports stay on the Mac until the user chooses "Send report", which opens a prefilled GitHub issue. |
| Languages | English and Russian, imported from upstream's `messages/en.json` and `ru.json` |
| Beyond upstream | Launch at login. Route- and domain-based split tunneling with a "bypass local network" switch (per-app routing later). A "Stop VPN when quitting" setting, off by default; quitting while connected warns that the VPN stays on. |
| Project | Checked-in `Keyline.xcodeproj`. Scripts are bash. |
| License | Apache-2.0, open source. NOTICE credits Outline Foundation/Jigsaw; no Outline branding. |

## Architecture

```
Keyline.app (sandboxed, hardened runtime)
├─ SwiftUI window: server list, add-key sheet, settings, about/licenses
├─ NSStatusItem menu: status, connect/disconnect, server picker, open, quit
└─ AppCore
   ├─ AccessKeyParser / DynamicKeyFetcher ──► Go: InvokeMethod(ParseTunnelConfig, FetchResource)
   ├─ ServerStore (servers.json metadata + access keys in the Keychain), SettingsStore
   ├─ ClipboardWatcher, URL scheme handler (ss://, ssconf://)
   ├─ ErrorMapper (Go PlatformError JSON → localized message)
   ├─ SystemExtensionManager (activate / replace / deactivate)
   ├─ TunnelController (NETunnelProviderManager, on-demand, status, last error)
   ├─ LoginItemController (SMAppService on 13+, helper app on 12)
   └─ DiagnosticsStore (MetricKit payloads → GitHub issue)
          │ providerConfiguration {id, name, transport, splitTunnel}   ▲ status + app messages
          ▼                                                             │
ca.pulsbeat.keyline.tunnel.systemextension (runs as root)
└─ PacketTunnelProvider (Swift port of upstream)
   ├─ Go client + tun2socks; packet flow ⇄ Go device
   ├─ routes (default or split), fake DNS 169.254.113.53, network-change handling
   └─ Go: outline-sdk (Shadowsocks, WebSocket, prefix, multi-hop, …) + lwIP
```

### Notes on the macOS 12 baseline
- **Menu bar:** `NSStatusItem` instead of `MenuBarExtra`.
- **Last tunnel error:** `fetchLastDisconnectError` on macOS 13+. On 12 the app asks the extension over `sendProviderMessage`, as upstream does.
- **Launch at login:** `SMAppService.mainApp` on 13+. On 12, a small LoginItem helper app in `Contents/Library/LoginItems`, enabled with `SMLoginItemSetEnabled`.
- **SwiftUI:** `ObservableObject` instead of `@Observable`, and `NavigationView` instead of `NavigationSplitView`.
- **Approval screen:** extension approval is in System Preferences → Security & Privacy on 12, Privacy & Security on 13–14, and Login Items & Extensions on 15+. The onboarding guide covers all three.

## Feature parity

| # | Feature | Upstream source | Keyline |
|---|---|---|---|
| 1 | `ss://` keys (name from `#fragment`, `outline=1`, prefix) | `client/web/app/outline_server_repository/config.ts`, `client/go/outline/parse.go` | Go `ParseTunnelConfig` |
| 2 | Dynamic `ssconf://`/`https://` keys, fetched on every connect, provider error messages | `server.ts`, `client/go/outline/fetch.go` | Go `FetchResource` |
| 3 | YAML/JSON transports: shadowsocks + prefix, websocket, first-supported, iptable, multi-hop, reporter | `client/go/outline/configregistry/`, `client/config.md` | Included in the Go core |
| 4 | Refuse proxyless (`DIRECT`) configs | `server.ts` | Same check |
| 5 | Server list: add, rename, forget with undo | `outline_server_repository/index.ts` | SwiftUI list + undo |
| 6 | Connect/disconnect, status, one active tunnel, switching servers | `OutlineAppleLib/Sources/OutlineTunnel/OutlineVpn.swift` | `TunnelController` |
| 7 | Auto-connect (on-demand rule) + explainer | `OutlineVpn.swift`, auto-connect dialog | Same |
| 8 | Tunnel subnet choice, excluded LAN routes, fake DNS, network changes | `OutlineLib/VpnExtension/Sources/PacketTunnelProvider.*` | Swift port |
| 9 | Error codes → messages, details dialog | `client/go/outline/platerrors/`, `client/web/model/platform_error.ts` | `ErrorMapper` + details sheet |
| 10 | `ss`/`ssconf` URL schemes | `Outline-Info.plist`, `url_interceptor.ts` | `CFBundleURLTypes` (done) + handler |
| 11 | Clipboard key detection when the app becomes active | `client/web/app/clipboard.ts` | `NSPasteboard` check |
| 12 | Privacy acknowledgement on first run | privacy dialog | First-run sheet |
| 13 | Appearance (light/dark/system) | appearance view | Setting |
| 14 | Languages | `client/web/messages/*.json` | English + Russian String Catalog |
| 15 | Menu bar item | `AppKitBridge/StatusItemController.swift` | `NSStatusItem` + server picker |
| 16 | Stop VPN on quit | `OutlinePlugin.swift` | Setting, off by default, with a warning on quit |
| 17 | About, licenses | about/licenses views | Bundled license list |
| 18 | Contact form, Sentry | contact view, Sentry logger | Replaced by MetricKit + GitHub issues |
| 19 | Erase per-server data on forget | `EraseServiceStorage` in `method_channel.go` | Message to the extension |
| — | Launch at login | not upstream | `LoginItemController` |
| — | Split tunneling | not upstream | See below |

### Split tunneling (v1)
- **Modes:**
  - *Exclude*: everything goes through the VPN except the listed IPs, CIDRs and domains.
  - *Include*: only the listed destinations go through the VPN.
- **Domains:** the extension resolves them when the tunnel starts and again periodically, then turns the addresses into routes. Domains whose IPs change often (CDNs) may leak or miss, and the settings screen says so.
- **Bypass local network:** a switch, on by default, that controls upstream's LAN exclusions.
- The fake DNS address always stays routed into the tunnel, so name resolution keeps working in include mode.
- The rules travel to the extension in `providerConfiguration` and are re-applied on network changes.
- **Per-app routing** needs a transparent proxy provider. It's out of scope for v1.

## Data and privacy
- **Access keys** are secrets. Each one is a generic-password item in the user's Keychain, keyed by server UUID.
- **Server metadata** goes in `~/Library/Application Support/ca.pulsbeat.keyline/servers.json`. **Settings** go in `UserDefaults`.
- The extension runs as root and can't read the user's Keychain. It receives only the resolved transport for the active server, through `providerConfiguration`, as upstream does. This is needed so on-demand and boot-time connects work without the app running.
- **MetricKit:** payloads are stored on the Mac and nothing is sent automatically.
  - "Send report" opens a GitHub issue with the crash summary. Users can review it before submitting.
  - It's unverified whether MetricKit delivers the extension's crashes to the extension itself. If not, the extension writes a breadcrumb file in the app group container.

## Building and releasing
- **Go core:** `core/build-xcframework.sh` builds pinned gomobile and runs `gomobile bind -target=macos` with Go 1.25.14 and `MACOSX_DEPLOYMENT_TARGET=12.0`. The output is a static, universal (arm64 + x86_64) `build/core/Tun2socks.xcframework` that both targets link.
- **Signing:**
  - certificate: Developer ID Application
  - Developer ID provisioning profiles for the app (Network Extensions + System Extension capabilities, app group) and the extension (Network Extensions, app group)
  - hardened runtime
- **Release script (`scripts/`, bash):**
  1. `xcodebuild archive` and `-exportArchive` with the `developer-id` method
  2. `create-dmg`
  3. `codesign` the DMG
  4. `xcrun notarytool submit --wait`
  5. `xcrun stapler staple`
  6. check with `spctl`
- **Sparkle 2:**
  - EdDSA-signed appcast on GitHub Releases.
  - The sandboxed app uses Sparkle's installer XPC service.
  - Each release raises the extension's `CFBundleVersion`, so the activation request replaces the old extension.
- **CI (GitHub Actions, macOS runner):**
  - On every PR: build the core (cached by submodule commit), run `go test`, and build and test unsigned.
  - On a tag: sign, notarize and publish the DMG and appcast.

## Testing
- **Unit tests:**
  - key parsing, using upstream's fixtures (`config.spec.ts`, `parse_test.go`)
  - ServerStore with a fake Keychain
  - ErrorMapper covering every error code
  - subnet selection and split-tunnel route building
- **Go:** upstream's tests run on every submodule bump.
- **Manual or self-hosted integration**, since CI runners can't approve system extensions:
  - against a local `outline-ss-server`
  - cases: static and dynamic keys, prefix, websocket, UDP, server switching, network changes, sleep/wake, reboot with auto-connect, both split-tunnel modes, wrong password, unreachable server
  - on macOS 12, 13, 14, 15 and 26, on Intel and Apple Silicon
- **Release check:** the DMG installs on a clean VM and passes Gatekeeper offline.

## Phases

| Phase | Scope | Estimate | Status |
|---|---|---|---|
| 0. Setup | Repo, submodule, license/notice, Go core build, Xcode project with app + system extension | 2–3 days | Done |
| 1. Tunnel spike | Extension activation flow, PacketTunnelProvider port, connect with a hard-coded `ss://` key | 4–6 days | Done: connects with a real key |
| 2. AppCore | Parsing, dynamic keys, Keychain, TunnelController, errors, extension messages, tests | 5–7 days | Done: 38 unit tests, CI on every PR |
| 3. UI | Window, menu bar, onboarding/approval, dialogs, settings, URL scheme, clipboard, launch at login, quit warning | 7–9 days | |
| 4. Split tunneling | Rules model, settings UI, route building, domain re-resolution | 3–4 days | |
| 5. Localization, licenses, diagnostics | English + Russian, license list, MetricKit + GitHub issue reports | 2–3 days | |
| 6. Packaging and CI | DMG, notarization, Sparkle, GitHub Actions | 3–5 days | |
| 7. Hardening and QA | OS and hardware matrix, sleep/wake, update path, beta | 5–8 days | |

## Needed from the account holder
- **A Developer ID Application certificate.** Only Apple Distribution and Apple Development exist on this Mac.
- **Registered identifiers:**
  - App IDs `ca.pulsbeat.keyline` (Network Extensions, System Extension, App Groups) and `ca.pulsbeat.keyline.tunnel` (Network Extensions, App Groups)
  - app group `group.ca.pulsbeat.keyline`
- **Provisioning profiles:**
  - development profiles for local testing (Xcode automatic signing can create them)
  - Developer ID profiles for both IDs, for releases
- **An App Store Connect API key** for `notarytool`, stored as CI secrets later.
