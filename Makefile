# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

.PHONY: test generate build check

test:
	swift test

generate:
	/opt/homebrew/bin/xcodegen generate

build: generate
	xcodebuild -project PhotoSuite.xcodeproj -scheme PhotoSuite -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/XcodeDerivedData CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build

check: test build
