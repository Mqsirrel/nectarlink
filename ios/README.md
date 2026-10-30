# NectarLink for iPhone & iPad (`ios/`)

Native iOS and iPadOS client for **NectarLink**, built with Swift, SwiftUI, and the shared Rust `nectarlink-core` / `nectarlink-ffi` workspace via Mozilla UniFFI.

## Architecture

- **Shared Rust Core (`core/nectarlink-core` & `core/nectarlink-ffi`)**:
  - End-to-end encrypted QUIC networking (`iroh`), mDNS discovery, QR/SAS pairing, persistent send queue, LocalSend v2.1 compatibility, encrypted clipboard history, and cross-device timeline.
  - First-class `"ios"` OS role and capability matrix in `core/nectarlink-core/src/features.rs`.
  - Compiled as a static library for `aarch64-apple-ios`, `aarch64-apple-ios-sim`, and `x86_64-apple-ios` and packaged into `ios/Frameworks/NectarLinkFFI.xcframework` by [`ios/scripts/build-rust-xcframework.sh`](scripts/build-rust-xcframework.sh).
- **Generated Bindings & Design Tokens**:
  - [`ios/NectarLink/Generated/nectarlink_ffi.swift`](NectarLink/Generated/nectarlink_ffi.swift), [`nectarlink_ffiFFI.h`](NectarLink/Generated/nectarlink_ffiFFI.h), and [`nectarlink_ffiFFI.modulemap`](NectarLink/Generated/nectarlink_ffiFFI.modulemap) — generated from `libnectarlink_ffi` via `uniffi-bindgen`.
  - [`ios/NectarLink/UI/Theme/Tokens.swift`](NectarLink/UI/Theme/Tokens.swift) — generated from `docs/design/tokens.json` via `cargo xtask tokens`.
- **Hardware-Accelerated iOS Services (`ios/NectarLink/Services/`)**:
  - **Keychain Key Protector** ([`KeychainKeyProtector.swift`](NectarLink/Core/KeychainKeyProtector.swift)): 256-bit ChaCha20-Poly1305 master key stored in iOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) to wrap the device's Ed25519 identity and SQLite database keys.
  - **Camera as PC Webcam** ([`WebcamStreamer.swift`](NectarLink/Services/WebcamStreamer.swift) & [`VideoToolboxEncoder.swift`](NectarLink/Services/VideoToolboxEncoder.swift)): `AVCaptureSession` + hardware `VTCompressionSession` (H.264 / HEVC Annex-B) with 720p/1080p/4K presets, zoom, lens switch, and torch control.
  - **Screen Mirroring** ([`ScreenMirrorStreamer.swift`](NectarLink/Services/ScreenMirrorStreamer.swift) & [`PcMirrorView.swift`](NectarLink/UI/Remote/PcMirrorView.swift)): `RPScreenRecorder` to stream the iPhone screen + audio to the PC, and hardware `VTDecompressionSession` to view and touch-control the PC screen on iPhone.
  - **Continuity Camera & Document Scanner** ([`ContinuityCameraManager.swift`](NectarLink/Services/ContinuityCameraManager.swift)): Native camera capture and `VNDocumentCameraViewController` / `Vision` perspective-corrected document scanning directly into the PC.
  - **Audio & Voice** ([`MicStreamer.swift`](NectarLink/Services/MicStreamer.swift), [`PcSpeakerPlayer.swift`](NectarLink/Services/PcSpeakerPlayer.swift), [`VoiceRecorder.swift`](NectarLink/Services/VoiceRecorder.swift)): 48 kHz PCM wireless PC microphone, live PC speaker relay on iPhone, and AAC `.m4a` voice recorder with timestamp markers.
  - **Photos, Contacts, Calls, Clipboard & Storage**: [`IosPhotos.swift`](NectarLink/Services/IosPhotos.swift) (`PHPhotoLibrary`), [`IosContacts.swift`](NectarLink/Services/IosContacts.swift) (`CNContactStore`), [`IosCalls.swift`](NectarLink/Services/IosCalls.swift) (`CXCallObserver` + `tel://`), [`IosClipboard.swift`](NectarLink/Services/IosClipboard.swift) (`UIPasteboard`), and [`IosStorage.swift`](NectarLink/Services/IosStorage.swift) (`Documents/NectarLink` + App Group container).
- **System Share Sheet Extension (`ios/NectarLinkShareExtension/`)**:
  - [`ShareViewController.swift`](NectarLinkShareExtension/ShareViewController.swift) stages shared files, photos, videos, URLs, and text into `group.app.nectarlink` and hands off to the main app.

## Building on macOS with Xcode

### 1. Prerequisites

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
brew install xcodegen
```

### 2. Build the Rust XCFramework & Refresh Swift Bindings

From the repository root:

```bash
./ios/scripts/build-rust-xcframework.sh --release
cargo run -p xtask -- tokens
```

### 3. Generate the Xcode Project & Run

```bash
cd ios
xcodegen generate
open NectarLink.xcodeproj
```

In Xcode:
1. Select the **NectarLink** scheme.
2. Under **Signing & Capabilities**, select your Apple Development Team for both `NectarLink` and `NectarLinkShareExtension` targets.
3. Build and run on your iPhone or iOS Simulator (`Cmd + R`).
