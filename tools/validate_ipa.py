#!/usr/bin/env python3
"""Check the archive AltStore actually imports, not just ZIP CRCs."""
import plistlib
import stat
import sys
import zipfile
from pathlib import PurePosixPath


def validate(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "ZIP integrity failure"
        names = archive.namelist()
        assert len(names) == len(set(names)), "Duplicate ZIP entries"
        # AltSign picks the first Payload child ending in .app without checking
        # if it is a directory. AppleDouble ._SoloPocket.app is a false candidate.
        candidates = {PurePosixPath(n).parts[1] for n in names
                      if len(PurePosixPath(n).parts) >= 2
                      and PurePosixPath(n).parts[0] == "Payload"
                      and PurePosixPath(n).parts[1].lower().endswith(".app")}
        assert len(candidates) == 1, "Ambiguous AltStore app candidates: " + str(sorted(candidates))
        assert not any(any(p.startswith("._") or p == "__MACOSX" for p in PurePosixPath(n).parts) for n in names), "Mac metadata in IPA"
        prefix = "Payload/" + next(iter(candidates)) + "/"
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        for key in ("CFBundleIdentifier", "CFBundleExecutable", "CFBundleShortVersionString", "CFBundleVersion"):
            assert isinstance(info.get(key), str) and info[key], "Missing " + key
        assert info.get("CFBundleDisplayName") or info.get("CFBundleName"), "Missing app name"
        assert info.get("CFBundlePackageType") == "APPL"
        assert info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Not an iPhone device build"
        assert isinstance(info.get("NSLocalNetworkUsageDescription"), str) and info["NSLocalNetworkUsageDescription"].strip(), "Missing local network permission explanation"
        executable = archive.getinfo(prefix + info["CFBundleExecutable"])
        assert (executable.external_attr >> 16) & stat.S_IXUSR, "Executable permission missing"
        assert archive.read(executable)[:4] == b"\xcf\xfa\xed\xfe", "Expected arm64 Mach-O executable"
        print("IPA validated:", info["CFBundleIdentifier"], info["CFBundleShortVersionString"], "build", info["CFBundleVersion"])


if __name__ == "__main__":
    validate(sys.argv[1])
