# Solo 2 transport notes

This is an experimental, unofficial interoperability implementation. No vendor application code or executable is included in the source repository. The wire format was investigated locally and validated with one Solo 2; these notes are not an official AiM API specification.

## Connection

- Device address: `10.0.0.1`.
- Discovery: UDP `aim-ka` (six ASCII bytes, without a NUL) to port 36002. The response contains a device name; the current code checks for `Solo 2 Tom`.
- Transfer: TCP port 2000.
- iPhone reads and downloads first run a TCP-only local connection check, then discovery and the transfer protocol. Network parameters use the system-selected local route and prohibit cellular transport.
- Initial STCP handshake payload: hexadecimal `0000000006080000`.

## Frames and commands

A frame contains `<h`, a four-byte tag, uint32 little-endian payload length, `\0>`, the payload, `<`, the repeated tag, uint16 little-endian payload-byte sum modulo 65536, and `>`.

The STNC command payload is 64 zero-initialized bytes. Operation and sub-operation are placed at offsets 8 and 10; byte 24 is 1.

- Session listing: operation 36, sub-operation 2.
- Read file: operation 2, sub-operation 4. ASCII path at byte 32, maximum 31 bytes, NUL padded. Paths use `1:/mem/<filename>`.
- Reads consume an initial 64-byte reply and a size reply; the uint32 little-endian total is at offset 16. A busy indicator may appear as `0x25` at byte 24.
- A chunk request uses STCP with a uint32 little-endian file offset. The reply starts with the offset followed by data.

The implementation limits frame and file sizes, checks tags/checksums/contiguous offsets, validates paths, and sends no erase or configuration commands. Unexpected responses fail with diagnostics rather than speculative writes.

## Session list

CSV fields include `name`, `size`, `date`, `hour`, `nlap`, `best`, `track_name` and `test_dur`. Bare names are converted to device paths. HRZ rows are excluded. Device dates are displayed without guessing a timezone. Missing best laps do not establish that a recording is worthless.

The public CSV fixture is generated data matching the observed schema; it is not a device capture. Private captures, diagnostic logs and raw recordings are excluded.
