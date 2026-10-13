# Development

## Build and test

The original build used Xcode 16.4. The app targets iOS 17+; the SoloCore Swift package supports macOS 13+ and uses Swift tools 5.10. The test suite opens local TCP/UDP sockets, so run it in an environment that permits local listeners.

Install Xcode and XcodeGen, then from the repository root:

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
./build-ipa.sh
```

`build-ipa.sh` generates the Xcode project, builds an unsigned iPhone arm64 release and validates the resulting IPA. Outputs go to the ignored `dist/` directory. Use AltStore to sign and install the IPA. For interactive development, open `SoloPocket.xcodeproj` after creating `Local.xcconfig`.

The build downloads Google Sign-In through Swift Package Manager. The direct dependency is pinned to 9.0.0; the checked-in `Package.resolved` locks transitive versions. The Swift core tests do not require Google login or a physical Solo.

## Repository layout

- `App/`: SwiftUI app, download workflow and optional Google account UI.
- `Sources/SoloCore/`: session parsing, transport, diagnostics, local batches and Drive upload.
- `Tests/SoloCoreTests/`: protocol, local socket, persistence, naming, filtering and simulated Drive tests.
- `Tests/SoloCoreTests/Fixtures/sessions.csv`: synthetic protocol-shaped data, also used by `--demo` mode; it contains no actual location records.
- `Config/Local.example.xcconfig`: empty Google configuration template. Copy it to the ignored `Config/Local.xcconfig` before building.
- `tools/validate_ipa.py`: ZIP structure, required metadata, device executable and local-network permission checks.

## Device scope

The current app connects to `10.0.0.1`, using UDP port 36002 for discovery and TCP port 2000 for transfer. Its discovery guard expects `Solo 2 Tom`. Changing that guard or adding a device picker requires separate real-device validation.

Read [protocol notes](PROTOCOL.md) before changing transport. Mock tests alone do not establish compatibility with another device or firmware. Diagnostics remain local to the phone unless the user exports them.

## Optional Google Drive

Google Drive is not required for local downloads. The release intentionally has empty Google OAuth configuration.

1. Enable Drive API in your Google Cloud project and configure the consent screen/test users as appropriate.
2. Create an iOS OAuth client for the actual installed bundle identifier. AltStore may alter the bundle identifier when re-signing; verify it on the installed app.
3. Set `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` in `Config/Local.xcconfig`, then rebuild. Do not put passwords, private keys or client secrets in the repository.
4. Sign in through the app. It requests `drive.file` access and can create/select its authorized upload folders.
5. Upload a complete local batch manually. Uploading does not delete local files.

Selecting arbitrary existing Drive folders via Google Picker is not implemented. Real Google sign-in/upload has not been validated for this release; automated coverage uses simulated HTTP responses.

## Telemetry analysis

The app checks transferred lengths, protocol checksums and local hashes. It does not decode all XRK/XRZ channels on iPhone. For separate local analysis, the project has used Python `libxrk`; no raw telemetry recordings are included in this repository.

## Third-party notices

Dependency license texts are retained in [third-party notices](THIRD_PARTY_NOTICES.md) and distributed with the release.
