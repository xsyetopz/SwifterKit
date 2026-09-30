# Publishing

SwifterKit is a source-based Swift package. A SemVer tag is the package version. The GitHub release adds a source archive and SHA-256 checksum. Publishing the package does not require Apple signing or notarization.

A generated DriverKit extension belongs to a downstream driver. Its bundle identifier, personality, entitlements, and provisioning profile are product-specific. Do not distribute the checked-in validation extension as a universal driver.

## Workflows

- `CI` checks formatting, lint, Swift 6 tests and release builds, DocC links, C++20 formatting and static analysis, unsigned DriverKit builds, plist files, and the 800-LOC source limit.
- `Release` runs on a pushed SemVer tag or a manual dispatch, repeats validation, creates the archive and checksum, and publishes a GitHub release. A dispatch for a tag that does not exist creates it at the dispatched commit after validation passes.
- `Signed DriverKit Validation` manually builds the validation extension with the protected `driverkit-signing` environment. The signed artifact expires after one day.

The release workflow cannot access DriverKit signing secrets.

## Publish a version

1. Ensure `CI` succeeds.
1. Create and push a SemVer tag without a `v` prefix, such as `0.1.0`.
1. The `Release` workflow validates the tagged commit and creates the GitHub release.
1. Consumers can use SwiftPM's `from: "0.1.0"` requirement.

Alternatively, run `Release` manually from `main` with the new version as `tag`. The workflow validates the `main` head, then creates and pushes the tag before publishing. Manual dispatch never moves an existing tag; it publishes that tag's commit.

## Downstream Apple requirements

A driver product needs:

- Apple approval for each requested DriverKit transport or family entitlement.
  - A `.hid` extension, including a HID device factory, requests `com.apple.developer.driverkit.family.hid.device`, `com.apple.developer.driverkit.transport.hid`, and `com.apple.developer.driverkit.family.hid.eventservice`. A factory needs no further entitlement.
  - `com.apple.developer.hid.virtual.device` is the CoreHID entitlement for user processes that create virtual HID devices. It never belongs in a dext's entitlements.
- An explicit App ID for the generated dext bundle identifier.
- An Apple Development certificate and its private key.
- A DriverKit provisioning profile matching the dext App ID, entitlements, team, and certificate.
- A host application that embeds and activates the dext.
- The `com.apple.developer.driverkit.userclient-access` entitlement on the host application, listing the dext bundle identifier. The generated extension rejects runtime connections without it, and the host's provisioning profile must grant it.
- Developer ID signing and notarization credentials for distribution outside the Mac App Store, or the corresponding App Store setup.

Apple references:

- <https://developer.apple.com/documentation/driverkit/requesting-entitlements-for-driverkit-development>
- <https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers>
- <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>

## Local signed validation

Copy `.env.dev.example` to `.env.dev`, fill in the values, then run:

```sh
./scripts/signing/build-driverkit.sh
```

Set `SWIFTERKIT_ENV=release` to load `.env.release`. The release example includes optional notarization fields for a downstream host application; SwifterKit does not consume them.

`DEXT_PROVISIONING_PROFILE_SPECIFIER` is the profile's `Name`, not its filename. The profile, certificate, private key, team, bundle identifier, and entitlements must agree.

## GitHub signed-validation setup

Create a protected GitHub environment named `driverkit-signing`.

Environment secrets:

| Name | Content |
| --- | --- |
| `APPLE_DEVELOPMENT_CERT_BASE64` | Base64-encoded `.p12` containing the certificate and private key |
| `CERTIFICATE_SECRET` | Password used to export the `.p12` |
| `KEYCHAIN_SECRET` | Random password for the temporary CI keychain |
| `SWIFTERKIT_DEXT_PROFILE_BASE64` | Base64-encoded DriverKit `.provisionprofile` |

Environment variables:

| Name | Content |
| --- | --- |
| `DEVELOPMENT_TEAM` | Certificate/profile Team ID |
| `SWIFTERKIT_DEXT_BUNDLE_IDENTIFIER` | Exact App ID suffix in the profile |

Upload binary secrets through standard input:

```sh
base64 -i AppleDevelopment.p12 |
  gh secret set --env driverkit-signing APPLE_DEVELOPMENT_CERT_BASE64
base64 -i SwifterKitRuntime.provisionprofile |
  gh secret set --env driverkit-signing SWIFTERKIT_DEXT_PROFILE_BASE64
gh secret set --env driverkit-signing CERTIFICATE_SECRET
gh secret set --env driverkit-signing KEYCHAIN_SECRET
gh variable set --env driverkit-signing DEVELOPMENT_TEAM --body "ABCDEF1234"
gh variable set --env driverkit-signing SWIFTERKIT_DEXT_BUNDLE_IDENTIFIER \
  --body "com.example.SwifterKitRuntime"
```

Configure required reviewers before adding secrets. GitHub does not pass repository or environment secrets to workflows from forks.
