# Grin Wallet iOS

A non-custodial iOS wallet for the [Grin](https://grin.mw) cryptocurrency, built on Mimblewimble — one of the most privacy-preserving, scalable blockchain protocols available.

> **Disclaimer:** This software is provided as-is for educational and experimental purposes. It comes with no warranty of any kind. Use at your own risk. The authors accept no liability for lost funds or any other damages arising from the use of this software.

## Features

- **Send & Receive** — Create, sign, and finalise Grin transactions via slatepack
- **Nearby Transfers** — Peer-to-peer transfers over local WiFi/Bluetooth using MultipeerConnectivity, no internet required
- **Transaction History** — View transaction status, details, and kernel lookups
- **Output Management** — Inspect UTXOs and consolidate outputs
- **Wallet Security** — Biometric unlock and Keychain-backed password storage
- **Node Connectivity** — Connect to a Grin node with sync status monitoring
- **Scan & Repair** — Built-in wallet integrity tool
- **watchOS Companion** — Balance updates pushed to Apple Watch via WatchConnectivity

## Requirements

- iOS 17.0+
- Xcode 16+
- Swift 5.0

The wallet backend is a Rust FFI library bundled as an XCFramework (`GrinWalletFFI.xcframework`), included in the repository.

## Building

```bash
# Build for device
xcodebuild -project grin-ios.xcodeproj -scheme grin-ios -configuration Debug build

# Build for simulator
xcodebuild -project grin-ios.xcodeproj -scheme grin-ios -sdk iphonesimulator build
```

### Rebuilding the FFI Framework (optional)

If you need to rebuild the Rust FFI library from source, you'll need the Rust toolchain with iOS targets installed:

```bash
rustup target add aarch64-apple-ios

# Device only
./build-ffi.sh

# Device + simulator
./build-ffi.sh --sim
```

## Project Structure

```
grin-ios/
├── grin_iosApp.swift          # App entry point
├── ContentView.swift          # Root container
├── Views/                     # Screen-level views
├── Components/                # Reusable UI components
├── Models/                    # Data structures
└── Services/                  # Wallet, node, nearby, and keychain services

grin-wallet-ffi/               # Rust FFI source
GrinWalletFFI.xcframework/     # Compiled native library
```

## Licence

This project is licensed under the [GNU General Public License v3.0](LICENSE).
