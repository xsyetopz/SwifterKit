#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: $0 DERIVED_DATA_PATH"
	exit 64
fi

native_sources="Sources/SwifterKit/Resources/DriverKitExtension/Sources"
derived_data="$1"
derived_sources="$(find "$derived_data" -type d -path '*/DerivedSources/SwifterKitRuntime' -print -quit)"
if [[ -z "$derived_sources" ]]; then
	echo "ERROR: generated IIG headers were not found under $derived_data"
	exit 1
fi

clang_tidy="${CLANG_TIDY:-}"
if [[ -z "$clang_tidy" ]]; then
	for candidate in \
		"$(command -v clang-tidy || true)" \
		/opt/homebrew/opt/llvm/bin/clang-tidy \
		/usr/local/opt/llvm/bin/clang-tidy; do
		if [[ -n "$candidate" && -x "$candidate" ]]; then
			clang_tidy="$candidate"
			break
		fi
	done
fi
if [[ -z "$clang_tidy" ]]; then
	echo "ERROR: clang-tidy is required; install Homebrew llvm or set CLANG_TIDY"
	exit 1
fi

sdk="$(xcrun --sdk driverkit --show-sdk-path)"
checks="-*,clang-analyzer-*,bugprone-*,-bugprone-branch-clone,-bugprone-easily-swappable-parameters,performance-*,-performance-enum-size,misc-const-correctness,modernize-loop-convert,modernize-use-auto,modernize-use-nullptr,readability-qualified-auto"
for source in "$native_sources"/*.cpp; do
	"$clang_tidy" "$source" -quiet \
		-checks="$checks" \
		--warnings-as-errors="*" \
		-- \
		-x c++ \
		-std=c++20 \
		-fblocks \
		-fno-exceptions \
		-fno-rtti \
		-target arm64-apple-driverkit19.0 \
		-isysroot "$sdk" \
		-I "$native_sources" \
		-I "$derived_sources"
done
