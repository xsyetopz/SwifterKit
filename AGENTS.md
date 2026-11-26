# AGENTS.md - SwifterKit

## Overview

SwifterKit is a Swift 6 wrapper for DriverKit. Driver authors use Swift APIs; the package owns the generated C++20/IIG runtime required by DriverKit.

## Read next

- `README.md` for supported workflows and capability scope.
- `CONTRIBUTING.md` for validation, layout, and change requirements.
- `Sources/SwifterKit/SwifterKit.docc/` for public API and native-boundary contracts.
- `Package.swift`, exact source, tests, and native project files remain authoritative.

## Commands

- Full validation: `just verify`
- Swift tests: `just swift::test`
- Lint: `just lint`
- Format check: `just format-check`
- Formatting, Swift, C++, and IIG: `just format`
- DriverKit extension checks: `just native-verify`, after `just swift::test` in the same run; `just verify` runs both

## Boundaries and invariants

- Preserve public APIs, diagnostics, runtime payloads, DriverKit/IIG ABI declarations, and completion ownership unless the request explicitly changes them.
- Keep Swift 6 concurrency checks clean. Add tests in the path matching the affected `Sources/SwifterKit` area.
- `Sources/SwifterKit/Resources/DriverKitExtension` is the single native extension source tree. Do not add a second generated or hand-maintained copy.
- Driver authors must not need application-owned C++, C, Objective-C, or IIG glue. Native changes belong inside SwifterKit and need a typed Swift surface.
- Source and test files must stay below 800 formatted lines; aim for 500. Markdown does not count. `scripts/ci/audit_loc.py` must remain a LOC-only helper.
- `///` documents only public API, including implicitly public enum cases and protocol requirements. Use `//` elsewhere; `scripts/ci/audit_docs.py` enforces it.
- Fix source rather than weakening `.swift-format`, `.swiftlint.yml`, `.clang-format`, or `.clang-tidy`.
- Keep secrets, signing identities, provisioning profiles, `.env` files, private keys, and device data out of source and output.

## Precedence

Direct user instructions override this file. A closer subtree `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md` overrides this map for that subtree.

<!-- bedrock -->
- Run each task through `just`. `just` lists the recipes. Check each change with the narrowest one, such as `just rust::test` or `just lint`, and run `just verify` once before you finish a change that alters behavior.
- Fix the cause of each lint, type, or guard error in the code. Keep the shared configs as they are; the bedrock that wrote them owns them.
- Put project recipes in `project.just`. The `justfile` and `.just/` are shared and get replaced on the next adopt. A recipe there named `project-<task>`, such as `project-verify` or `project-test`, runs after the languages' `<task>`, so a project extends `just verify` there. `project-pre-typecheck` runs before the TypeScript type check, for a build the types import.
- Write commit messages as Conventional Commits; the commit-msg hook checks them.
- When a recipe reports a missing tool, run `just setup`, which installs the pinned ones. Install any it can't, such as `just`, Bun, rustup, or Xcode, with the system's package manager, then rerun the recipe. Tell the user what you installed, and keep the check instead of skipping it.
<!-- /bedrock -->

<!-- swift-bedrock -->
- Write tests with Swift Testing: `import Testing`, `@Test`, `#expect`, and `#require`. XCTest is only for `*UITests` targets, which need `XCUIApplication`; `just lint-fix` converts other XCTest files.
- Keep the `// >>> swift-bedrock` block at the end of `Package.swift`. It turns on Swift 6 mode, the upcoming features, strict memory safety, and warnings as errors for each target.
- Mark an unsafe expression with `unsafe`, and spell an existential `any P`.
- Build an app in Xcode against `Config/Bedrock.xcconfig`, which sets the same flags as the package.
- Build Swift through `just`, which turns on the compile cache every checkout shares, in a repository without C or C++. When worktrees fill the disk, `just swift::clean-worktrees` deletes each `.build` folder no process is using.
- Document each `public` or `open` declaration other modules can reach. Internal and private code needs no docs, and SwiftLint reports a `public` member of an internal type instead.
<!-- /swift-bedrock -->
