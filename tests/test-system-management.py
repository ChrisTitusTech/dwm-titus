#!/usr/bin/python3
"""Contract tests for the Phase 6 system-management snapshot."""

from __future__ import annotations

import hashlib
import importlib.util
import importlib.machinery
import os
import pathlib
import sys
import tempfile
import threading
import unittest
from unittest import mock


REPO = pathlib.Path(__file__).resolve().parent.parent
PROVIDER_PATH = REPO / "scripts" / "dwm-system-management"
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_loader(
    "dwm_system_management",
    importlib.machinery.SourceFileLoader("dwm_system_management", str(PROVIDER_PATH)),
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load dwm-system-management")
provider = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = provider
SPEC.loader.exec_module(provider)


class FixtureBackend:
    def __init__(
        self,
        *,
        refresh_age=42,
        updates=(),
        restart_types=(),
        plan=(),
        refresh_failure=None,
        updates_failure=None,
        plan_failure=None,
    ):
        self.refresh_age = refresh_age
        self.update_records = tuple(updates)
        self.restart_types = tuple(restart_types)
        self.plan_records = tuple(plan)
        self.refresh_failure = refresh_failure
        self.updates_failure = updates_failure
        self.plan_failure = plan_failure
        self.simulated_ids = None

    def last_refresh_age(self):
        if self.refresh_failure:
            raise self.refresh_failure
        return self.refresh_age

    def updates(self):
        if self.updates_failure:
            raise self.updates_failure
        return provider.TransactionResult(self.update_records, self.restart_types)

    def simulate(self, package_ids):
        self.simulated_ids = tuple(package_ids)
        if self.plan_failure:
            raise self.plan_failure
        return provider.TransactionResult(self.plan_records)


def package(info, package_id, summary):
    return provider.Package(info, package_id, summary)


def rows(lines, kind):
    return [line.split("\t") for line in lines if line.startswith(f"{kind}\t")]


class SnapshotTests(unittest.TestCase):
    def test_complete_read_only_snapshot(self):
        backend = FixtureBackend(
            updates=(
                package(26, "kernel;6.18.1;x86_64;updates", "Critical kernel"),
                package(9, "held;2.0;x86_64;updates", "Blocked update"),
                package(2, "bash;5.3;x86_64;updates", "Shell\tupdate\nsummary"),
            ),
            restart_types=(2, 5, 4),
            plan=(
                package(11, "kernel;6.18.1;x86_64;updates", "Critical kernel"),
                package(11, "bash;5.3;x86_64;updates", "Shell update"),
                package(12, "dependency;1.0;x86_64;updates", "New dependency"),
                package(15, "old-dependency;0.9;x86_64;installed", "Old dependency"),
            ),
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(output[0], "system-management-protocol\t1\t0")
        self.assertEqual(output[-1], "complete\tsnapshot")
        self.assertEqual(len(rows(output, "provider")), 2)
        self.assertEqual(len(rows(output, "state")), 3)
        self.assertEqual(len(rows(output, "action")), 3)
        self.assertEqual(len(rows(output, "update")), 3)
        self.assertEqual(len(rows(output, "package-change")), 4)
        self.assertEqual(rows(output, "error"), [])
        self.assertEqual(
            backend.simulated_ids,
            ("bash;5.3;x86_64;updates", "kernel;6.18.1;x86_64;updates"),
        )
        self.assertIn(
            [
                "state",
                "update-summary",
                "available",
                "3",
                "PackageKit update discovery completed",
            ],
            rows(output, "state"),
        )
        self.assertIn(
            [
                "state",
                "update-restart",
                "available",
                "security-system",
                "PackageKit restart guidance from update discovery",
            ],
            rows(output, "state"),
        )
        bash_row = next(
            row for row in rows(output, "update") if row[1].startswith("bash;")
        )
        self.assertEqual(bash_row[2:4], ["unknown", "installable"])
        self.assertEqual(bash_row[-1], "Shell update summary")
        self.assertEqual(
            output[1],
            "snapshot-generation\t"
            "0626a3347e1e76f4394deb0948b444a89b9ec8875696a1735c893b0db7258bac",
        )

    def test_empty_snapshot_has_stable_generation_and_skips_simulation(self):
        backend = FixtureBackend()
        output = provider.build_snapshot(backend)

        expected = hashlib.sha256(b"dwm-titus-update-plan-v1").hexdigest()
        self.assertEqual(output[1], f"snapshot-generation\t{expected}")
        self.assertEqual(backend.simulated_ids, None)
        self.assertIn(
            [
                "state",
                "update-summary",
                "available",
                "0",
                "PackageKit update discovery completed",
            ],
            rows(output, "state"),
        )

    def test_generation_changes_with_dependency_preview(self):
        update = package(8, "openssl;4.0;x86_64;updates", "TLS library")
        first = FixtureBackend(
            updates=(update,), plan=(package(11, update.package_id, "TLS library"),)
        )
        second = FixtureBackend(
            updates=(update,),
            plan=(
                package(11, update.package_id, "TLS library"),
                package(12, "crypto-policy;2;x86_64;updates", "Policy data"),
            ),
        )

        first_generation = provider.build_snapshot(first)[1]
        second_generation = provider.build_snapshot(second)[1]

        self.assertNotEqual(first_generation, second_generation)

    def test_no_refresh_history_is_explicit_without_an_error(self):
        output = provider.build_snapshot(FixtureBackend(refresh_age=provider.G_MAXUINT))

        self.assertIn(
            [
                "state",
                "update-last-refresh",
                "partial",
                "unknown",
                "PackageKit has no successful refresh history",
            ],
            rows(output, "state"),
        )
        self.assertEqual(rows(output, "error"), [])

    def test_source_failures_preserve_the_complete_protocol_shape(self):
        backend = FixtureBackend(
            refresh_failure=provider.SnapshotFailure(
                "timeout", "PackageKit refresh history timed out", "unavailable"
            ),
            updates_failure=provider.SnapshotFailure(
                "missing-provider", "PackageKit service is unavailable", "unavailable"
            ),
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(output[-1], "complete\tsnapshot")
        self.assertEqual(len(rows(output, "provider")), 2)
        self.assertEqual(len(rows(output, "state")), 3)
        self.assertEqual(len(rows(output, "action")), 3)
        self.assertEqual(rows(output, "update"), [])
        self.assertEqual(rows(output, "package-change"), [])
        self.assertEqual(
            [row[2] for row in rows(output, "error")],
            ["timeout", "missing-provider"],
        )
        install_action = next(
            row for row in rows(output, "action") if row[1] == "updates-install-all"
        )
        self.assertIn("dependency preview is unavailable", install_action[-1])

    def test_invalid_update_classification_discards_the_inventory(self):
        backend = FixtureBackend(
            updates=(package(999, "bad;1;x86_64;updates", "Invalid"),)
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(rows(output, "update"), [])
        self.assertIn(
            [
                "state",
                "update-summary",
                "partial",
                "unknown",
                "PackageKit returned an unsupported update classification",
            ],
            rows(output, "state"),
        )
        self.assertEqual(rows(output, "error")[0][2], "malformed")


class JournalFrameTests(unittest.TestCase):
    def frame_with_header(self, frame, *, offset, value):
        changed = bytearray(frame)
        changed[offset : offset + len(value)] = value
        length = int.from_bytes(changed[12:16], "little")
        payload = changed[provider.JOURNAL_PAYLOAD_OFFSET :][:length]
        changed[32:64] = hashlib.sha256(changed[:32] + payload).digest()
        return bytes(changed)

    def test_golden_frame_layout_and_initial_image(self):
        payload = "op-0123456789abcdef0123456789abcdef\tupdate"
        frame = provider.encode_journal_frame(0x0102030405060708, payload)

        self.assertEqual(len(frame), 8192)
        self.assertEqual(frame[:8], b"DWMJNL1\0")
        self.assertEqual(frame[8:10], b"\x01\x00")
        self.assertEqual(frame[10:12], b"\x00\x00")
        self.assertEqual(
            int.from_bytes(frame[12:16], "little"), len(payload.encode("utf-8"))
        )
        self.assertEqual(frame[16:24], b"\x08\x07\x06\x05\x04\x03\x02\x01")
        self.assertEqual(frame[24:32], bytes(8))
        self.assertEqual(
            frame[32:64],
            hashlib.sha256(frame[:32] + payload.encode("utf-8")).digest(),
        )
        self.assertEqual(frame[64 : 64 + len(payload)], payload.encode("utf-8"))
        self.assertEqual(frame[64 + len(payload) :], bytes(8128 - len(payload)))
        self.assertEqual(
            provider.decode_journal_frame(frame),
            provider.JournalFrame(0x0102030405060708, payload),
        )

        initial = provider.initial_journal_image("00")
        self.assertEqual(len(initial), 16384)
        self.assertEqual(initial[8192:], bytes(8192))
        self.assertEqual(
            provider.select_journal_frame(initial),
            (0, provider.JournalFrame(1, "00")),
        )

    def test_maximum_utf8_payload_round_trips(self):
        payload = "x" * provider.JOURNAL_PAYLOAD_MAX
        frame = provider.encode_journal_frame(2, payload)

        self.assertEqual(provider.decode_journal_frame(frame).payload, payload)
        with self.assertRaisesRegex(provider.JournalFrameError, "too large"):
            provider.encode_journal_frame(2, payload + "x")

    def test_payload_and_sequence_validation(self):
        for payload in ("nul\0byte", "line\nbreak", "carriage\rreturn"):
            with self.subTest(payload=payload):
                with self.assertRaises(provider.JournalFrameError):
                    provider.encode_journal_frame(1, payload)
        with self.assertRaisesRegex(provider.JournalFrameError, "not UTF-8"):
            provider.encode_journal_frame(1, "unpaired-\udcff")
        for sequence in (0, -1, provider.JOURNAL_SEQUENCE_MAX + 1, True):
            with self.subTest(sequence=sequence):
                with self.assertRaises(provider.JournalFrameError):
                    provider.encode_journal_frame(sequence, "")

    def test_decoder_rejects_every_canonical_boundary_violation(self):
        base = provider.encode_journal_frame(4, "payload")
        cases = {
            "size": base[:-1],
            "magic": self.frame_with_header(base, offset=0, value=b"BADJNL1\0"),
            "major": self.frame_with_header(base, offset=8, value=b"\x02\x00"),
            "minor": self.frame_with_header(base, offset=10, value=b"\x01\x00"),
            "length": self.frame_with_header(
                base,
                offset=12,
                value=(provider.JOURNAL_PAYLOAD_MAX + 1).to_bytes(4, "little"),
            ),
            "sequence": self.frame_with_header(base, offset=16, value=bytes(8)),
            "reserved": self.frame_with_header(base, offset=24, value=b"\x01"),
            "digest": base[:32] + bytes(32) + base[64:],
            "padding": base[:-1] + b"\x01",
        }
        for name, image in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalFrameError):
                    provider.decode_journal_frame(image)

        invalid_utf8 = bytearray(provider.encode_journal_frame(4, "x"))
        invalid_utf8[64] = 0xFF
        invalid_utf8[32:64] = hashlib.sha256(
            invalid_utf8[:32] + invalid_utf8[64:65]
        ).digest()
        with self.assertRaisesRegex(provider.JournalFrameError, "not UTF-8"):
            provider.decode_journal_frame(bytes(invalid_utf8))

        forbidden = bytearray(provider.encode_journal_frame(4, "x"))
        forbidden[64] = 0
        forbidden[32:64] = hashlib.sha256(forbidden[:32] + forbidden[64:65]).digest()
        with self.assertRaisesRegex(provider.JournalFrameError, "forbidden"):
            provider.decode_journal_frame(bytes(forbidden))

    def test_selector_uses_highest_valid_sequence_and_survives_torn_peer(self):
        older = provider.encode_journal_frame(9, "older")
        newer = provider.encode_journal_frame(10, "newer")

        self.assertEqual(
            provider.select_journal_frame(older + newer),
            (1, provider.JournalFrame(10, "newer")),
        )
        torn = newer[:40] + bytes(provider.JOURNAL_FRAME_SIZE - 40)
        self.assertEqual(
            provider.select_journal_frame(older + torn),
            (0, provider.JournalFrame(9, "older")),
        )

    def test_selector_rejects_ambiguous_or_exhausted_files(self):
        first = provider.encode_journal_frame(7, "first")
        second = provider.encode_journal_frame(7, "second")
        exhausted = provider.encode_journal_frame(provider.JOURNAL_SEQUENCE_MAX, "")

        with self.assertRaisesRegex(provider.JournalFrameError, "conflicting"):
            provider.select_journal_frame(first + second)
        with self.assertRaisesRegex(provider.JournalFrameError, "no valid"):
            provider.select_journal_frame(bytes(provider.JOURNAL_FILE_SIZE))
        with self.assertRaisesRegex(provider.JournalFrameError, "exhausted"):
            provider.select_journal_frame(
                exhausted + bytes(provider.JOURNAL_FRAME_SIZE)
            )
        self.assertEqual(
            provider.select_journal_frame(first + first),
            (0, provider.JournalFrame(7, "first")),
        )


class JournalFileTests(unittest.TestCase):
    def open_empty(self, directory, name="journal"):
        path = pathlib.Path(directory) / name
        lock_descriptor = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
        descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_RDWR, 0o600)
        return path, lock_descriptor, descriptor

    def test_initialize_and_load_exact_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path, lock_descriptor, descriptor = self.open_empty(directory)
            try:
                initialized = provider.initialize_journal_file(
                    lock_descriptor, descriptor, "initial"
                )
                selected = provider.read_journal_file(lock_descriptor, descriptor)
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)

            self.assertEqual(initialized, provider.JournalFrame(1, "initial"))
            self.assertEqual(selected, (0, initialized))
            self.assertEqual(path.stat().st_size, provider.JOURNAL_FILE_SIZE)
            self.assertEqual(path.stat().st_mode & 0o7777, 0o600)

    def test_commits_alternate_frames_without_resizing(self):
        with tempfile.TemporaryDirectory() as directory:
            path, lock_descriptor, descriptor = self.open_empty(directory)
            try:
                provider.initialize_journal_file(lock_descriptor, descriptor)
                self.assertEqual(
                    provider.commit_journal_file(lock_descriptor, descriptor, "second"),
                    (1, provider.JournalFrame(2, "second")),
                )
                self.assertEqual(
                    provider.commit_journal_file(lock_descriptor, descriptor, "third"),
                    (0, provider.JournalFrame(3, "third")),
                )
                self.assertEqual(
                    provider.read_journal_file(lock_descriptor, descriptor),
                    (0, provider.JournalFrame(3, "third")),
                )
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)

            self.assertEqual(path.stat().st_size, provider.JOURNAL_FILE_SIZE)

    def test_reads_until_the_exact_image_is_complete(self):
        with tempfile.TemporaryDirectory() as directory:
            _path, lock_descriptor, descriptor = self.open_empty(directory)
            try:
                provider.initialize_journal_file(lock_descriptor, descriptor, "chunked")
                original_pread = os.pread

                def chunked_pread(fd, length, offset):
                    return original_pread(fd, min(length, 17), offset)

                with mock.patch.object(provider.os, "pread", side_effect=chunked_pread):
                    self.assertEqual(
                        provider.read_journal_file(lock_descriptor, descriptor),
                        (0, provider.JournalFrame(1, "chunked")),
                    )
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)

    def test_rejects_unsafe_metadata_and_descriptor_access(self):
        with tempfile.TemporaryDirectory() as directory:
            path, lock_descriptor, descriptor = self.open_empty(directory)
            provider.initialize_journal_file(lock_descriptor, descriptor)
            os.close(descriptor)

            os.chmod(path, 0o644)
            descriptor = os.open(path, os.O_RDONLY)
            try:
                with self.assertRaisesRegex(provider.JournalFileError, "metadata"):
                    provider.read_journal_file(lock_descriptor, descriptor)
            finally:
                os.close(descriptor)

            os.chmod(path, 0o600)
            descriptor = os.open(path, os.O_RDONLY)
            try:
                with self.assertRaisesRegex(provider.JournalFileError, "access"):
                    provider.commit_journal_file(lock_descriptor, descriptor, "new")
            finally:
                os.close(descriptor)

            descriptor = os.open(path, os.O_RDWR | os.O_APPEND)
            try:
                with self.assertRaisesRegex(provider.JournalFileError, "access"):
                    provider.commit_journal_file(lock_descriptor, descriptor, "new")
                self.assertEqual(path.stat().st_size, provider.JOURNAL_FILE_SIZE)
            finally:
                os.close(descriptor)

            os.link(path, pathlib.Path(directory) / "extra-link")
            descriptor = os.open(path, os.O_RDWR)
            try:
                with self.assertRaisesRegex(provider.JournalFileError, "metadata"):
                    provider.read_journal_file(lock_descriptor, descriptor)
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)

    def test_torn_inactive_frame_preserves_previous_frame(self):
        with tempfile.TemporaryDirectory() as directory:
            _path, lock_descriptor, descriptor = self.open_empty(directory)
            try:
                provider.initialize_journal_file(
                    lock_descriptor, descriptor, "previous"
                )
                original_pwrite = os.pwrite

                def short_pwrite(fd, data, offset):
                    return original_pwrite(fd, data[:32], offset)

                with mock.patch.object(provider.os, "pwrite", side_effect=short_pwrite):
                    with self.assertRaisesRegex(
                        provider.JournalCommitError, "indeterminate"
                    ):
                        provider.commit_journal_file(lock_descriptor, descriptor, "new")
                self.assertEqual(
                    provider.read_journal_file(lock_descriptor, descriptor),
                    (0, provider.JournalFrame(1, "previous")),
                )
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)

    def test_concurrent_writers_are_serialized_by_directory_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            path, first_lock, first_file = self.open_empty(directory)
            second_file = os.open(path, os.O_RDWR)
            first_in_sync = threading.Event()
            release_first = threading.Event()
            second_done = threading.Event()
            failures = []
            original_fsync = os.fsync

            def blocking_fsync(fd):
                if fd == first_file and not first_in_sync.is_set():
                    first_in_sync.set()
                    if not release_first.wait(2):
                        raise OSError("test did not release the first writer")
                return original_fsync(fd)

            def write(lock_descriptor, descriptor, payload, done=None):
                try:
                    provider.commit_journal_file(lock_descriptor, descriptor, payload)
                except Exception as error:  # unittest thread boundary
                    failures.append(error)
                finally:
                    if done is not None:
                        done.set()

            try:
                provider.initialize_journal_file(first_lock, first_file, "initial")
                with mock.patch.object(
                    provider.os, "fsync", side_effect=blocking_fsync
                ):
                    first = threading.Thread(
                        target=write,
                        args=(first_lock, first_file, "first"),
                    )
                    second = threading.Thread(
                        target=write,
                        args=(first_lock, second_file, "second", second_done),
                    )
                    first.start()
                    self.assertTrue(first_in_sync.wait(1))
                    second.start()
                    self.assertFalse(second_done.wait(0.05))
                    release_first.set()
                    first.join(2)
                    second.join(2)

                self.assertFalse(first.is_alive())
                self.assertFalse(second.is_alive())
                self.assertEqual(failures, [])
                self.assertEqual(
                    provider.read_journal_file(first_lock, first_file),
                    (0, provider.JournalFrame(3, "second")),
                )
            finally:
                release_first.set()
                os.close(second_file)
                os.close(first_file)
                os.close(first_lock)

    def test_sync_failure_can_leave_new_frame_authoritative(self):
        with tempfile.TemporaryDirectory() as directory:
            _path, lock_descriptor, descriptor = self.open_empty(directory)
            try:
                provider.initialize_journal_file(
                    lock_descriptor, descriptor, "previous"
                )
                with mock.patch.object(
                    provider.os, "fsync", side_effect=OSError("injected sync failure")
                ):
                    with self.assertRaisesRegex(
                        provider.JournalCommitError, "indeterminate"
                    ):
                        provider.commit_journal_file(lock_descriptor, descriptor, "new")
                self.assertEqual(
                    provider.read_journal_file(lock_descriptor, descriptor),
                    (1, provider.JournalFrame(2, "new")),
                )
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)

    def test_readback_mismatch_is_indeterminate(self):
        with tempfile.TemporaryDirectory() as directory:
            _path, lock_descriptor, descriptor = self.open_empty(directory)
            try:
                provider.initialize_journal_file(
                    lock_descriptor, descriptor, "previous"
                )
                original_read = provider._read_journal_image
                read_count = 0

                def mismatched_readback(fd):
                    nonlocal read_count
                    read_count += 1
                    image = original_read(fd)
                    if read_count == 2:
                        changed = bytearray(image)
                        changed[provider.JOURNAL_FRAME_SIZE + 32] ^= 1
                        return bytes(changed)
                    return image

                with mock.patch.object(
                    provider, "_read_journal_image", side_effect=mismatched_readback
                ):
                    with self.assertRaisesRegex(
                        provider.JournalCommitError, "indeterminate"
                    ):
                        provider.commit_journal_file(lock_descriptor, descriptor, "new")
                self.assertEqual(
                    provider.read_journal_file(lock_descriptor, descriptor),
                    (1, provider.JournalFrame(2, "new")),
                )
            finally:
                os.close(descriptor)
                os.close(lock_descriptor)


class JournalLayoutTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"

    def open_directory(self, directory):
        return os.open(directory, os.O_RDONLY | os.O_DIRECTORY)

    def read_path(self, directory_descriptor, name):
        descriptor = os.open(
            name,
            os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
            dir_fd=directory_descriptor,
        )
        try:
            return provider.read_journal_file(directory_descriptor, descriptor)
        finally:
            os.close(descriptor)

    def test_fresh_layout_has_exact_initial_records(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            try:
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                self.assertEqual(
                    set(os.listdir(directory)), set(provider.JOURNAL_NAMES)
                )
                payloads = provider._initial_journal_payloads(self.boot_id)
                for name in provider.JOURNAL_NAMES:
                    with self.subTest(name=name):
                        path = pathlib.Path(directory) / name
                        metadata = path.stat()
                        self.assertEqual(metadata.st_mode & 0o7777, 0o600)
                        self.assertEqual(metadata.st_nlink, 1)
                        self.assertEqual(metadata.st_size, provider.JOURNAL_FILE_SIZE)
                        self.assertEqual(
                            self.read_path(directory_descriptor, name),
                            (0, provider.JournalFrame(1, payloads[name])),
                        )
            finally:
                os.close(directory_descriptor)

    def test_invalid_boot_identity_creates_nothing(self):
        invalid = (
            "",
            "01234567-89AB-cdef-0123-456789abcdef",
            "0123456789ab-cdef-0123-456789abcdef",
            "01234567-89ab-cdef-0123-456789abcdeg",
        )
        for boot_id in invalid:
            with self.subTest(boot_id=boot_id):
                with tempfile.TemporaryDirectory() as directory:
                    directory_descriptor = self.open_directory(directory)
                    try:
                        with self.assertRaisesRegex(
                            provider.JournalLayoutError, "boot identity"
                        ):
                            provider.initialize_journal_layout(
                                directory_descriptor, boot_id
                            )
                        self.assertEqual(os.listdir(directory), [])
                    finally:
                        os.close(directory_descriptor)

    def test_fixed_symlink_collision_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            victim = pathlib.Path(directory) / "victim"
            victim.write_bytes(b"do not modify")
            os.symlink("victim", pathlib.Path(directory) / "active")
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active creation"
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(victim.read_bytes(), b"do not modify")
                self.assertFalse(
                    (pathlib.Path(directory) / provider.JOURNAL_CURSOR_NAME).exists()
                )
            finally:
                os.close(directory_descriptor)

    def test_directory_sync_failure_leaves_cursor_absent(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            original_fsync = os.fsync

            def fail_directory_sync(descriptor):
                if descriptor == directory_descriptor:
                    raise OSError("injected directory sync failure")
                return original_fsync(descriptor)

            try:
                with mock.patch.object(
                    provider.os, "fsync", side_effect=fail_directory_sync
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "directory sync"
                    ):
                        provider.initialize_journal_layout(
                            directory_descriptor, self.boot_id
                        )
                self.assertEqual(
                    set(os.listdir(directory)), set(provider.JOURNAL_DATA_NAMES)
                )
                self.assertFalse(
                    (pathlib.Path(directory) / provider.JOURNAL_CURSOR_NAME).exists()
                )
            finally:
                os.close(directory_descriptor)

    def test_final_directory_sync_failure_is_not_accepted_as_success(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            original_fsync = os.fsync
            directory_syncs = 0

            def fail_final_directory_sync(descriptor):
                nonlocal directory_syncs
                if descriptor == directory_descriptor:
                    directory_syncs += 1
                    if directory_syncs == 2:
                        raise OSError("injected final directory sync failure")
                return original_fsync(descriptor)

            try:
                with mock.patch.object(
                    provider.os, "fsync", side_effect=fail_final_directory_sync
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "directory sync"
                    ):
                        provider.initialize_journal_layout(
                            directory_descriptor, self.boot_id
                        )
                self.assertEqual(
                    set(os.listdir(directory)), set(provider.JOURNAL_NAMES)
                )
                self.assertEqual(
                    self.read_path(directory_descriptor, provider.JOURNAL_CURSOR_NAME),
                    (0, provider.JournalFrame(1, "00")),
                )
            finally:
                os.close(directory_descriptor)

    def test_existing_fixed_file_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            active = pathlib.Path(directory) / "active"
            active.write_bytes(b"legacy record")
            os.chmod(active, 0o600)
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active creation"
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(active.read_bytes(), b"legacy record")
                self.assertFalse(
                    (pathlib.Path(directory) / provider.JOURNAL_CURSOR_NAME).exists()
                )
            finally:
                os.close(directory_descriptor)


class SnapshotValidationTests(unittest.TestCase):
    def test_duplicate_plan_preserves_readable_updates(self):
        update = package(8, "openssl;4.0;x86_64;updates", "TLS library")
        backend = FixtureBackend(
            updates=(update,),
            plan=(
                package(11, update.package_id, "TLS library"),
                package(11, update.package_id, "Duplicate"),
            ),
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(len(rows(output, "update")), 1)
        self.assertEqual(rows(output, "package-change"), [])
        self.assertEqual(rows(output, "error")[0][2], "malformed")
        install_action = next(
            row for row in rows(output, "action") if row[1] == "updates-install-all"
        )
        self.assertIn("duplicate plan identity", install_action[-1])

    def test_plan_rejects_packagekit_intent_enums(self):
        package_id = "example;2;x86_64;updates"
        for info in (27, 28, 29, 30):
            with self.subTest(info=info):
                with self.assertRaisesRegex(
                    provider.SnapshotFailure, "unsupported plan classification"
                ):
                    provider.normalize_plan(
                        (package(info, package_id, "Intent enum"),), (package_id,)
                    )

    def test_reinstall_and_downgrade_plan_remains_visible_but_unsupported(self):
        update = package(8, "openssl;4.0;x86_64;updates", "TLS library")
        for extra_info, extra_id in (
            (19, "openssl;4.0;x86_64;installed"),
            (20, "compat-lib;1.0;x86_64;updates"),
        ):
            with self.subTest(extra_info=extra_info):
                backend = FixtureBackend(
                    updates=(update,),
                    plan=(
                        package(11, update.package_id, "TLS library"),
                        package(extra_info, extra_id, "Unsupported change"),
                    ),
                )

                output = provider.build_snapshot(backend)

                self.assertEqual(
                    {row[1] for row in rows(output, "package-change")},
                    {update.package_id, extra_id},
                )
                self.assertIn("unsupported", [row[2] for row in rows(output, "error")])
                install_action = next(
                    row
                    for row in rows(output, "action")
                    if row[1] == "updates-install-all"
                )
                self.assertIn("unsupported reinstall or downgrade", install_action[-1])

    def test_unlisted_packagekit_errors_fall_back_to_internal(self):
        backend = object.__new__(provider.PackageKitBackend)

        self.assertEqual(backend._transaction_failure(10, "download").code, "package")
        self.assertEqual(backend._transaction_failure(4, "internal").code, "internal")

    def test_blocked_updates_are_not_simulated(self):
        backend = FixtureBackend(
            updates=(package(9, "held;2.0;x86_64;updates", "Blocked"),)
        )

        output = provider.build_snapshot(backend)

        self.assertEqual(backend.simulated_ids, None)
        self.assertEqual(rows(output, "update")[0][3], "blocked")

    def test_unsafe_or_duplicate_identities_fail_closed(self):
        cases = (
            (package(8, "bad\tid;1;x86_64;updates", "Unsafe"),),
            (
                package(8, "same;1;x86_64;updates", "First"),
                package(8, "same;1;x86_64;updates", "Second"),
            ),
        )
        for records in cases:
            with self.subTest(records=records):
                output = provider.build_snapshot(FixtureBackend(updates=records))
                self.assertEqual(rows(output, "update"), [])
                self.assertEqual(rows(output, "error")[0][2], "malformed")

    def test_restart_aggregation_rejects_unknown_values(self):
        update = package(9, "held;2.0;x86_64;updates", "Blocked")
        output = provider.build_snapshot(
            FixtureBackend(updates=(update,), restart_types=(99,))
        )

        self.assertEqual(len(rows(output, "update")), 1)
        summary = next(
            row for row in rows(output, "state") if row[1] == "update-summary"
        )
        self.assertEqual(summary[2:4], ["available", "1"])
        restart = next(
            row for row in rows(output, "state") if row[1] == "update-restart"
        )
        self.assertEqual(restart[2:4], ["partial", "unknown"])
        self.assertEqual(rows(output, "error")[0][2], "malformed")

    def test_record_count_limit_discards_the_whole_inventory(self):
        packages = tuple(
            package(2, f"pkg-{number};1;x86_64;updates", "Update")
            for number in range(provider.MAX_LIST_RECORDS + 1)
        )

        output = provider.build_snapshot(FixtureBackend(updates=packages))

        self.assertEqual(rows(output, "update"), [])
        self.assertEqual(rows(output, "error")[0][2], "malformed")


if __name__ == "__main__":
    unittest.main()
