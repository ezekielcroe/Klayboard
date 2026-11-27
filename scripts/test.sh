#!/bin/sh
# Runs Klayboard's logic tests (Package.swift) on an iOS simulator.
# Usage: scripts/test.sh ["iPhone 17"]
set -e
cd "$(dirname "$0")/.."
DEVICE="${1:-iPhone 17}"
xcodebuild test \
  -workspace .swiftpm/xcode/package.xcworkspace \
  -scheme KlayboardCore-Package \
  -destination "platform=iOS Simulator,name=$DEVICE"
