#!/usr/bin/env bash
set -euo pipefail

environment="${SWIFTERKIT_ENV:-dev}"
env_file="${SWIFTERKIT_ENV_FILE:-.env.$environment}"
if [[ -f "$env_file" ]]; then
	set -a
	source "$env_file"
	set +a
fi

: "${DEVELOPMENT_TEAM:?missing DEVELOPMENT_TEAM}"
: "${CODESIGN_IDENTITY:?missing CODESIGN_IDENTITY}"
: "${DEXT_BUNDLE_IDENTIFIER:?missing DEXT_BUNDLE_IDENTIFIER}"
: "${DEXT_PROVISIONING_PROFILE_SPECIFIER:?missing DEXT_PROVISIONING_PROFILE_SPECIFIER}"

derived_data="${SWIFTERKIT_DERIVED_DATA:-.build/DriverKitSigned}"
other_code_sign_flags=()
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
	other_code_sign_flags=("OTHER_CODE_SIGN_FLAGS=--keychain $SIGNING_KEYCHAIN")
fi

xcodebuild -quiet \
	-project Sources/SwifterKit/Resources/DriverKitExtension/SwifterKitRuntime.xcodeproj \
	-scheme SwifterKitRuntime \
	-configuration Release \
	-sdk driverkit \
	-derivedDataPath "$derived_data" \
	DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
	PRODUCT_BUNDLE_IDENTIFIER="$DEXT_BUNDLE_IDENTIFIER" \
	CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
	PROVISIONING_PROFILE_SPECIFIER="$DEXT_PROVISIONING_PROFILE_SPECIFIER" \
	"ARCHS=arm64 x86_64" \
	ONLY_ACTIVE_ARCH=NO \
	"${other_code_sign_flags[@]}" \
	build
