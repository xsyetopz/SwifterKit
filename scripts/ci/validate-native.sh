#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
	echo "usage: $0 DERIVED_DATA_PATH [GENERATED_TREES]"
	echo "GENERATED_TREES holds the trees the build tests capture with SWIFTERKIT_NATIVE_ANALYSIS_CAPTURE."
	exit 64
fi

native_sources="Sources/SwifterKit/Resources/DriverKitExtension/Sources"
derived_data="$1"
generated_trees="${2:-}"
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

# Each job is SOURCES, IIG_HEADERS, DEPLOYMENT_TARGET, HEADER_FILTER, FILE, NUL-separated.
jobs_file="$(mktemp)"
trap 'rm -f "$jobs_file"' EXIT
add_tree() {
	local sources="$1" headers="$2" target="$3" header_filter="$4" source
	for source in "$sources"/*.cpp; do
		printf '%s\0' "$sources" "$headers" "$target" "$header_filter" "$source" >>"$jobs_file"
	done
}

add_tree "$native_sources" "$derived_sources" "${SWIFTERKIT_DRIVERKIT_TARGET:-19.0}" \
	".*/$native_sources/.*"

if [[ -n "$generated_trees" ]]; then
	# Most family switches are off in the checked-in tree, so analyze the generated trees the
	# build tests produced, and fail when a switch no captured tree turns on.
	trees=("$generated_trees"/*/)
	if [[ ! -d "${trees[0]}" ]]; then
		echo "ERROR: no generated extension trees were captured under $generated_trees"
		exit 1
	fi
	switches="$(sed -n 's/^#define \(SWIFTERKIT_[A-Z_]*\) 0$/\1/p' "$native_sources/SwifterKitRuntimeConfiguration.h")"
	for switch in $switches; do
		if ! grep -Eqs "^#define $switch [1-9]" "${trees[@]/%/Sources/SwifterKitRuntimeConfiguration.h}"; then
			echo "ERROR: no generated extension tree enables $switch; add a build test that does"
			exit 1
		fi
	done
	for tree in "${trees[@]}"; do
		tree="${tree%/}"
		add_tree "$tree/Sources" "$tree/DerivedSources" "$(<"$tree/DeploymentTarget")" "$tree/Sources/.*"
	done
fi

sdk="$(xcrun --sdk driverkit --show-sdk-path)"
checks="-*,clang-analyzer-*,bugprone-*,-bugprone-branch-clone,-bugprone-easily-swappable-parameters,performance-*,-performance-enum-size,misc-const-correctness,modernize-loop-convert,modernize-use-auto,modernize-use-nullptr,readability-qualified-auto"
export clang_tidy checks sdk
# Generated trees live outside the repository, so pass the repository configuration explicitly.
export config_file="$PWD/.clang-tidy"
# shellcheck disable=SC2016 # The job script expands its own positional parameters.
xargs -0 -n 5 -P "$(sysctl -n hw.ncpu)" bash -c '
	"$clang_tidy" "$5" -quiet --use-color=false \
		--config-file="$config_file" \
		-checks="$checks" \
		--warnings-as-errors="*" \
		--header-filter="$4" \
		-- \
		-x c++ \
		-std=c++20 \
		-fblocks \
		-fno-exceptions \
		-fno-rtti \
		-target "arm64-apple-driverkit$3" \
		-isysroot "$sdk" \
		-I "$1" \
		-I "$2"
' _ <"$jobs_file"
