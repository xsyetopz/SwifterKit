#!/usr/bin/env bash
set -euo pipefail

xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swiftlint lint --strict
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors

swift package dump-symbol-graph --minimum-access-level public
symbol_graph_dir="$(find .build -type d -name symbolgraph -print -quit)"
test -n "$symbol_graph_dir"
xcrun docc convert Sources/SwifterKit/SwifterKit.docc \
	--additional-symbol-graph-dir "$symbol_graph_dir" \
	--fallback-display-name SwifterKit \
	--fallback-bundle-identifier com.xsyetopz.SwifterKit \
	--fallback-bundle-version 1 \
	--output-path .build/SwifterKit.doccarchive \
	--warnings-as-errors

native_project="Sources/SwifterKit/Resources/DriverKitExtension/SwifterKitRuntime.xcodeproj"
native_sources="Sources/SwifterKit/Resources/DriverKitExtension/Sources"
xcrun clang-format --dry-run --Werror "$native_sources"/*.{cpp,h,iig}

derived_data="${RUNNER_TEMP:-.build}/SwifterKitDriverKitDerived"
xcodebuild -quiet \
	-project "$native_project" \
	-scheme SwifterKitRuntime \
	-configuration Debug \
	-sdk driverkit \
	-derivedDataPath "$derived_data" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	DEVELOPMENT_TEAM= \
	"ARCHS=arm64 x86_64" \
	ONLY_ACTIVE_ARCH=NO \
	GCC_TREAT_WARNINGS_AS_ERRORS=YES \
	build

native_binary="$derived_data/Build/Products/Debug-driverkit/SwifterKitRuntime.dext/SwifterKitRuntime"
test -f "$native_binary"
native_architectures="$(lipo -archs "$native_binary")"
if [[ " $native_architectures " != *" arm64 "* || " $native_architectures " != *" x86_64 "* ]]; then
	echo "ERROR: expected arm64 and x86_64 DriverKit slices, found: $native_architectures"
	exit 1
fi

analysis_derived_data="${derived_data}-Analyze"
xcodebuild -quiet \
	-project "$native_project" \
	-scheme SwifterKitRuntime \
	-configuration Debug \
	-sdk driverkit \
	-derivedDataPath "$analysis_derived_data" \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	DEVELOPMENT_TEAM= \
	ARCHS=arm64 \
	ONLY_ACTIVE_ARCH=YES \
	GCC_TREAT_WARNINGS_AS_ERRORS=YES \
	analyze

./scripts/ci/validate-native.sh "$derived_data"

plutil -lint \
	Sources/SwifterKit/Resources/DriverKitExtension/Info.plist \
	Sources/SwifterKit/Resources/DriverKitExtension/SwifterKitRuntime.entitlements

./scripts/ci/audit_loc.py
