#!/bin/bash
# Build the Grin Wallet FFI library for iOS
# Run this from the ios/ directory: ./build-ffi.sh
#
# By default, builds for iOS device only.
# Pass --sim to also build for the iOS simulator.

set -e

# Minimum iOS deployment target — must match your Xcode project setting.
export IPHONEOS_DEPLOYMENT_TARGET=17.0

FFI_DIR="grin-wallet-ffi"
XCFW="GrinWalletFFI.xcframework"
HEADER_DIR="${FFI_DIR}/include"

BUILD_SIM=false
if [[ "$1" == "--sim" ]]; then
    BUILD_SIM=true
fi

echo "🔨 Building for iOS device (aarch64-apple-ios)..."
cd "$FFI_DIR"
cargo build --release --target aarch64-apple-ios

if $BUILD_SIM; then
    echo "🔨 Building for iOS simulator (aarch64-apple-ios-sim)..."
    # The gcc 0.3 crate (used by liblmdb-sys) hardcodes aarch64 → iOS device
    # and injects the wrong -isysroot and -miphoneos-version-min flags.
    # This wrapper filters those out and forces the simulator SDK instead.
    SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
    SIM_CC_WRAPPER="$(pwd)/.sim-cc-wrapper.sh"
    cat > "$SIM_CC_WRAPPER" << 'WRAPPER'
#!/bin/bash
# Filter out device-only flags injected by the gcc 0.3 crate
args=()
skip_next=false
for arg in "$@"; do
    if $skip_next; then
        skip_next=false
        continue
    fi
    case "$arg" in
        -miphoneos-version-min=*) continue ;;
        -isysroot)                skip_next=true; continue ;;
        --target=aarch64-apple-ios) continue ;;
        *)                        args+=("$arg") ;;
    esac
done
WRAPPER
    # Append the exec line with expanded variables (not single-quoted)
    cat >> "$SIM_CC_WRAPPER" << EXEC
exec xcrun --sdk iphonesimulator clang \\
    -target arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET}-simulator \\
    -isysroot ${SIM_SDK} \\
    "\${args[@]}"
EXEC
    chmod +x "$SIM_CC_WRAPPER"
    CC_aarch64_apple_ios_sim="$SIM_CC_WRAPPER" \
    cargo build --release --target aarch64-apple-ios-sim
    rm -f "$SIM_CC_WRAPPER"
fi

echo "📦 Creating XCFramework..."
cd -
rm -rf "$XCFW"

# Prepare headers with modulemap for xcodebuild
DEVICE_HEADERS="$(mktemp -d)"
cp "$HEADER_DIR/grin_wallet_ffi.h" "$DEVICE_HEADERS/"
cat > "$DEVICE_HEADERS/module.modulemap" << 'EOF'
module GrinWalletFFI {
    header "grin_wallet_ffi.h"
    link "grin_wallet_ffi"
    export *
}
EOF

if $BUILD_SIM; then
    SIM_HEADERS="$(mktemp -d)"
    cp "$HEADER_DIR/grin_wallet_ffi.h" "$SIM_HEADERS/"
    cat > "$SIM_HEADERS/module.modulemap" << 'EOF'
module GrinWalletFFI {
    header "grin_wallet_ffi.h"
    link "grin_wallet_ffi"
    export *
}
EOF

    xcodebuild -create-xcframework \
        -library "${FFI_DIR}/target/aarch64-apple-ios/release/libgrin_wallet_ffi.a" \
        -headers "$DEVICE_HEADERS" \
        -library "${FFI_DIR}/target/aarch64-apple-ios-sim/release/libgrin_wallet_ffi.a" \
        -headers "$SIM_HEADERS" \
        -output "$XCFW"

    rm -rf "$SIM_HEADERS"
else
    xcodebuild -create-xcframework \
        -library "${FFI_DIR}/target/aarch64-apple-ios/release/libgrin_wallet_ffi.a" \
        -headers "$DEVICE_HEADERS" \
        -output "$XCFW"
fi

rm -rf "$DEVICE_HEADERS"

echo "✅ GrinWalletFFI.xcframework built successfully"
echo ""
echo "If not already linked: Xcode → target → Frameworks → + → Add Files → select GrinWalletFFI.xcframework"
