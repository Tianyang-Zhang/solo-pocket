# Solo Pocket 0.1.4

First public release. Only this working version is published.

## Included

- Automatic local-network connection checks when reading sessions or downloading files.
- Full date/time in session rows and an optional filter for sessions without a best lap.
- Multi-session downloads with shared batch annotations.
- Configurable local parent folder and Files access.
- Date/driver/vehicle batch folders and driver/date/time data filenames.
- Optional, manually initiated Drive upload implementation; OAuth is unconfigured in this build.

## Validation and public packaging

The author confirmed that the original 0.1.4 app works with their iPhone and Solo 2. For public distribution, only `Payload/SoloPocket.app/sessions.csv` was replaced with a synthetic fixture. Every other archive member, including the executable, is byte-for-byte identical to the device-tested IPA. The optional `--demo` resource is not used for normal downloads.

- Version: 0.1.4, build 5.
- Public IPA SHA-256: `b06060b5487454292851966fe878f893d4b38e489f4433fb471cf6daa40100d4`.
- Unchanged executable SHA-256: `b5f6848d72ccb64e938a2909558381fa01468ceb0b0e9139685ee62d4c7a1f16`.
- The IPA is unsigned for AltStore to re-sign with the user's own Apple account.
- Public-source test run: 22 tests passed, zero failures; IPA structure/metadata validation passed.
- Real Google OAuth/upload and other Solo device names have not been validated.

The public package has a different full-archive checksum from the private package because its demo resource changed. It has not been separately reinstalled on the physical phone after that resource replacement.
