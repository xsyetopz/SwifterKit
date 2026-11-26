# SwifterKit's checks beyond what bedrock's Swift and C++ recipes run: the release build, the
# public documentation, the DriverKit extension build and analysis, the coverage article, the
# extension plists, and the IIG formatting that the C++ recipes' file list leaves out.

native_root := "Sources/SwifterKit/Resources/DriverKitExtension"
native_project := native_root / "SwifterKitRuntime.xcodeproj"
native_sources := native_root / "Sources"
generated_trees_root := justfile_directory() / ".build" / "SwifterKitGeneratedTrees"
driverkit_derived := env("RUNNER_TEMP", justfile_directory() / ".build") / "SwifterKitDriverKitDerived"

# The extension build tests copy each generated tree here, one directory per just run, so
# `project-verify` analyzes the trees that this run's `swift::test` built and no stale ones.
export SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE := generated_trees_root / BEDROCK_RUN

# Runs after `just verify`: everything CI checks beyond the languages' own verify.
project-verify: release-build docs native-verify
    rm -rf "{{ SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE }}"

# Format the IIG interface definitions, which clang-format reads as C++.
project-format:
    xcrun clang-format -i {{ native_sources }}/*.iig

# Fail if an IIG interface definition is not formatted.
project-format-check:
    xcrun clang-format --dry-run --Werror {{ native_sources }}/*.iig

# Build the package in release mode.
release-build:
    swift build -c release

# Check that `///` documents only public API, then build the DocC archive with warnings as errors.
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    # Symbol graphs from earlier builds or other toolchains would be found first.
    find .build -type d -name symbolgraph -prune -exec rm -rf {} +
    swift package dump-symbol-graph --minimum-access-level public
    # Built test targets add their own symbol graph; DocC accepts only the library module.
    symbol_graph="$(find .build -type f -path '*/symbolgraph/SwifterKit.symbols.json' -print -quit)"
    test -n "$symbol_graph"
    graphs=.build/SwifterKitSymbolGraph
    rm -rf "$graphs"
    mkdir -p "$graphs"
    cp "$symbol_graph" "$graphs/"
    ./scripts/ci/audit_docs.py "$graphs"
    xcrun docc convert Sources/SwifterKit/SwifterKit.docc \
        --additional-symbol-graph-dir "$graphs" \
        --fallback-display-name SwifterKit \
        --fallback-bundle-identifier com.xsyetopz.SwifterKit \
        --fallback-bundle-version 1 \
        --output-path .build/SwifterKit.doccarchive \
        --warnings-as-errors

# The DriverKit checks read the trees `swift::test` captures, so `just verify` runs them.

# Check coverage claims, the universal and analyzed extension builds, clang-tidy, plists, and file length.
native-verify: project-format-check coverage native-build native-tidy
    plutil -lint {{ native_root }}/Info.plist {{ native_root }}/SwifterKitRuntime.entitlements
    ./scripts/ci/audit_loc.py

# The checked-in project links every family framework, including VideoDriverKit, so it needs
# the newest SDK, and a newer SDK can raise its minimum.

# Print the oldest DriverKit target the selected SDK accepts.
[private]
driverkit-target:
    @plutil -extract SupportedTargets.driverkit.MinimumDeploymentTarget raw -o - "$(xcrun --sdk driverkit --show-sdk-path)/SDKSettings.json"

# The article names the SDKs it was generated from, so every installed DriverKit SDK is passed;
# the article is compared only when the SDKs match.

# Check the DocC coverage article against Apple's headers, clang's evidence, and the Swift docs.
coverage:
    #!/usr/bin/env bash
    set -euo pipefail
    sdks=()
    while IFS= read -r sdk; do sdks+=(--sdk "$sdk"); done < <(
        {
            xcrun --sdk driverkit --show-sdk-path
            find /Applications -maxdepth 1 -name 'Xcode*.app' -exec find \
                {}/Contents/Developer/Platforms/DriverKit.platform/Developer/SDKs \
                -maxdepth 1 -name 'DriverKit[0-9]*.sdk' \; 2>/dev/null
        } | while IFS= read -r path; do realpath "$path"; done | sort -u
    )
    swift run SwifterKitCoverage check "${sdks[@]}" \
        --trees "$SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE" \
        --article Sources/SwifterKit/SwifterKit.docc/DriverKitCoverage.md

# Both builds use Xcode's compilers: a `TOOLCHAINS` override, such as a swift.org toolchain,
# swaps in a clang that rejects Xcode's module flags under -Werror.

