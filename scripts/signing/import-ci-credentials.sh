#!/usr/bin/env bash
set -euo pipefail

: "${APPLE_DEVELOPMENT_CERT_BASE64:?missing APPLE_DEVELOPMENT_CERT_BASE64}"
: "${CERTIFICATE_SECRET:?missing CERTIFICATE_SECRET}"
: "${KEYCHAIN_SECRET:?missing KEYCHAIN_SECRET}"
: "${SWIFTERKIT_DEXT_PROFILE_BASE64:?missing SWIFTERKIT_DEXT_PROFILE_BASE64}"
: "${DEVELOPMENT_TEAM:?missing DEVELOPMENT_TEAM}"
: "${DEXT_BUNDLE_IDENTIFIER:?missing DEXT_BUNDLE_IDENTIFIER}"

certificate_path="$RUNNER_TEMP/apple-development.p12"
profile_path="$RUNNER_TEMP/SwifterKitRuntime.provisionprofile"
keychain_path="$RUNNER_TEMP/swifterkit-signing.keychain-db"
profiles_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

printf '%s' "$APPLE_DEVELOPMENT_CERT_BASE64" | base64 --decode >"$certificate_path"
printf '%s' "$SWIFTERKIT_DEXT_PROFILE_BASE64" | base64 --decode >"$profile_path"

security create-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain_path"
security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"
security import "$certificate_path" -f pkcs12 -k "$keychain_path" \
	-P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
	-k "$KEYCHAIN_SECRET" "$keychain_path"

profile_plist="$RUNNER_TEMP/SwifterKitRuntime-profile.plist"
security cms -D -i "$profile_path" >"$profile_plist"
profile_uuid="$(plutil -extract UUID raw "$profile_plist")"
profile_name="$(plutil -extract Name raw "$profile_plist")"
profile_team="$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$profile_plist")"
profile_app_id="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$profile_plist")"
profile_driverkit="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.driverkit" "$profile_plist")"
expected_app_id="$DEVELOPMENT_TEAM.$DEXT_BUNDLE_IDENTIFIER"
if [[ "$profile_team" != "$DEVELOPMENT_TEAM" || "$profile_app_id" != "$expected_app_id" || "$profile_driverkit" != "true" ]]; then
	echo "ERROR: DriverKit profile does not match the configured team, bundle identifier, or entitlement."
	exit 1
fi
mkdir -p "$profiles_dir"
cp "$profile_path" "$profiles_dir/$profile_uuid.provisionprofile"

echo "profile-name=$profile_name" >>"$GITHUB_OUTPUT"
echo "keychain-path=$keychain_path" >>"$GITHUB_OUTPUT"
