#!/usr/bin/env python3
"""The image floor must not accept release-only backports or prereleases."""
import importlib.util
from pathlib import Path
import unittest

import rpm

spec = importlib.util.spec_from_file_location(
    "image_packagekit", Path(__file__).resolve().parents[1] / "scripts/image/check-packagekit.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ImagePackageKitTests(unittest.TestCase):
    def test_version_boundary(self):
        for version, release, expected in (
            ("1.3.4", "3.fc44", False),
            ("1.3.4", "100.fc44", False),
            ("1.3.5~rc1", "1.fc44", False),
            ("1.3.5", "1.fc44", True),
            ("1.3.6", "1.fc44", True),
            ("1.10.0", "1.fc44", True),
        ):
            with self.subTest(version=version, release=release):
                self.assertEqual(module.check([
                    dict(epoch=None, version=version, release=release)
                ], rpm.labelCompare), expected)

    def test_ambiguous_or_missing_identity(self):
        header = dict(epoch=0, version="1.3.6", release="1.fc44")
        for headers in ([], [header, header], [dict(header, epoch=1)]):
            with self.subTest(headers=headers):
                self.assertFalse(module.check(headers, rpm.labelCompare))


if __name__ == "__main__":
    unittest.main()
