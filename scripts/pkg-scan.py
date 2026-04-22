#!/usr/bin/env python3
"""Simple system package scanner - lists all installed packages."""

import subprocess
import sys


def run(cmd):
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def list_python_packages():
    output = run([sys.executable, "-m", "pip", "list", "--format=columns"])
    if output:
        print("\n=== Python Packages ===")
        print(output)


def list_system_packages():
    managers = [
        ("pacman",  ["pacman", "-Q"]),
        ("dpkg",    ["dpkg-query", "-W", "-f=${Package}\t${Version}\n"]),
        ("rpm",     ["rpm", "-qa", "--qf", "%{NAME}\t%{VERSION}\n"]),
        ("apk",     ["apk", "info", "-v"]),
        ("zypper",  ["zypper", "se", "--installed-only", "-s"]),
        ("flatpak", ["flatpak", "list", "--columns=application,version"]),
        ("snap",    ["snap", "list"]),
    ]

    found = False
    for name, cmd in managers:
        output = run(cmd)
        if output:
            print(f"\n=== {name} Packages ===")
            print(output)
            found = True

    if not found:
        print("No supported package manager found.")


if __name__ == "__main__":
    list_system_packages()
    list_python_packages()