# Build the extension unsigned for arm64 and x86_64, then run Xcode's analyzer.
native-build:
    #!/usr/bin/env bash
    set -euo pipefail
    target="$({{ quote(just_executable()) }} driverkit-target)"
    build() {
        env -u TOOLCHAINS xcodebuild -quiet -project "{{ native_project }}" \
            -scheme SwifterKitRuntime -configuration Debug -sdk driverkit \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= \
            GCC_TREAT_WARNINGS_AS_ERRORS=YES DRIVERKIT_DEPLOYMENT_TARGET="$target" "$@"
    }
    build -derivedDataPath "{{ driverkit_derived }}" "ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
    binary="{{ driverkit_derived }}/Build/Products/Debug-driverkit/SwifterKitRuntime.dext/SwifterKitRuntime"
    archs="$(lipo -archs "$binary")"
    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
        echo "expected arm64 and x86_64 DriverKit slices, found: $archs" >&2
        exit 1
    fi
    build -derivedDataPath "{{ driverkit_derived }}-Analyze" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES analyze

# bedrock's `cpp::lint` reads compile commands, which an Xcode DriverKit project does not produce.

# Run clang-tidy over the checked-in extension and each generated tree the build tests captured.
native-tidy:
    #!/usr/bin/env bash
    set -euo pipefail
    derived_sources="$(find "{{ driverkit_derived }}" -type d -path '*/DerivedSources/SwifterKitRuntime' -print -quit)"
    if [[ -z "$derived_sources" ]]; then
        echo "no generated IIG headers under {{ driverkit_derived }}; run just native-build" >&2
        exit 1
    fi
    clang_tidy="${CLANG_TIDY:-}"
    for candidate in "$(command -v clang-tidy || true)" /opt/homebrew/opt/llvm/bin/clang-tidy /usr/local/opt/llvm/bin/clang-tidy; do
        if [[ -z "$clang_tidy" && -n "$candidate" && -x "$candidate" ]]; then clang_tidy="$candidate"; fi
    done
    if [[ -z "$clang_tidy" ]]; then
        echo "clang-tidy is required; run just setup or set CLANG_TIDY" >&2
        exit 1
    fi

    # Each job is SOURCES, IIG_HEADERS, DEPLOYMENT_TARGET, HEADER_FILTER, FILE, NUL-separated.
    jobs_file="$(mktemp)"
    trap 'rm -f "$jobs_file"' EXIT
    add_tree() {
        local source
        for source in "$1"/*.cpp; do printf '%s\0' "$1" "$2" "$3" "$4" "$source" >>"$jobs_file"; done
    }
    add_tree "{{ native_sources }}" "$derived_sources" "$({{ quote(just_executable()) }} driverkit-target)" \
        ".*/{{ native_sources }}/.*"

    # Most family switches are off in the checked-in tree, so the generated trees carry the
    # analysis, and a switch no captured tree turns on fails.
    trees=("$SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE"/*/)
    if [[ ! -d "${trees[0]}" ]]; then
        echo "no generated trees under $SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE; run just verify, which captures them in swift::test" >&2
        exit 1
    fi
    switches="$(sed -n 's/^#define \(SWIFTERKIT_[A-Z_]*\) 0$/\1/p' "{{ native_sources }}/SwifterKitRuntimeConfiguration.h")"
    for switch in $switches; do
        if ! grep -Eqs "^#define $switch [1-9]" "${trees[@]/%/Sources/SwifterKitRuntimeConfiguration.h}"; then
            echo "no generated extension tree enables $switch; add a build test that does" >&2
            exit 1
        fi
    done
    for tree in "${trees[@]}"; do
        tree="${tree%/}"
        add_tree "$tree/Sources" "$tree/DerivedSources" "$(<"$tree/DeploymentTarget")" "$tree/Sources/.*"
    done

    export clang_tidy
    export sdk="$(xcrun --sdk driverkit --show-sdk-path)"
    export checks="-*,clang-analyzer-*,bugprone-*,-bugprone-branch-clone,-bugprone-easily-swappable-parameters,performance-*,-performance-enum-size,misc-const-correctness,modernize-loop-convert,modernize-use-auto,modernize-use-nullptr,readability-qualified-auto"
    # Generated trees live outside the repository, so the configuration is passed explicitly.
    export config_file="$PWD/.clang-tidy"
    # The job script expands its own positional parameters.
    xargs -0 -n 5 -P "$(getconf _NPROCESSORS_ONLN)" bash -c '
        "$clang_tidy" "$5" -quiet --use-color=false --config-file="$config_file" \
            -checks="$checks" --warnings-as-errors="*" --header-filter="$4" -- \
            -x c++ -std=c++20 -fblocks -fno-exceptions -fno-rtti \
            -target "arm64-apple-driverkit$3" -isysroot "$sdk" -I "$1" -I "$2"
    ' _ <"$jobs_file"

# Write the source archive and its SHA-256 checksum for the SemVer `tag` HEAD carries.
release-archive tag:
    #!/usr/bin/env bash
    set -euo pipefail
    tag="{{ tag }}"
    if [[ ! "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
        echo "the release tag must be SemVer, such as 0.1.0 or 0.1.0-rc.1" >&2
        exit 1
    fi
    if [[ "$(git describe --tags --exact-match HEAD 2>/dev/null || true)" != "$tag" ]]; then
        echo "HEAD is not tagged $tag" >&2
        exit 1
    fi
    mkdir -p .build/release-artifacts
    archive=".build/release-artifacts/SwifterKit-$tag.zip"
    git archive --format=zip --prefix="SwifterKit-$tag/" --output="$archive" "$tag"
    shasum -a 256 "$archive" >"$archive.sha256"

# The values come from the environment or `.env.<SWIFTERKIT_ENV>` (default `dev`):
# DEVELOPMENT_TEAM, CODESIGN_IDENTITY, DEXT_BUNDLE_IDENTIFIER,
# DEXT_PROVISIONING_PROFILE_SPECIFIER, and optionally SIGNING_KEYCHAIN.

# Build the validation extension signed for arm64 and x86_64.
sign-driverkit:
    #!/usr/bin/env bash
    set -euo pipefail
    env_file="${SWIFTERKIT_ENV_FILE:-.env.${SWIFTERKIT_ENV:-dev}}"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi
    : "${DEVELOPMENT_TEAM:?missing DEVELOPMENT_TEAM}"
    : "${CODESIGN_IDENTITY:?missing CODESIGN_IDENTITY}"
    : "${DEXT_BUNDLE_IDENTIFIER:?missing DEXT_BUNDLE_IDENTIFIER}"
    : "${DEXT_PROVISIONING_PROFILE_SPECIFIER:?missing DEXT_PROVISIONING_PROFILE_SPECIFIER}"
    keychain_flags=()
    if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
        keychain_flags=("OTHER_CODE_SIGN_FLAGS=--keychain $SIGNING_KEYCHAIN")
    fi
    xcodebuild -quiet -project "{{ native_project }}" -scheme SwifterKitRuntime \
        -configuration Release -sdk driverkit \
        -derivedDataPath "${SWIFTERKIT_DERIVED_DATA:-.build/DriverKitSigned}" \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" PRODUCT_BUNDLE_IDENTIFIER="$DEXT_BUNDLE_IDENTIFIER" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
        PROVISIONING_PROFILE_SPECIFIER="$DEXT_PROVISIONING_PROFILE_SPECIFIER" \
        "ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO "${keychain_flags[@]}" build

# Only the `Signed DriverKit Validation` workflow runs this; it writes GitHub step outputs.

# Import the CI certificate and a DriverKit profile matching the team and bundle identifier.
[private]
import-ci-signing:
    #!/usr/bin/env bash
    set -euo pipefail
    : "${APPLE_DEVELOPMENT_CERT_BASE64:?missing APPLE_DEVELOPMENT_CERT_BASE64}"
    : "${CERTIFICATE_SECRET:?missing CERTIFICATE_SECRET}"
    : "${KEYCHAIN_SECRET:?missing KEYCHAIN_SECRET}"
    : "${SWIFTERKIT_DEXT_PROFILE_BASE64:?missing SWIFTERKIT_DEXT_PROFILE_BASE64}"
    : "${DEVELOPMENT_TEAM:?missing DEVELOPMENT_TEAM}"
    : "${DEXT_BUNDLE_IDENTIFIER:?missing DEXT_BUNDLE_IDENTIFIER}"
    certificate="$RUNNER_TEMP/apple-development.p12"
    profile="$RUNNER_TEMP/SwifterKitRuntime.provisionprofile"
    keychain="$RUNNER_TEMP/swifterkit-signing.keychain-db"
    printf '%s' "$APPLE_DEVELOPMENT_CERT_BASE64" | base64 --decode >"$certificate"
    printf '%s' "$SWIFTERKIT_DEXT_PROFILE_BASE64" | base64 --decode >"$profile"
    security create-keychain -p "$KEYCHAIN_SECRET" "$keychain"
    security set-keychain-settings -lut 21600 "$keychain"
    security unlock-keychain -p "$KEYCHAIN_SECRET" "$keychain"
    security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
    security import "$certificate" -f pkcs12 -k "$keychain" \
        -P "$CERTIFICATE_SECRET" -T /usr/bin/codesign -T /usr/bin/security
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_SECRET" "$keychain"

    plist="$RUNNER_TEMP/SwifterKitRuntime-profile.plist"
    security cms -D -i "$profile" >"$plist"
    team="$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$plist")"
    app_id="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$plist")"
    driverkit="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.driverkit" "$plist")"
    if [[ "$team" != "$DEVELOPMENT_TEAM" || "$app_id" != "$DEVELOPMENT_TEAM.$DEXT_BUNDLE_IDENTIFIER" || "$driverkit" != true ]]; then
        echo "the DriverKit profile does not match the configured team, bundle identifier, or entitlement" >&2
        exit 1
    fi
    profiles="$HOME/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$profiles"
    cp "$profile" "$profiles/$(plutil -extract UUID raw "$plist").provisionprofile"
    echo "profile-name=$(plutil -extract Name raw "$plist")" >>"$GITHUB_OUTPUT"
    echo "keychain-path=$keychain" >>"$GITHUB_OUTPUT"
