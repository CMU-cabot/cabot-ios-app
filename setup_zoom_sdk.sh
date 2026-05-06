#!/usr/bin/env bash

set -euo pipefail

readonly REPO="CMU-cabot/cabot-ios-app"
readonly RELEASE_TAG="zoom-sdk-7.0.2.34511"
readonly ASSET_NAME="zoom-ios-sdk-7.0.2.34511.zip"
readonly DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${ROOT_DIR}/Vendor/Zoom"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cabot-zoom-sdk.XXXXXX")"
ARCHIVE_PATH="${TMP_DIR}/${ASSET_NAME}"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ -d "${TARGET_DIR}" ]]; then
    if [[ "${1:-}" != "--force" ]]; then
        echo "Vendor/Zoom already exists. Remove it first or run ./setup_zoom_sdk.sh --force."
        exit 1
    fi
    rm -rf "${TARGET_DIR}"
fi

mkdir -p "${ROOT_DIR}/Vendor"

echo "Downloading ${ASSET_NAME}..."
curl -fL --retry 3 --retry-delay 1 -o "${ARCHIVE_PATH}" "${DOWNLOAD_URL}"

echo "Installing Zoom SDK into Vendor/Zoom..."
unzip -q "${ARCHIVE_PATH}" -d "${ROOT_DIR}"

for path in MobileRTC.xcframework zoomcml.xcframework MobileRTCResources.bundle; do
    if [[ ! -e "${TARGET_DIR}/${path}" ]]; then
        echo "Install failed: missing ${TARGET_DIR}/${path}" >&2
        exit 1
    fi
done

echo "Zoom SDK installed successfully."
