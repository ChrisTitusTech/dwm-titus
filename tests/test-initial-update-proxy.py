#!/usr/bin/python3
"""Real DNF probes for proxy and file repositories in a disposable container."""
import base64
from http.server import BaseHTTPRequestHandler, HTTPServer
import os
from pathlib import Path
import pwd
import subprocess
import tempfile
import threading
import urllib.parse

assert os.geteuid() == 0 and Path("/.dockerenv").exists()
assert os.environ.get("DWM_DISPOSABLE_DNF_TEST") == "1"
source = Path(__file__).resolve().parents[1] / "scripts/dwm-initial-update-root"

with tempfile.TemporaryDirectory() as name:
    work = Path(name)
    work.chmod(0o755)
    account = pwd.getpwnam("nobody")
    user_home = work / "user"
    user_home.mkdir(mode=0o700)
    os.chown(user_home, account.pw_uid, account.pw_gid)
    packages = work / "packages"
    packages.mkdir()
    subprocess.run(["createrepo_c", str(packages)], check=True)
    authenticated = []

    class Proxy(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            expected = "Basic " + base64.b64encode(b"fixture:fixture").decode()
            if self.headers.get("Proxy-Authorization") != expected:
                self.send_response(407)
                self.send_header("Proxy-Authenticate", 'Basic realm="fixture"')
                self.end_headers()
                return
            location = urllib.parse.urlsplit(self.path)
            path = packages / location.path.removeprefix("/repo/")
            if not path.is_relative_to(packages) or not path.is_file():
                self.send_error(404)
                return
            authenticated.append(location.path)
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = HTTPServer(("127.0.0.1", 0), Proxy)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    repos = work / "repos"
    repos.mkdir()
    repos.chmod(0o755)
    (repos / "fixture.repo").write_text(
        "[fixture]\nname=Authenticated proxy fixture\n"
        "baseurl=http://dnf-fixture.invalid/repo/\nenabled=1\npkg_gpgcheck=1\n"
        f"proxy=http://127.0.0.1:{server.server_port}\n"
        "proxy_username=fixture\nproxy_password=fixture\nproxy_auth_method=basic\n")
    (repos / "fixture.repo").chmod(0o644)
    config = Path("/etc/dnf/dnf.conf")
    original = config.read_bytes()
    try:
        config.write_text("[main]\nreposdir=" + str(repos) + "\n")
        result = subprocess.run(["runuser", "-u", "nobody", "--", "env",
                                 "HOME=" + str(user_home), "TMPDIR=" + str(user_home),
                                 str(source), "probe"], timeout=55)
        assert result.returncode == 0
        assert "/repo/repodata/repomd.xml" in authenticated
        # A normal file:// repository has no custom transport settings, but
        # must still use DNF's native transport instead of HTTPS-only curl.
        # Keep this fixture readable and traversable by the session user.
        for entry in (packages, *packages.rglob("*")):
            entry.chmod(0o755 if entry.is_dir() else 0o644)
        (repos / "fixture.repo").write_text(
            "[fixture]\nname=Local file fixture\n"
            f"baseurl={packages.as_uri()}/\nenabled=1\npkg_gpgcheck=1\n")
        result = subprocess.run(["runuser", "-u", "nobody", "--", "env",
                                 "HOME=" + str(user_home), "TMPDIR=" + str(user_home),
                                 str(source), "probe"], timeout=55)
        assert result.returncode == 0, "Session-user file repository probe failed"
    finally:
        config.write_bytes(original)
        server.shutdown()
        server.server_close()
print("PASS: native repository probe honors configured proxy credentials without copying them into argv")
print("PASS: native repository probe accepts an ordinary file repository as the session user")
