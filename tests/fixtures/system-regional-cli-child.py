#!/usr/bin/python3
"""Run the real regional CLI with Fedora identity confined to this test child."""

import runpy
import sys

provider = runpy.run_path(sys.argv[1], run_name="regional_cli_child_fixture")
provider["main"].__globals__["read_fedora_identity"] = lambda: {
    "ID": "fedora", "VERSION_ID": "44"
}
raise SystemExit(provider["main"](sys.argv[2:]))
