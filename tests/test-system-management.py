#!/usr/bin/python3
"""Contract tests for the Phase 6 system-management snapshot."""

from __future__ import annotations

import errno
import hashlib
import importlib.util
import importlib.machinery
import os
import pathlib
import stat
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


class JournalControlRecordTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"
    operation_id = "op-0123456789abcdef0123456789abcdef"

    def test_cursor_round_trips_every_terminal_slot(self):
        for slot in range(provider.JOURNAL_TERMINAL_COUNT):
            with self.subTest(slot=slot):
                payload = provider.encode_journal_cursor(slot)
                self.assertEqual(payload, f"{slot:02d}")
                self.assertEqual(provider.decode_journal_cursor(payload), slot)

    def test_cursor_rejects_noncanonical_or_out_of_range_values(self):
        for payload in ("", "0", "00 ", "01\t", "32", "-1", "aa"):
            with self.subTest(payload=payload):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_cursor(payload)
        for slot in (-1, 32, True, "00"):
            with self.subTest(slot=slot):
                with self.assertRaises(provider.JournalRecordError):
                    provider.encode_journal_cursor(slot)

    def test_handoff_round_trips_empty_and_exact_identity(self):
        self.assertEqual(provider.encode_journal_handoff(None), "")
        self.assertIsNone(provider.decode_journal_handoff(""))
        record = provider.JournalHandoff(self.operation_id, 31)
        payload = f"{self.operation_id}\t31"
        self.assertEqual(provider.encode_journal_handoff(record), payload)
        self.assertEqual(provider.decode_journal_handoff(payload), record)

    def test_handoff_rejects_malformed_identity_or_extra_fields(self):
        invalid = (
            f"{self.operation_id}",
            f"{self.operation_id}\t32",
            f"{self.operation_id}\t00\textra",
            f"op-{'A' * 32}\t00",
            f"op-{'0' * 31}\t00",
        )
        for payload in invalid:
            with self.subTest(payload=payload):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_handoff(payload)

    def test_restart_round_trips_all_closed_values_and_uint64_boundary(self):
        for system in provider.JOURNAL_RESTART_SYSTEM_VALUES:
            for session in provider.JOURNAL_RESTART_SESSION_VALUES:
                for application in (False, True):
                    record = provider.JournalRestart(
                        self.boot_id,
                        self.operation_id,
                        system,
                        session,
                        provider.JOURNAL_SEQUENCE_MAX,
                        application,
                        provider.JOURNAL_SEQUENCE_MAX,
                    )
                    with self.subTest(
                        system=system, session=session, application=application
                    ):
                        payload = provider.encode_journal_restart(record)
                        self.assertEqual(
                            provider.decode_journal_restart(payload), record
                        )

        initial = provider.JournalRestart(
            self.boot_id, None, "none", "none", 0, False, 0
        )
        self.assertEqual(
            provider.decode_journal_restart(self.boot_id + "\t-\tnone\tnone\t0\tno\t0"),
            initial,
        )

    def test_restart_rejects_noncanonical_or_kind_invalid_fields(self):
        base = provider.encode_journal_restart(
            provider.JournalRestart(self.boot_id, None, "none", "none", 0, False, 0)
        ).split("\t")
        cases = {
            "field count": base[:-1],
            "boot": ["not-a-boot-id", *base[1:]],
            "operation": [base[0], "op-bad", *base[2:]],
            "system": [*base[:2], "session", *base[3:]],
            "session": [*base[:3], "system", *base[4:]],
            "session cutoff": [*base[:4], "01", *base[5:]],
            "application": [*base[:5], "true", base[6]],
            "application cutoff": [*base[:6], str(1 << 64)],
            "oversized cutoff": [*base[:6], "9" * 5000],
        }
        for name, fields in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_restart("\t".join(fields))

    def test_restart_encoder_rejects_invalid_typed_values(self):
        invalid = (
            provider.JournalRestart(self.boot_id, None, "none", "none", True, False, 0),
            provider.JournalRestart(self.boot_id, None, "none", "none", 0, "no", 0),
            provider.JournalRestart(self.boot_id, None, "none", "none", 0, False, -1),
            provider.JournalRestart(None, None, "none", "none", 0, False, 0),
            provider.JournalRestart(self.boot_id, 1, "none", "none", 0, False, 0),
            provider.JournalRestart(self.boot_id, None, [], "none", 0, False, 0),
        )
        for record in invalid:
            with self.subTest(record=record):
                with self.assertRaises(provider.JournalRecordError):
                    provider.encode_journal_restart(record)


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

    def write_path(self, directory, name, image):
        path = pathlib.Path(directory) / name
        path.write_bytes(image)
        os.chmod(path, 0o600)
        return path

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
                    provider.JournalLayoutError, "active partial metadata is unsafe"
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
                observed_directory_sync = False

                def observe_retry_sync(descriptor):
                    nonlocal observed_directory_sync
                    if descriptor == directory_descriptor:
                        observed_directory_sync = True
                    return original_fsync(descriptor)

                with mock.patch.object(
                    provider.os, "fsync", side_effect=observe_retry_sync
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertTrue(observed_directory_sync)
            finally:
                os.close(directory_descriptor)

    def test_legacy_plaintext_is_rejected_without_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            active = pathlib.Path(directory) / "active"
            active.write_bytes(b"legacy record")
            os.chmod(active, 0o600)
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active is not recoverable"
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

    def test_missing_and_short_initial_fragments_are_recovered(self):
        with tempfile.TemporaryDirectory() as directory:
            payloads = provider._initial_journal_payloads(self.boot_id)
            active_image = provider.initial_journal_image(payloads["active"])
            cursor_image = provider.initial_journal_image(
                payloads[provider.JOURNAL_CURSOR_NAME]
            )
            active = self.write_path(directory, "active", active_image[:113])
            cursor = self.write_path(
                directory, provider.JOURNAL_CURSOR_NAME, cursor_image[:31]
            )
            active_identity = (active.stat().st_dev, active.stat().st_ino)
            cursor_identity = (cursor.stat().st_dev, cursor.stat().st_ino)
            directory_descriptor = self.open_directory(directory)
            try:
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                self.assertEqual(
                    set(os.listdir(directory)), set(provider.JOURNAL_NAMES)
                )
                self.assertEqual(
                    (active.stat().st_dev, active.stat().st_ino), active_identity
                )
                self.assertEqual(
                    (cursor.stat().st_dev, cursor.stat().st_ino), cursor_identity
                )
                for name in provider.JOURNAL_NAMES:
                    with self.subTest(name=name):
                        self.assertEqual(
                            self.read_path(directory_descriptor, name),
                            (0, provider.JournalFrame(1, payloads[name])),
                        )
            finally:
                os.close(directory_descriptor)

    def test_previous_boot_restart_fragments_are_recovered(self):
        previous_boot = "11234567-89ab-cdef-0123-456789abcdef"
        previous_payload = provider._initial_journal_payloads(previous_boot)["restart"]
        previous_image = provider.initial_journal_image(previous_payload)
        for image in (
            previous_image,
            previous_image[:48],
            previous_image[:100],
            previous_image[:100] + bytes(len(previous_image) - 100),
        ):
            with (
                self.subTest(size=len(image)),
                tempfile.TemporaryDirectory() as directory,
            ):
                restart = self.write_path(directory, "restart", image)
                identity = (restart.stat().st_dev, restart.stat().st_ino)
                directory_descriptor = self.open_directory(directory)
                try:
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                    self.assertEqual(
                        (restart.stat().st_dev, restart.stat().st_ino), identity
                    )
                    current_payload = provider._initial_journal_payloads(self.boot_id)[
                        "restart"
                    ]
                    self.assertEqual(
                        self.read_path(directory_descriptor, "restart"),
                        (0, provider.JournalFrame(1, current_payload)),
                    )
                finally:
                    os.close(directory_descriptor)

    def test_noninitial_restart_records_still_block_recovery(self):
        previous_boot = "11234567-89ab-cdef-0123-456789abcdef"
        previous_payload = provider._initial_journal_payloads(previous_boot)["restart"]
        cases = (
            provider.encode_journal_frame(1, "not-an-all-clear-record")
            + bytes(provider.JOURNAL_FRAME_SIZE),
            provider.encode_journal_frame(1, previous_payload)
            + provider.encode_journal_frame(2, previous_payload),
        )
        for image in cases:
            with (
                self.subTest(image=image[:72]),
                tempfile.TemporaryDirectory() as directory,
            ):
                restart = self.write_path(directory, "restart", image)
                before = restart.read_bytes()
                directory_descriptor = self.open_directory(directory)
                try:
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "restart is not recoverable"
                    ):
                        provider.initialize_journal_layout(
                            directory_descriptor, self.boot_id
                        )
                    self.assertEqual(restart.read_bytes(), before)
                    self.assertEqual(os.listdir(directory), ["restart"])
                finally:
                    os.close(directory_descriptor)

    def test_interrupted_previous_boot_rewrite_remains_retryable(self):
        previous_boot = "11234567-89ab-cdef-0123-456789abcdef"
        previous_payload = provider._initial_journal_payloads(previous_boot)["restart"]
        with tempfile.TemporaryDirectory() as directory:
            restart = self.write_path(
                directory, "restart", provider.initial_journal_image(previous_payload)
            )
            restart_identity = (restart.stat().st_dev, restart.stat().st_ino)
            directory_descriptor = self.open_directory(directory)
            original_pwrite = os.pwrite
            injected = False

            def interrupt_restart_rewrite(descriptor, image, offset):
                nonlocal injected
                metadata = os.fstat(descriptor)
                if (
                    not injected
                    and (metadata.st_dev, metadata.st_ino) == restart_identity
                    and offset == 0
                    and len(image) == provider.JOURNAL_FILE_SIZE
                ):
                    injected = True
                    self.assertEqual(
                        original_pwrite(descriptor, image[:40], offset), 40
                    )
                    return 40
                return original_pwrite(descriptor, image, offset)

            try:
                with mock.patch.object(
                    provider.os, "pwrite", side_effect=interrupt_restart_rewrite
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "restart recovery failed"
                    ):
                        provider.initialize_journal_layout(
                            directory_descriptor, self.boot_id
                        )
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                current_payload = provider._initial_journal_payloads(self.boot_id)[
                    "restart"
                ]
                self.assertEqual(
                    self.read_path(directory_descriptor, "restart"),
                    (0, provider.JournalFrame(1, current_payload)),
                )
            finally:
                os.close(directory_descriptor)

    def test_safe_fragments_cover_short_and_torn_initial_writes(self):
        expected = provider.initial_journal_image("payload")
        for length in (0, 1, 7, 8, 31, 64, 8191, 8192, 10000, 16383):
            with self.subTest(length=length):
                self.assertTrue(
                    provider._is_safe_initial_fragment(expected[:length], expected)
                )
        first_difference = next(
            index for index, byte in enumerate(expected) if byte != 0
        )
        torn = expected[: first_difference + 1] + bytes(
            len(expected) - first_difference - 1
        )
        self.assertTrue(provider._is_safe_initial_fragment(torn, expected))
        self.assertFalse(provider._is_safe_initial_fragment(b"legacy record", expected))
        self.assertFalse(
            provider._is_safe_initial_fragment(expected + b"extra", expected)
        )

    def test_invalid_precursor_file_blocks_all_recovery_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            expected = provider.initial_journal_image("")
            active = self.write_path(directory, "active", expected[:47])
            restart = self.write_path(directory, "restart", b"legacy record")
            active_before = active.read_bytes()
            restart_before = restart.read_bytes()
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "restart is not recoverable"
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(active.read_bytes(), active_before)
                self.assertEqual(restart.read_bytes(), restart_before)
                self.assertEqual(set(os.listdir(directory)), {"active", "restart"})
            finally:
                os.close(directory_descriptor)

    def test_advanced_precursor_file_blocks_reinitialization(self):
        with tempfile.TemporaryDirectory() as directory:
            advanced = provider.encode_journal_frame(
                1, ""
            ) + provider.encode_journal_frame(2, "changed")
            active = self.write_path(directory, "active", advanced)
            before = active.read_bytes()
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active is not recoverable"
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(active.read_bytes(), before)
                self.assertEqual(os.listdir(directory), ["active"])
            finally:
                os.close(directory_descriptor)

    def test_missing_file_after_cursor_is_not_recreated(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            try:
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                active = pathlib.Path(directory) / "active"
                active.unlink()
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active is missing after cursor"
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertFalse(active.exists())
            finally:
                os.close(directory_descriptor)

    def test_damaged_file_after_cursor_is_not_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            try:
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                active = pathlib.Path(directory) / "active"
                active.write_bytes(b"damage")
                damaged = active.read_bytes()
                with self.assertRaises(provider.JournalLayoutError):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(active.read_bytes(), damaged)
            finally:
                os.close(directory_descriptor)

    def test_empty_mode_zero_file_after_cursor_is_not_repaired(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            try:
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                active = pathlib.Path(directory) / "active"
                active.write_bytes(b"")
                os.chmod(active, 0)
                with self.assertRaises(provider.JournalLayoutError):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(stat.S_IMODE(active.stat().st_mode), 0)
                self.assertEqual(active.stat().st_size, 0)
            finally:
                os.chmod(pathlib.Path(directory) / "active", 0o600)
                os.close(directory_descriptor)

    def test_valid_advanced_file_after_cursor_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            try:
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                active_descriptor = os.open(
                    "active",
                    os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
                    dir_fd=directory_descriptor,
                )
                try:
                    provider.commit_journal_file(
                        directory_descriptor, active_descriptor, "changed"
                    )
                finally:
                    os.close(active_descriptor)
                active = pathlib.Path(directory) / "active"
                before = active.read_bytes()
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                self.assertEqual(active.read_bytes(), before)
                self.assertEqual(
                    self.read_path(directory_descriptor, "active"),
                    (1, provider.JournalFrame(2, "changed")),
                )
            finally:
                os.close(directory_descriptor)

    def test_interrupted_creation_is_private_and_retryable_under_strict_umask(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            previous_umask = os.umask(0o777)
            try:
                with mock.patch.object(
                    provider,
                    "_initialize_journal_file_unlocked",
                    side_effect=provider.JournalFrameError(
                        "injected initialization interruption"
                    ),
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "active initialization"
                    ):
                        provider.initialize_journal_layout(
                            directory_descriptor, self.boot_id
                        )
                active = pathlib.Path(directory) / "active"
                self.assertEqual(stat.S_IMODE(active.stat().st_mode), 0o600)
                self.assertEqual(active.stat().st_size, 0)
                provider.initialize_journal_layout(directory_descriptor, self.boot_id)
                self.assertEqual(
                    set(os.listdir(directory)), set(provider.JOURNAL_NAMES)
                )
            finally:
                os.umask(previous_umask)
                os.close(directory_descriptor)

    def test_empty_owner_mode_precursors_are_repaired_through_held_descriptors(self):
        for mode in (0, 0o200, 0o400):
            with (
                self.subTest(mode=oct(mode)),
                tempfile.TemporaryDirectory() as directory,
            ):
                active = self.write_path(directory, "active", b"")
                os.chmod(active, mode)
                directory_descriptor = self.open_directory(directory)
                try:
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                    self.assertEqual(stat.S_IMODE(active.stat().st_mode), 0o600)
                    self.assertEqual(
                        self.read_path(directory_descriptor, "active"),
                        (0, provider.JournalFrame(1, "")),
                    )
                finally:
                    os.close(directory_descriptor)

    def test_mode_repair_waits_until_every_path_is_recoverable(self):
        with tempfile.TemporaryDirectory() as directory:
            active = self.write_path(directory, "active", b"")
            os.chmod(active, 0)
            restart = self.write_path(directory, "restart", b"legacy record")
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "restart is not recoverable"
                ):
                    provider.initialize_journal_layout(
                        directory_descriptor, self.boot_id
                    )
                self.assertEqual(stat.S_IMODE(active.stat().st_mode), 0)
                self.assertEqual(active.stat().st_size, 0)
                self.assertEqual(restart.read_bytes(), b"legacy record")
            finally:
                os.close(directory_descriptor)

    def test_invalid_initial_frame_uses_layout_error_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            active = pathlib.Path(directory) / "active"
            active.write_bytes(b"\0" * provider.JOURNAL_FILE_SIZE)
            os.chmod(active, 0o600)
            directory_descriptor = self.open_directory(directory)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active is not initial"
                ):
                    provider._validate_initial_journal_path_unlocked(
                        directory_descriptor, "active", "0"
                    )
            finally:
                os.close(directory_descriptor)


class JournalDirectoryChainTests(unittest.TestCase):
    def test_xdg_state_path_and_home_fallback_are_canonical(self):
        self.assertEqual(
            provider.journal_directory_path(
                {"XDG_STATE_HOME": "/var/tmp/state", "HOME": "/ignored"}
            ),
            "/var/tmp/state/dwm-titus/system-management",
        )
        self.assertEqual(
            provider.journal_directory_path({"HOME": "/var/tmp/home"}),
            "/var/tmp/home/.local/state/dwm-titus/system-management",
        )
        self.assertEqual(
            provider.journal_directory_path(
                {"XDG_STATE_HOME": "relative", "HOME": "/var/tmp/home/"}
            ),
            "/var/tmp/home/.local/state/dwm-titus/system-management",
        )
        self.assertEqual(
            provider.journal_directory_path({"XDG_STATE_HOME": "/var/tmp/state/"}),
            "/var/tmp/state/dwm-titus/system-management",
        )

    def test_invalid_state_inputs_fail_before_filesystem_access(self):
        cases = (
            {},
            {"HOME": "relative"},
            {"XDG_STATE_HOME": "/tmp/../state"},
            {"XDG_STATE_HOME": "/tmp//state"},
            {"XDG_STATE_HOME": "/tmp/state\0suffix"},
            {"XDG_STATE_HOME": f"/tmp/{'x' * 256}"},
        )
        for environment in cases:
            with self.subTest(environment=environment):
                with self.assertRaises(provider.JournalLayoutError):
                    provider.journal_directory_path(environment)

    def test_fresh_chain_creates_private_journal_and_retains_each_component(self):
        with tempfile.TemporaryDirectory() as directory:
            state_home = pathlib.Path(directory) / "new" / "state"
            chain = provider.open_journal_directory(
                {"XDG_STATE_HOME": str(state_home), "HOME": "/ignored"}
            )
            descriptors = chain.descriptors
            try:
                self.assertEqual(
                    chain.path,
                    str(state_home / "dwm-titus" / "system-management"),
                )
                self.assertEqual(len(descriptors), len(chain.names) + 1)
                self.assertEqual(
                    stat.S_IMODE(os.fstat(chain.directory_descriptor).st_mode), 0o700
                )
                chain.validate()
            finally:
                chain.close()
            for descriptor in descriptors:
                with self.assertRaises(OSError):
                    os.fstat(descriptor)

    def test_root_path_is_rejected_before_opening_a_descriptor(self):
        with mock.patch.object(provider.os, "open") as open_mock:
            with self.assertRaisesRegex(
                provider.JournalLayoutError, "must not be root"
            ):
                provider.open_journal_directory_chain("/")
        open_mock.assert_not_called()

    def test_execute_only_existing_ancestor_can_be_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            ancestor = pathlib.Path(directory) / "traverse-only"
            journal = ancestor / "state" / "dwm-titus" / "system-management"
            journal.mkdir(parents=True, mode=0o700)
            os.chmod(journal, 0o700)
            os.chmod(ancestor, 0o311)
            try:
                with provider.open_journal_directory_chain(str(journal)) as chain:
                    chain.validate()
            finally:
                os.chmod(ancestor, 0o700)

    def test_execute_only_parent_is_rejected_before_child_creation(self):
        with tempfile.TemporaryDirectory() as directory:
            ancestor = pathlib.Path(directory) / "traverse-only"
            ancestor.mkdir()
            os.chmod(ancestor, 0o311)
            ancestor_identity = (ancestor.stat().st_dev, ancestor.stat().st_ino)
            original_open = os.open

            def reject_readable_ancestor(path, flags, *args, **kwargs):
                descriptor = kwargs.get("dir_fd")
                if path == "." and descriptor is not None:
                    metadata = os.fstat(descriptor)
                    if (metadata.st_dev, metadata.st_ino) == ancestor_identity:
                        raise PermissionError(errno.EACCES, "injected access denial")
                return original_open(path, flags, *args, **kwargs)

            try:
                journal = ancestor / "state" / "dwm-titus" / "system-management"
                with mock.patch.object(
                    provider.os, "open", side_effect=reject_readable_ancestor
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "sync handle"
                    ):
                        provider.open_journal_directory_chain(str(journal))
                self.assertFalse((ancestor / "state").exists())
            finally:
                os.chmod(ancestor, 0o700)

    def test_restrictive_umask_cannot_remove_created_owner_access(self):
        with tempfile.TemporaryDirectory() as directory:
            journal = (
                pathlib.Path(directory) / "state" / "dwm-titus" / "system-management"
            )
            previous_umask = os.umask(0o777)
            try:
                with provider.open_journal_directory_chain(str(journal)) as chain:
                    self.assertEqual(
                        stat.S_IMODE(os.fstat(chain.directory_descriptor).st_mode),
                        0o700,
                    )
            finally:
                os.umask(previous_umask)

    def test_interrupted_mode_repair_leaves_a_retryable_private_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = pathlib.Path(directory) / "state" / "dwm-titus"
            parent.mkdir(parents=True)
            journal = parent / "system-management"
            previous_umask = os.umask(0o777)
            try:
                with mock.patch.object(
                    provider,
                    "_chmod_directory_descriptor",
                    side_effect=provider.JournalLayoutError(
                        "injected mode update interruption"
                    ),
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "mode update interruption"
                    ):
                        provider.open_journal_directory_chain(str(journal))
                self.assertEqual(stat.S_IMODE(journal.stat().st_mode), 0o700)
                with provider.open_journal_directory_chain(str(journal)) as chain:
                    chain.validate()
            finally:
                os.umask(previous_umask)

    def test_retry_resyncs_an_indeterminate_created_parent_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = pathlib.Path(directory) / "state" / "dwm-titus"
            parent.mkdir(parents=True)
            journal = parent / "system-management"
            parent_identity = (parent.stat().st_dev, parent.stat().st_ino)
            original_fsync = os.fsync
            failed_parent_sync = False

            def fail_created_entry_sync(descriptor):
                nonlocal failed_parent_sync
                metadata = os.fstat(descriptor)
                if (
                    not failed_parent_sync
                    and journal.exists()
                    and (metadata.st_dev, metadata.st_ino) == parent_identity
                ):
                    failed_parent_sync = True
                    raise OSError("injected parent sync failure")
                return original_fsync(descriptor)

            with mock.patch.object(
                provider.os, "fsync", side_effect=fail_created_entry_sync
            ):
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "directory sync failed"
                ):
                    provider.open_journal_directory_chain(str(journal))
            self.assertTrue(journal.is_dir())

            observed_parent_sync = False

            def observe_parent_sync(descriptor):
                nonlocal observed_parent_sync
                metadata = os.fstat(descriptor)
                if (metadata.st_dev, metadata.st_ino) == parent_identity:
                    observed_parent_sync = True
                return original_fsync(descriptor)

            with mock.patch.object(
                provider.os, "fsync", side_effect=observe_parent_sync
            ):
                with provider.open_journal_directory_chain(str(journal)) as chain:
                    chain.validate()
            self.assertTrue(observed_parent_sync)

    def test_retry_resyncs_an_indeterminate_created_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            parent = pathlib.Path(directory) / "state" / "dwm-titus"
            parent.mkdir(parents=True)
            journal = parent / "system-management"
            original_fsync = os.fsync

            def fail_final_sync(descriptor):
                metadata = os.fstat(descriptor)
                if journal.exists():
                    current = journal.stat()
                    if (metadata.st_dev, metadata.st_ino) == (
                        current.st_dev,
                        current.st_ino,
                    ):
                        raise OSError("injected directory sync failure")
                return original_fsync(descriptor)

            with mock.patch.object(provider.os, "fsync", side_effect=fail_final_sync):
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "directory sync failed"
                ):
                    provider.open_journal_directory_chain(str(journal))
            journal_identity = (journal.stat().st_dev, journal.stat().st_ino)

            observed_directory_sync = False

            def observe_directory_sync(descriptor):
                nonlocal observed_directory_sync
                metadata = os.fstat(descriptor)
                if (metadata.st_dev, metadata.st_ino) == journal_identity:
                    observed_directory_sync = True
                return original_fsync(descriptor)

            with mock.patch.object(
                provider.os, "fsync", side_effect=observe_directory_sync
            ):
                with provider.open_journal_directory_chain(str(journal)) as chain:
                    chain.validate()
            self.assertTrue(observed_directory_sync)

    def test_created_directory_mode_update_follows_the_held_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            original = pathlib.Path(directory) / "original"
            replacement = pathlib.Path(directory) / "replacement"
            original.mkdir(mode=0o755)
            replacement.mkdir(mode=0o755)
            os.chmod(original, 0o755)
            os.chmod(replacement, 0o755)
            descriptor = os.open(original, os.O_PATH | os.O_DIRECTORY)
            try:
                moved = pathlib.Path(directory) / "moved"
                original.rename(moved)
                replacement.rename(original)
                provider._chmod_directory_descriptor(descriptor, 0o700)
                self.assertEqual(stat.S_IMODE(moved.stat().st_mode), 0o700)
                self.assertEqual(stat.S_IMODE(original.stat().st_mode), 0o755)
            finally:
                os.close(descriptor)

    def test_existing_nonprivate_ancestor_is_not_modified(self):
        with tempfile.TemporaryDirectory() as directory:
            ancestor = pathlib.Path(directory) / "shared"
            ancestor.mkdir(mode=0o755)
            os.chmod(ancestor, 0o755)
            with provider.open_journal_directory_chain(
                str(ancestor / "state" / "dwm-titus" / "system-management")
            ) as chain:
                chain.validate()
                self.assertEqual(stat.S_IMODE(ancestor.stat().st_mode), 0o755)

    def test_nonprivate_existing_journal_is_rejected_without_chmod(self):
        with tempfile.TemporaryDirectory() as directory:
            journal = pathlib.Path(directory) / "dwm-titus" / "system-management"
            journal.mkdir(parents=True, mode=0o755)
            os.chmod(journal, 0o755)
            with self.assertRaisesRegex(
                provider.JournalLayoutError, "system-management is not private"
            ):
                provider.open_journal_directory_chain(str(journal))
            self.assertEqual(stat.S_IMODE(journal.stat().st_mode), 0o755)

    def test_symlink_and_nondirectory_components_fail_closed(self):
        for collision in ("symlink", "file"):
            with (
                self.subTest(collision=collision),
                tempfile.TemporaryDirectory() as directory,
            ):
                state = pathlib.Path(directory) / "state"
                if collision == "symlink":
                    target = pathlib.Path(directory) / "target"
                    target.mkdir()
                    state.symlink_to(target, target_is_directory=True)
                else:
                    state.write_text("not a directory", encoding="utf-8")
                with self.assertRaises(provider.JournalLayoutError):
                    provider.open_journal_directory_chain(
                        str(state / "dwm-titus" / "system-management")
                    )

    def test_renamed_ancestor_fails_identity_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            state = pathlib.Path(directory) / "state"
            journal = state / "dwm-titus" / "system-management"
            chain = provider.open_journal_directory_chain(str(journal))
            try:
                moved = pathlib.Path(directory) / "state-moved"
                state.rename(moved)
                state.mkdir()
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "state is unsafe"
                ):
                    chain.validate()
            finally:
                chain.close()

    def test_renamed_journal_fails_identity_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            state = pathlib.Path(directory) / "state"
            journal = state / "dwm-titus" / "system-management"
            chain = provider.open_journal_directory_chain(str(journal))
            try:
                moved = journal.with_name("system-management-moved")
                journal.rename(moved)
                journal.mkdir(mode=0o700)
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "system-management is unsafe"
                ):
                    chain.validate()
            finally:
                chain.close()


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
