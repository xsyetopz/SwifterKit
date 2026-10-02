#!/usr/bin/env bash
set -euo pipefail

xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swiftlint lint --strict Sources Tests Package.swift
# The generated-extension build tests keep each built tree for validate-native.sh to analyze.
generated_trees="$PWD/.build/SwifterKitGeneratedTrees"
rm -rf "$generated_trees"
SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE="$generated_trees" swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors

# Remove symbol graphs left by earlier builds or other toolchains so only this dump is found.
find .build -type d -name symbolgraph -prune -exec rm -rf {} +
swift package dump-symbol-graph --minimum-access-level public
# Built test targets add their own symbol graph; DocC accepts only the library module.
symbol_graph="$(find .build -type f -path '*/symbolgraph/SwifterKit.symbols.json' -print -quit)"
test -n "$symbol_graph"
symbol_graph_dir=".build/SwifterKitSymbolGraph"
rm -rf "$symbol_graph_dir"
mkdir -p "$symbol_graph_dir"
cp "$symbol_graph" "$symbol_graph_dir/"
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

# The checked-in project targets DriverKit 19.0 and links every family framework, including
# VideoDriverKit, so it needs the newest SDK. Newer SDKs raise their minimum (21.0 in the Xcode 27
# SDK), so build at the oldest target the selected SDK accepts.
driverkit_settings="$(xcrun --sdk driverkit --show-sdk-path)/SDKSettings.json"
driverkit_target="$(plutil -extract SupportedTargets.driverkit.MinimumDeploymentTarget raw -o - "$driverkit_settings")"
export SWIFTERKIT_DRIVERKIT_TARGET="$driverkit_target"

# The DocC coverage article must match what Apple's headers, clang's evidence from the generated
# trees, and the Swift documentation give. It names the SDKs it was generated from, so pass every
# installed DriverKit SDK; the check compares the article only when the SDKs match.
coverage_sdks=()
while IFS= read -r sdk; do
	coverage_sdks+=(--sdk "$sdk")
done < <(
	{
		xcrun --sdk driverkit --show-sdk-path
		find /Applications -maxdepth 1 -name 'Xcode*.app' -exec find \
			{}/Contents/Developer/Platforms/DriverKit.platform/Developer/SDKs \
			-maxdepth 1 -name 'DriverKit[0-9]*.sdk' \; 2>/dev/null
	} | while IFS= read -r path; do realpath "$path"; done | sort -u
)
swift run SwifterKitCoverage check "${coverage_sdks[@]}" \
	--trees "$generated_trees" \
	--article Sources/SwifterKit/SwifterKit.docc/DriverKitCoverage.md

derived_data="${RUNNER_TEMP:-.build}/SwifterKitDriverKitDerived"
# Build DriverKit with Xcode's own compilers. A `TOOLCHAINS` override, such as a swift.org
# toolchain, swaps in a clang that rejects Xcode's module flags under -Werror.
env -u TOOLCHAINS xcodebuild -quiet \
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
	DRIVERKIT_DEPLOYMENT_TARGET="$driverkit_target" \
	build

native_binary="$derived_data/Build/Products/Debug-driverkit/SwifterKitRuntime.dext/SwifterKitRuntime"
test -f "$native_binary"
native_architectures="$(lipo -archs "$native_binary")"
if [[ " $native_architectures " != *" arm64 "* || " $native_architectures " != *" x86_64 "* ]]; then
	echo "ERROR: expected arm64 and x86_64 DriverKit slices, found: $native_architectures"
	exit 1
fi

analysis_derived_data="${derived_data}-Analyze"
env -u TOOLCHAINS xcodebuild -quiet \
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
	DRIVERKIT_DEPLOYMENT_TARGET="$driverkit_target" \
	analyze

./scripts/ci/validate-native.sh "$derived_data" "$generated_trees"

plutil -lint \
	Sources/SwifterKit/Resources/DriverKitExtension/Info.plist \
	Sources/SwifterKit/Resources/DriverKitExtension/SwifterKitRuntime.entitlements

./scripts/ci/audit_loc.py
