#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# Builds `nectarlink-ffi` for iOS device and Simulator targets, generates
# the Swift UniFFI bindings into `ios/NectarLink/Generated/`, and packages
# the static libraries + C headers into `ios/Frameworks/NectarLinkCore.xcframework`.
#
# Usage:
#   ./ios/scripts/build-rust-xcframework.sh [--release] [--sim-only]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${IOS_DIR}/.." && pwd)"

PROFILE="debug"
CARGO_FLAG=""
SIM_ONLY=0

for arg in "$@"; do
  case "${arg}" in
    --release)
      PROFILE="release"
      CARGO_FLAG="--release"
      ;;
    --sim-only)
      SIM_ONLY=1
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      echo "Usage: $0 [--release] [--sim-only]" >&2
      exit 1
      ;;
  esac
done

export IPHONEOS_DEPLOYMENT_TARGET="17.0"

echo "==> Generating design tokens (Kotlin, QML, Swift)..."
(cd "${REPO_ROOT}" && cargo run -p xtask -- tokens)

DEVICE_TARGET="aarch64-apple-ios"
SIM_ARM64_TARGET="aarch64-apple-ios-sim"
SIM_X64_TARGET="x86_64-apple-ios"

echo "==> Ensuring Rust iOS targets are installed..."
if [[ "${SIM_ONLY}" -eq 0 ]]; then
  rustup target add "${DEVICE_TARGET}" "${SIM_ARM64_TARGET}" "${SIM_X64_TARGET}"
else
  rustup target add "${SIM_ARM64_TARGET}"
fi

if [[ "${SIM_ONLY}" -eq 0 ]]; then
  echo "==> Building nectarlink-ffi for iOS Device (${DEVICE_TARGET}, ${PROFILE})..."
  (cd "${REPO_ROOT}" && cargo build -p nectarlink-ffi --target "${DEVICE_TARGET}" ${CARGO_FLAG})
fi

echo "==> Building nectarlink-ffi for iOS Simulator (${SIM_ARM64_TARGET}, ${PROFILE})..."
(cd "${REPO_ROOT}" && cargo build -p nectarlink-ffi --target "${SIM_ARM64_TARGET}" ${CARGO_FLAG})

if [[ "${SIM_ONLY}" -eq 0 ]]; then
  echo "==> Building nectarlink-ffi for iOS Simulator Intel (${SIM_X64_TARGET}, ${PROFILE})..."
  (cd "${REPO_ROOT}" && cargo build -p nectarlink-ffi --target "${SIM_X64_TARGET}" ${CARGO_FLAG})
fi

GEN_DIR="${IOS_DIR}/NectarLink/Generated"
mkdir -p "${GEN_DIR}"

LIB_FOR_BINDGEN="${REPO_ROOT}/target/${SIM_ARM64_TARGET}/${PROFILE}/libnectarlink_ffi.a"

echo "==> Generating UniFFI Swift bindings into ${GEN_DIR}..."
(cd "${REPO_ROOT}" && cargo run -p nectarlink-ffi --features bindgen --bin uniffi-bindgen -- \
  generate \
  --library "${LIB_FOR_BINDGEN}" \
  --language swift \
  --out-dir "${GEN_DIR}")

HEADERS_STAGE="${IOS_DIR}/build/Headers"
SIM_FAT_DIR="${IOS_DIR}/build/sim-universal"
XCFRAMEWORK_OUT="${IOS_DIR}/Frameworks/NectarLinkCore.xcframework"

rm -rf "${HEADERS_STAGE}" "${SIM_FAT_DIR}" "${XCFRAMEWORK_OUT}"
mkdir -p "${HEADERS_STAGE}" "${SIM_FAT_DIR}" "${IOS_DIR}/Frameworks"

cp "${GEN_DIR}/nectarlink_ffiFFI.h" "${HEADERS_STAGE}/nectarlink_ffiFFI.h"
cp "${GEN_DIR}/nectarlink_ffiFFI.modulemap" "${HEADERS_STAGE}/module.modulemap"

if [[ "${SIM_ONLY}" -eq 0 ]]; then
  echo "==> Creating universal Simulator library with lipo..."
  lipo -create \
    "${REPO_ROOT}/target/${SIM_ARM64_TARGET}/${PROFILE}/libnectarlink_ffi.a" \
    "${REPO_ROOT}/target/${SIM_X64_TARGET}/${PROFILE}/libnectarlink_ffi.a" \
    -output "${SIM_FAT_DIR}/libnectarlink_ffi.a"

  echo "==> Packaging ${XCFRAMEWORK_OUT}..."
  xcodebuild -create-xcframework \
    -library "${REPO_ROOT}/target/${DEVICE_TARGET}/${PROFILE}/libnectarlink_ffi.a" \
    -headers "${HEADERS_STAGE}" \
    -library "${SIM_FAT_DIR}/libnectarlink_ffi.a" \
    -headers "${HEADERS_STAGE}" \
    -output "${XCFRAMEWORK_OUT}"
else
  echo "==> Packaging simulator-only ${XCFRAMEWORK_OUT}..."
  xcodebuild -create-xcframework \
    -library "${REPO_ROOT}/target/${SIM_ARM64_TARGET}/${PROFILE}/libnectarlink_ffi.a" \
    -headers "${HEADERS_STAGE}" \
    -output "${XCFRAMEWORK_OUT}"
fi

echo "==> Done! NectarLinkCore.xcframework and Swift bindings are ready."
