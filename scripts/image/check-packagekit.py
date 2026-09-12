#!/usr/bin/env python3
"""Reject image captures whose PackageKit needs privileged backport inspection."""
import sys

import rpm


def check(headers, compare):
    if len(headers) != 1 or headers[0]["epoch"] not in (None, 0):
        return False
    header = headers[0]
    return compare(("0", header["version"], header["release"]),
                   ("0", "1.3.5", "0")) >= 0


if __name__ == "__main__":
    headers = list(rpm.TransactionSet().dbMatch("name", "PackageKit"))
    if not check(headers, rpm.labelCompare):
        sys.exit("Image requires PackageKit >= 1.3.5 for unprivileged Settings updates; "
                 "update the factory from Fedora repositories before capture")
    print("Image PackageKit security floor: PASS")
