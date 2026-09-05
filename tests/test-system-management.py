#!/usr/bin/python3
"""Contract tests for the Phase 6 system-management snapshot."""

from __future__ import annotations

import contextlib
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
import time
import unittest
from dataclasses import replace
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

    def update_operation(self, **changes):
        record = provider.JournalOperation(
            self.operation_id,
            "updates-install-all",
            "2026-02-28T01:02:03Z",
            None,
            "update",
            "running",
            None,
            "Installing updates",
            "a" * 64,
            "/1_deadbeef",
            "none",
            "none",
            False,
            self.boot_id,
            None,
            31,
        )
        return replace(record, **changes)

    def state_payloads(self):
        return provider._initial_journal_payloads(self.boot_id)

    def test_operation_round_trips_nonterminal_and_terminal_update(self):
        active = self.update_operation()
        active_payload = provider.encode_journal_operation(active)
        self.assertEqual(provider.decode_journal_operation(active_payload), active)
        self.assertIn("\tpending\tupdate\trunning\t-\t", active_payload)
        self.assertTrue(active_payload.endswith(f"\t{self.boot_id}\tpending\t31"))

        terminal = replace(
            active,
            finished_at="2026-02-28T01:03:04Z",
            state="failed",
            error_code="package",
            system_restart="unknown",
            session_restart="security-session",
            application_restart=True,
            terminal_monotonic=provider.JOURNAL_SEQUENCE_MAX,
        )
        payload = provider.encode_journal_operation(terminal)
        self.assertEqual(provider.decode_journal_operation(payload), terminal)

    def test_operation_round_trips_refresh_and_non_packagekit_kinds(self):
        refresh = replace(
            self.update_operation(),
            action_id="updates-refresh",
            kind="refresh",
            generation=None,
            system_restart=None,
            session_restart=None,
            application_restart=None,
            boot_id=None,
        )
        timezone = replace(
            refresh,
            action_id="timezone-set",
            kind="timezone",
            transaction_path=None,
        )
        delegate = replace(
            timezone,
            action_id="printers-open",
            kind="delegate",
            finished_at="2026-02-28T01:02:04Z",
            state="succeeded",
        )
        for record in (refresh, timezone, delegate):
            with self.subTest(kind=record.kind):
                payload = provider.encode_journal_operation(record)
                self.assertEqual(provider.decode_journal_operation(payload), record)

    def test_operation_rejects_identity_timestamp_and_field_shape_errors(self):
        active = self.update_operation()
        invalid_records = (
            replace(active, operation_id="op-bad"),
            replace(active, action_id="updates-refresh"),
            replace(active, started_at="2026-02-30T01:02:03Z"),
            replace(active, finished_at="2026-02-28T01:03:04Z"),
            replace(active, state="unknown"),
            replace(active, slot=32),
        )
        for record in invalid_records:
            with self.subTest(record=record):
                with self.assertRaises(provider.JournalRecordError):
                    provider.encode_journal_operation(record)

        payload = provider.encode_journal_operation(active)
        for malformed in (payload + "\textra", "\t".join(payload.split("\t")[:-1])):
            with self.subTest(payload=malformed):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_operation(malformed)

    def test_operation_rejects_invalid_state_error_combinations(self):
        active = self.update_operation()
        invalid = (
            replace(active, error_code="network"),
            replace(
                active,
                finished_at="2026-02-28T01:03:04Z",
                state="succeeded",
                error_code="package",
                terminal_monotonic=1,
            ),
            replace(
                active,
                finished_at="2026-02-28T01:03:04Z",
                state="failed",
                terminal_monotonic=1,
            ),
            replace(
                active,
                finished_at="2026-02-28T01:03:04Z",
                state="failed",
                error_code="not-normalized",
                terminal_monotonic=1,
            ),
        )
        for record in invalid:
            with self.subTest(record=record):
                with self.assertRaises(provider.JournalRecordError):
                    provider.encode_journal_operation(record)

    def test_operation_rejects_kind_incompatible_typed_fields(self):
        active = self.update_operation()
        invalid = (
            replace(active, generation="A" * 64),
            replace(active, transaction_path="/not/packagekit"),
            replace(active, system_restart="session"),
            replace(active, session_restart="system"),
            replace(active, application_restart="no"),
            replace(active, boot_id=None),
            replace(active, terminal_monotonic=1),
            replace(
                active,
                action_id="timezone-set",
                kind="timezone",
                transaction_path=None,
                generation=None,
                system_restart=None,
                session_restart=None,
                application_restart=None,
                boot_id=None,
                terminal_monotonic=1,
            ),
        )
        for record in invalid:
            with self.subTest(record=record):
                with self.assertRaises(provider.JournalRecordError):
                    provider.encode_journal_operation(record)

    def test_operation_rejects_noncanonical_diagnostics_and_wire_fields(self):
        active = self.update_operation()
        for detail in ("line\nbreak", "tab\tbreak", "x" * 513, "bad\0byte"):
            with self.subTest(detail=detail):
                with self.assertRaises(provider.JournalRecordError):
                    provider.encode_journal_operation(replace(active, detail=detail))

        fields = provider.encode_journal_operation(active).split("\t")
        malformed = {
            "application": [*fields[:12], "maybe", *fields[13:]],
            "monotonic": [*fields[:14], "0", fields[15]],
            "finished": [*fields[:3], "-", *fields[4:]],
        }
        for name, changed in malformed.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_operation("\t".join(changed))

    def test_state_round_trips_initial_and_nonterminal_active_payloads(self):
        payloads = self.state_payloads()
        state = provider.decode_journal_state(payloads)
        self.assertEqual(state.cursor, 0)
        self.assertIsNone(state.active)
        self.assertIsNone(state.handoff)
        self.assertEqual(state.restart.boot_id, self.boot_id)
        self.assertEqual(state.terminals, (None,) * provider.JOURNAL_TERMINAL_COUNT)

        active = self.update_operation(slot=7)
        payloads["active"] = provider.encode_journal_operation(active)
        self.assertEqual(provider.decode_journal_state(payloads).active, active)

    def test_state_accepts_each_terminalization_checkpoint(self):
        active = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            terminal_monotonic=123,
        )
        active_payload = provider.encode_journal_operation(active)
        checkpoints = []

        payloads = self.state_payloads()
        payloads["active"] = active_payload
        checkpoints.append(payloads.copy())
        payloads["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(payloads["restart"]),
                last_applied_operation_id=active.operation_id,
            )
        )
        payloads["terminal-07"] = active_payload
        checkpoints.append(payloads.copy())
        payloads["cursor"] = "08"
        checkpoints.append(payloads.copy())
        payloads["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(active.operation_id, 7)
        )
        checkpoints.append(payloads.copy())
        payloads["active"] = ""
        checkpoints.append(payloads.copy())

        for index, checkpoint in enumerate(checkpoints):
            with self.subTest(checkpoint=index):
                state = provider.decode_journal_state(checkpoint)
                self.assertEqual(state.terminals[7], active if index >= 1 else None)

    def test_state_accepts_old_selected_slot_before_terminal_overwrite(self):
        payloads = self.state_payloads()
        old = replace(
            self.update_operation(
                operation_id="op-ffffffffffffffffffffffffffffffff", slot=7
            ),
            finished_at="2026-02-27T01:03:04Z",
            state="succeeded",
            terminal_monotonic=100,
        )
        current = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            terminal_monotonic=123,
        )
        payloads["active"] = provider.encode_journal_operation(current)
        payloads["terminal-07"] = provider.encode_journal_operation(old)
        payloads["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(payloads["restart"]),
                last_applied_operation_id=old.operation_id,
            )
        )
        self.assertEqual(provider.decode_journal_state(payloads).active, current)

    def test_state_accepts_pruned_lower_scope_restart_guidance(self):
        terminal = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            session_restart="security-session",
            application_restart=True,
            terminal_monotonic=123,
        )
        payloads = self.state_payloads()
        payloads["terminal-07"] = provider.encode_journal_operation(terminal)
        payloads["cursor"] = "08"
        payloads["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(payloads["restart"]),
                last_applied_operation_id=terminal.operation_id,
            )
        )
        state = provider.decode_journal_state(payloads)
        self.assertEqual(state.restart.session, "none")
        self.assertFalse(state.restart.application)

        later = replace(
            terminal,
            operation_id="op-ffffffffffffffffffffffffffffffff",
            session_restart="session",
            application_restart=False,
            terminal_monotonic=200,
            slot=8,
        )
        payloads["terminal-08"] = provider.encode_journal_operation(later)
        payloads["cursor"] = "09"
        payloads["restart"] = provider.encode_journal_restart(
            replace(
                state.restart,
                last_applied_operation_id=later.operation_id,
                session="session",
                session_cutoff=later.terminal_monotonic,
            )
        )
        self.assertEqual(provider.decode_journal_state(payloads).restart.session, "session")

    def test_state_rejects_missing_extra_or_wrong_typed_paths(self):
        payloads = self.state_payloads()
        invalid = []
        missing = payloads.copy()
        del missing["active"]
        invalid.append(missing)
        extra = payloads.copy()
        extra["terminal-32"] = ""
        invalid.append(extra)
        wrong_type = payloads.copy()
        wrong_type["active"] = None
        invalid.append(wrong_type)
        for state in invalid:
            with self.subTest(paths=state.keys()):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_state(state)

    def test_state_rejects_invalid_terminal_slot_records(self):
        terminal = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            terminal_monotonic=123,
        )
        cases = {}
        nonterminal = self.state_payloads()
        nonterminal["terminal-07"] = provider.encode_journal_operation(
            self.update_operation(slot=7)
        )
        cases["nonterminal slot"] = nonterminal
        wrong_slot = self.state_payloads()
        wrong_slot["terminal-06"] = provider.encode_journal_operation(terminal)
        cases["wrong slot identity"] = wrong_slot
        duplicate = self.state_payloads()
        duplicate["terminal-07"] = provider.encode_journal_operation(terminal)
        duplicate["terminal-08"] = provider.encode_journal_operation(
            replace(terminal, slot=8)
        )
        cases["duplicate retained identity"] = duplicate
        active_duplicate = self.state_payloads()
        active_duplicate["active"] = provider.encode_journal_operation(
            self.update_operation(slot=7)
        )
        active_duplicate["terminal-07"] = provider.encode_journal_operation(terminal)
        cases["active identity duplicated in terminal"] = active_duplicate
        for name, payloads in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_state(payloads)

    def test_state_rejects_handoff_and_terminalization_conflicts(self):
        terminal = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            terminal_monotonic=123,
        )
        other = replace(
            terminal,
            operation_id="op-ffffffffffffffffffffffffffffffff",
        )
        cases = {}
        missing = self.state_payloads()
        missing["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(terminal.operation_id, 7)
        )
        cases["handoff terminal missing"] = missing
        mismatch = self.state_payloads()
        mismatch["terminal-07"] = provider.encode_journal_operation(terminal)
        mismatch["cursor"] = "08"
        mismatch["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(other.operation_id, 7)
        )
        cases["handoff identity mismatch"] = mismatch
        active_conflict = self.state_payloads()
        active_conflict["active"] = provider.encode_journal_operation(other)
        active_conflict["terminal-07"] = provider.encode_journal_operation(terminal)
        active_conflict["cursor"] = "08"
        active_conflict["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(terminal.operation_id, 7)
        )
        cases["active conflicts with handoff"] = active_conflict
        for name, payloads in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_state(payloads)

    def test_state_rejects_stale_cursor_restart_and_restart_id_reuse(self):
        terminal = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            terminal_monotonic=123,
        )
        cases = {}
        stale_cursor = self.state_payloads()
        stale_cursor["terminal-07"] = provider.encode_journal_operation(terminal)
        stale_cursor["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(terminal.operation_id, 7)
        )
        cases["handoff cursor is stale"] = stale_cursor
        missing_restart = self.state_payloads()
        missing_restart["active"] = provider.encode_journal_operation(terminal)
        missing_restart["terminal-07"] = provider.encode_journal_operation(terminal)
        cases["terminal update restart commit missing"] = missing_restart
        missing_retained_restart = self.state_payloads()
        missing_retained_restart["terminal-07"] = provider.encode_journal_operation(
            terminal
        )
        missing_retained_restart["cursor"] = "08"
        cases["retained update restart identity missing"] = missing_retained_restart
        reused = self.state_payloads()
        reused["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(reused["restart"]),
                last_applied_operation_id=terminal.operation_id,
            )
        )
        reused["active"] = provider.encode_journal_operation(
            self.update_operation(slot=8)
        )
        cases["nonterminal active reuses restart identity"] = reused
        non_update = replace(
            terminal,
            action_id="timezone-set",
            kind="timezone",
            generation=None,
            transaction_path=None,
            system_restart=None,
            session_restart=None,
            application_restart=None,
            boot_id=None,
            terminal_monotonic=None,
        )
        reused_terminal = self.state_payloads()
        reused_terminal["restart"] = reused["restart"]
        reused_terminal["terminal-07"] = provider.encode_journal_operation(non_update)
        reused_terminal["cursor"] = "08"
        cases["non-update terminal reuses restart identity"] = reused_terminal
        previous_boot = self.state_payloads()
        previous_boot["restart"] = reused["restart"]
        previous_boot["terminal-07"] = provider.encode_journal_operation(
            replace(terminal, boot_id="11234567-89ab-cdef-0123-456789abcdef")
        )
        previous_boot["cursor"] = "08"
        cases["previous-boot update reuses restart identity"] = previous_boot
        missing_contribution = self.state_payloads()
        missing_contribution["restart"] = reused["restart"]
        missing_contribution["terminal-07"] = provider.encode_journal_operation(
            replace(terminal, system_restart="security-system")
        )
        missing_contribution["cursor"] = "08"
        cases["system contribution missing"] = missing_contribution
        older_contribution = self.state_payloads()
        newer = replace(
            terminal,
            operation_id="op-ffffffffffffffffffffffffffffffff",
            terminal_monotonic=200,
            slot=8,
        )
        older_contribution["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(older_contribution["restart"]),
                last_applied_operation_id=newer.operation_id,
            )
        )
        older_contribution["terminal-07"] = provider.encode_journal_operation(
            replace(terminal, system_restart="security-system")
        )
        older_contribution["terminal-08"] = provider.encode_journal_operation(newer)
        cases["older system contribution missing"] = older_contribution
        stale_identity = self.state_payloads()
        stale_identity["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(stale_identity["restart"]),
                last_applied_operation_id=terminal.operation_id,
            )
        )
        stale_identity["terminal-07"] = provider.encode_journal_operation(terminal)
        stale_identity["terminal-08"] = provider.encode_journal_operation(newer)
        cases["last-applied identity is stale"] = stale_identity
        for field, changes in (
            (
                "session",
                {
                    "session": "session",
                    "session_cutoff": terminal.terminal_monotonic - 1,
                },
            ),
            (
                "application",
                {
                    "application": True,
                    "application_cutoff": terminal.terminal_monotonic - 1,
                },
            ),
        ):
            stale_cutoff = self.state_payloads()
            stale_cutoff["restart"] = provider.encode_journal_restart(
                replace(
                    provider.decode_journal_restart(stale_cutoff["restart"]),
                    last_applied_operation_id=terminal.operation_id,
                    **changes,
                )
            )
            stale_cutoff["terminal-07"] = provider.encode_journal_operation(
                replace(
                    terminal,
                    session_restart="session" if field == "session" else "none",
                    application_restart=field == "application",
                )
            )
            stale_cutoff["cursor"] = "08"
            cases[f"{field} cutoff is stale"] = stale_cutoff
        for field, changes in (
            (
                "session",
                {
                    "session": "session",
                    "session_cutoff": terminal.terminal_monotonic + 1,
                },
            ),
            (
                "application",
                {
                    "application": True,
                    "application_cutoff": terminal.terminal_monotonic + 1,
                },
            ),
        ):
            future_cutoff = self.state_payloads()
            future_cutoff["restart"] = provider.encode_journal_restart(
                replace(
                    provider.decode_journal_restart(future_cutoff["restart"]),
                    last_applied_operation_id=terminal.operation_id,
                    **changes,
                )
            )
            future_cutoff["terminal-07"] = provider.encode_journal_operation(
                replace(
                    terminal,
                    session_restart="session" if field == "session" else "none",
                    application_restart=field == "application",
                )
            )
            future_cutoff["cursor"] = "08"
            cases[f"{field} cutoff is newer than the last update"] = future_cutoff
        for field, restart_changes in (
            ("system", {"system": "security-system"}),
            (
                "session",
                {"session": "security-session", "session_cutoff": 123},
            ),
            ("application", {"application": True, "application_cutoff": 123}),
        ):
            unsupported_bucket = self.state_payloads()
            unsupported_bucket["restart"] = provider.encode_journal_restart(
                replace(
                    provider.decode_journal_restart(unsupported_bucket["restart"]),
                    last_applied_operation_id=terminal.operation_id,
                    **restart_changes,
                )
            )
            unsupported_bucket["terminal-07"] = provider.encode_journal_operation(
                terminal
            )
            unsupported_bucket["cursor"] = "08"
            cases[f"{field} bucket is unsupported by retained history"] = (
                unsupported_bucket
            )
        for field, contribution_changes, restart_changes in (
            (
                "session",
                {"session_restart": "session"},
                {"session": "session", "session_cutoff": 150},
            ),
            (
                "application",
                {"application_restart": True},
                {"application": True, "application_cutoff": 150},
            ),
        ):
            inexact_cutoff = self.state_payloads()
            older = replace(terminal, terminal_monotonic=100, **contribution_changes)
            latest = replace(
                terminal,
                operation_id="op-ffffffffffffffffffffffffffffffff",
                terminal_monotonic=200,
                slot=8,
            )
            inexact_cutoff["restart"] = provider.encode_journal_restart(
                replace(
                    provider.decode_journal_restart(inexact_cutoff["restart"]),
                    last_applied_operation_id=latest.operation_id,
                    **restart_changes,
                )
            )
            inexact_cutoff["terminal-07"] = provider.encode_journal_operation(older)
            inexact_cutoff["terminal-08"] = provider.encode_journal_operation(latest)
            inexact_cutoff["cursor"] = "09"
            cases[f"{field} cutoff is not a retained contribution"] = inexact_cutoff
        unidentified_guidance = self.state_payloads()
        unidentified_guidance["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(unidentified_guidance["restart"]),
                system="unknown",
            )
        )
        cases["restart guidance has no identity"] = unidentified_guidance
        orphan_identity = self.state_payloads()
        orphan_identity["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(orphan_identity["restart"]),
                last_applied_operation_id="op-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                system="unknown",
            )
        )
        cases["restart identity is absent before ring wrap"] = orphan_identity
        for field, changes in (
            ("session", {"session_cutoff": 123}),
            ("application", {"application_cutoff": 123}),
        ):
            cleared_cutoff = self.state_payloads()
            cleared_cutoff["restart"] = provider.encode_journal_restart(
                replace(
                    provider.decode_journal_restart(cleared_cutoff["restart"]),
                    last_applied_operation_id=terminal.operation_id,
                    **changes,
                )
            )
            cleared_cutoff["terminal-07"] = provider.encode_journal_operation(
                terminal
            )
            cleared_cutoff["cursor"] = "08"
            cases[f"cleared {field} bucket retains cutoff"] = cleared_cutoff
        expected_errors = {
            "system contribution missing": "restart contribution is incomplete",
            "session cutoff is stale": "session restart cutoff is stale",
            "application cutoff is stale": "application restart cutoff is stale",
            "session cutoff is newer than the last update": (
                "session restart cutoff is stale"
            ),
            "application cutoff is newer than the last update": (
                "application restart cutoff is stale"
            ),
            "system bucket is unsupported by retained history": (
                "system restart bucket is unsupported"
            ),
            "session bucket is unsupported by retained history": (
                "session restart bucket is unsupported"
            ),
            "application bucket is unsupported by retained history": (
                "application restart state is not derivable"
            ),
            "session cutoff is not a retained contribution": (
                "session restart state is not derivable"
            ),
            "application cutoff is not a retained contribution": (
                "application restart state is not derivable"
            ),
            "cleared session bucket retains cutoff": (
                "cleared session restart has a cutoff"
            ),
            "cleared application bucket retains cutoff": (
                "cleared application restart has a cutoff"
            ),
        }
        for name, payloads in cases.items():
            with self.subTest(name=name):
                with self.assertRaisesRegex(
                    provider.JournalRecordError,
                    expected_errors.get(name, "journal"),
                ):
                    provider.decode_journal_state(payloads)

    def test_state_rejects_cross_record_recovery_conflicts(self):
        terminal = replace(
            self.update_operation(slot=7),
            finished_at="2026-02-28T01:03:04Z",
            state="succeeded",
            terminal_monotonic=123,
        )
        cases = {}

        newer = replace(
            terminal,
            operation_id="op-ffffffffffffffffffffffffffffffff",
            terminal_monotonic=200,
        )
        stale_active = self.state_payloads()
        stale_active["terminal-07"] = provider.encode_journal_operation(newer)
        stale_active["cursor"] = "08"
        stale_active["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(stale_active["restart"]),
                last_applied_operation_id=newer.operation_id,
            )
        )
        stale_active["active"] = provider.encode_journal_operation(
            replace(terminal, slot=8, terminal_monotonic=100)
        )
        cases["active update predates retained history"] = stale_active

        stale_refresh = self.state_payloads()
        refresh = replace(
            terminal,
            action_id="updates-refresh",
            kind="refresh",
            generation=None,
            system_restart=None,
            session_restart=None,
            application_restart=None,
            boot_id=None,
            terminal_monotonic=100,
            slot=8,
        )
        stale_refresh["terminal-07"] = provider.encode_journal_operation(newer)
        stale_refresh["cursor"] = "08"
        stale_refresh["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(stale_refresh["restart"]),
                last_applied_operation_id=newer.operation_id,
            )
        )
        stale_refresh["active"] = provider.encode_journal_operation(refresh)
        cases["active refresh predates retained update history"] = stale_refresh

        old_boot_active = self.state_payloads()
        old_boot_active["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(old_boot_active["restart"]),
                last_applied_operation_id="op-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                system="unknown",
            )
        )
        old_boot_active["active"] = provider.encode_journal_operation(
            replace(
                self.update_operation(slot=7),
                boot_id="11234567-89ab-cdef-0123-456789abcdef",
            )
        )
        old_boot_active["cursor"] = "07"
        regional_terminal = replace(
            terminal,
            action_id="timezone-set",
            kind="timezone",
            generation=None,
            transaction_path=None,
            system_restart=None,
            session_restart=None,
            application_restart=None,
            boot_id=None,
            terminal_monotonic=None,
        )
        for slot in range(provider.JOURNAL_TERMINAL_COUNT):
            old_boot_active[f"terminal-{slot:02d}"] = (
                provider.encode_journal_operation(
                    replace(
                        regional_terminal,
                        operation_id=f"op-{slot + 1:032x}",
                        slot=slot,
                    )
                )
            )
        cases["old-boot active update restart is not clear"] = old_boot_active

        old_boot_handoff = self.state_payloads()
        old_boot_terminal = replace(
            terminal, boot_id="11234567-89ab-cdef-0123-456789abcdef"
        )
        old_boot_handoff["terminal-07"] = provider.encode_journal_operation(
            old_boot_terminal
        )
        old_boot_handoff["cursor"] = "08"
        old_boot_handoff["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(old_boot_terminal.operation_id, 7)
        )
        old_boot_handoff["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(old_boot_handoff["restart"]),
                last_applied_operation_id="op-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
                system="unknown",
            )
        )
        cases["old-boot handoff restart is not clear"] = old_boot_handoff

        downgraded_session = self.state_payloads()
        downgraded_session["terminal-07"] = provider.encode_journal_operation(
            replace(terminal, session_restart="security-session")
        )
        downgraded_session["cursor"] = "08"
        downgraded_session["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(downgraded_session["restart"]),
                last_applied_operation_id=terminal.operation_id,
                session="session",
                session_cutoff=terminal.terminal_monotonic,
            )
        )
        cases["security-session urgency is downgraded"] = downgraded_session

        stale_handoff = self.state_payloads()
        refresh = replace(
            terminal,
            action_id="updates-refresh",
            kind="refresh",
            generation=None,
            system_restart=None,
            session_restart=None,
            application_restart=None,
            boot_id=None,
            terminal_monotonic=100,
        )
        later_update = replace(newer, slot=8)
        stale_handoff["terminal-07"] = provider.encode_journal_operation(refresh)
        stale_handoff["terminal-08"] = provider.encode_journal_operation(later_update)
        stale_handoff["cursor"] = "08"
        stale_handoff["handoff"] = provider.encode_journal_handoff(
            provider.JournalHandoff(refresh.operation_id, 7)
        )
        stale_handoff["restart"] = provider.encode_journal_restart(
            replace(
                provider.decode_journal_restart(stale_handoff["restart"]),
                last_applied_operation_id=later_update.operation_id,
            )
        )
        cases["handoff is superseded by retained update"] = stale_handoff

        stale_cursor = self.state_payloads()
        stale_cursor["terminal-07"] = provider.encode_journal_operation(refresh)
        cases["completed terminal cursor is stale"] = stale_cursor

        for name, payloads in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(provider.JournalRecordError):
                    provider.decode_journal_state(payloads)


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

    def test_descriptor_close_failure_does_not_mask_layout_error(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            provider.initialize_journal_layout(directory_descriptor, self.boot_id)
            original_close_descriptors = provider._close_descriptors
            cleanup_calls = 0

            def close_descriptors_then_fail(descriptors):
                nonlocal cleanup_calls
                cleanup_calls += 1
                self.assertIsNone(original_close_descriptors(descriptors))
                return OSError(errno.EIO, "injected close failure")

            try:
                with (
                    mock.patch.object(
                        provider,
                        "_validate_initialized_journal_path_unlocked",
                        side_effect=provider.JournalLayoutError(
                            "injected primary layout error"
                        ),
                    ),
                    mock.patch.object(
                        provider,
                        "_close_descriptors",
                        side_effect=close_descriptors_then_fail,
                    ),
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "injected primary layout error"
                    ):
                        provider.initialize_journal_layout(
                            directory_descriptor, self.boot_id
                        )
            finally:
                os.close(directory_descriptor)

            self.assertEqual(cleanup_calls, 2)

    def test_successful_layout_close_failure_inside_exception_handler_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_descriptor = self.open_directory(directory)
            provider.initialize_journal_layout(directory_descriptor, self.boot_id)
            original_close_descriptors = provider._close_descriptors
            cleanup_calls = 0

            def close_descriptors_then_fail(descriptors):
                nonlocal cleanup_calls
                cleanup_calls += 1
                self.assertIsNone(original_close_descriptors(descriptors))
                return OSError(errno.EIO, "injected close failure")

            try:
                try:
                    raise RuntimeError("outer handled error")
                except RuntimeError:
                    with mock.patch.object(
                        provider,
                        "_close_descriptors",
                        side_effect=close_descriptors_then_fail,
                    ):
                        with self.assertRaisesRegex(
                            provider.JournalLayoutError,
                            "journal partial descriptor close failed",
                        ):
                            provider.initialize_journal_layout(
                                directory_descriptor, self.boot_id
                            )
            finally:
                os.close(directory_descriptor)

            self.assertEqual(cleanup_calls, 2)

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


class JournalStateLoadTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"

    def open_initialized_chain(self, directory):
        state = pathlib.Path(directory) / "state"
        journal = state / "dwm-titus" / "system-management"
        chain = provider.open_journal_directory_chain(str(journal))
        provider.initialize_journal_layout(chain.directory_descriptor, self.boot_id)
        return state, journal, chain

    def test_loads_exact_fixed_paths_read_only_without_enumeration(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, _journal, chain = self.open_initialized_chain(directory)
            opened = {}
            first_read_saw_all_descriptors = False
            original_open = os.open
            original_read = provider._read_journal_file_unlocked

            def track_open(path, flags, *args, **kwargs):
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened[path] = (descriptor, flags)
                return descriptor

            def observe_first_read(descriptor):
                nonlocal first_read_saw_all_descriptors
                if not first_read_saw_all_descriptors:
                    self.assertEqual(tuple(opened), provider.JOURNAL_NAMES)
                    first_read_saw_all_descriptors = True
                return original_read(descriptor)

            try:
                with (
                    mock.patch.object(provider.os, "open", side_effect=track_open),
                    mock.patch.object(
                        provider.os,
                        "listdir",
                        side_effect=AssertionError("directory enumeration is forbidden"),
                    ),
                    mock.patch.object(
                        provider.os,
                        "scandir",
                        side_effect=AssertionError("directory enumeration is forbidden"),
                    ),
                    mock.patch.object(
                        provider,
                        "_read_journal_file_unlocked",
                        side_effect=observe_first_read,
                    ),
                ):
                    state = provider.load_journal_state(chain)
            finally:
                chain.close()

            self.assertTrue(first_read_saw_all_descriptors)
            self.assertEqual(
                state,
                provider.decode_journal_state(
                    provider._initial_journal_payloads(self.boot_id)
                ),
            )
            self.assertEqual(tuple(opened), provider.JOURNAL_NAMES)
            for descriptor, flags in opened.values():
                self.assertEqual(flags & os.O_ACCMODE, os.O_RDONLY)
                self.assertTrue(flags & os.O_NONBLOCK)
                self.assertTrue(flags & os.O_NOFOLLOW)
                self.assertTrue(flags & os.O_CLOEXEC)
                with self.assertRaises(OSError):
                    os.fstat(descriptor)

    def test_record_error_closes_every_retained_file_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, _journal, chain = self.open_initialized_chain(directory)
            active_descriptor = os.open(
                "active",
                os.O_NOFOLLOW | os.O_CLOEXEC | os.O_RDWR,
                dir_fd=chain.directory_descriptor,
            )
            try:
                provider.commit_journal_file(
                    chain.directory_descriptor, active_descriptor, "malformed"
                )
            finally:
                os.close(active_descriptor)

            opened = []
            original_open = os.open

            def track_open(path, flags, *args, **kwargs):
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened.append(descriptor)
                return descriptor

            try:
                with mock.patch.object(provider.os, "open", side_effect=track_open):
                    with self.assertRaisesRegex(
                        provider.JournalRecordError, "operation field count"
                    ):
                        provider.load_journal_state(chain)
            finally:
                chain.close()

            self.assertEqual(len(opened), len(provider.JOURNAL_NAMES))
            for descriptor in opened:
                with self.assertRaises(OSError):
                    os.fstat(descriptor)

    def test_close_failure_does_not_mask_primary_record_error(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, _journal, chain = self.open_initialized_chain(directory)
            opened = []
            original_open = os.open
            original_close = os.close
            failed_close = False

            def track_open(path, flags, *args, **kwargs):
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened.append(descriptor)
                return descriptor

            def close_then_fail_once(descriptor):
                nonlocal failed_close
                original_close(descriptor)
                if descriptor in opened and not failed_close:
                    failed_close = True
                    raise OSError(errno.EIO, "injected close failure")

            try:
                with (
                    mock.patch.object(provider.os, "open", side_effect=track_open),
                    mock.patch.object(
                        provider,
                        "decode_journal_state",
                        side_effect=provider.JournalRecordError(
                            "injected primary record error"
                        ),
                    ),
                    mock.patch.object(
                        provider.os, "close", side_effect=close_then_fail_once
                    ),
                ):
                    with self.assertRaisesRegex(
                        provider.JournalRecordError, "injected primary record error"
                    ):
                        provider.load_journal_state(chain)
            finally:
                chain.close()

            self.assertTrue(failed_close)
            for descriptor in opened:
                with self.assertRaises(OSError):
                    os.fstat(descriptor)

    def test_successful_load_close_failure_inside_exception_handler_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, _journal, chain = self.open_initialized_chain(directory)
            opened = []
            original_open = os.open
            original_close = os.close
            failed_close = False

            def track_open(path, flags, *args, **kwargs):
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened.append(descriptor)
                return descriptor

            def close_then_fail_once(descriptor):
                nonlocal failed_close
                original_close(descriptor)
                if descriptor in opened and not failed_close:
                    failed_close = True
                    raise OSError(errno.EIO, "injected close failure")

            try:
                try:
                    raise RuntimeError("outer handled error")
                except RuntimeError:
                    with (
                        mock.patch.object(
                            provider.os, "open", side_effect=track_open
                        ),
                        mock.patch.object(
                            provider.os, "close", side_effect=close_then_fail_once
                        ),
                    ):
                        with self.assertRaisesRegex(
                            provider.JournalLayoutError,
                            "journal state descriptor close failed",
                        ):
                            provider.load_journal_state(chain)
            finally:
                chain.close()

            self.assertTrue(failed_close)
            for descriptor in opened:
                with self.assertRaises(OSError):
                    os.fstat(descriptor)

    def test_open_failure_closes_every_previously_opened_path(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, _journal, chain = self.open_initialized_chain(directory)
            opened = []
            original_open = os.open

            def fail_later_open(path, flags, *args, **kwargs):
                if (
                    path == "terminal-05"
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    raise OSError(errno.EIO, "injected open failure")
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened.append(descriptor)
                return descriptor

            try:
                with mock.patch.object(provider.os, "open", side_effect=fail_later_open):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "terminal-05 open failed"
                    ):
                        provider.load_journal_state(chain)
            finally:
                chain.close()

            self.assertGreater(len(opened), 1)
            for descriptor in opened:
                with self.assertRaises(OSError):
                    os.fstat(descriptor)

    def test_fixed_symlink_is_rejected_without_following_the_target(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, journal, chain = self.open_initialized_chain(directory)
            path = journal / "terminal-31"
            target = journal / "terminal-31-retained"
            path.rename(target)
            path.symlink_to(target.name)
            before = target.read_bytes()
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "terminal-31 open failed"
                ):
                    provider.load_journal_state(chain)
                self.assertEqual(target.read_bytes(), before)
            finally:
                chain.close()

    def test_unsafe_metadata_reports_the_exact_fixed_path(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, journal, chain = self.open_initialized_chain(directory)
            active = journal / "active"
            os.chmod(active, 0o644)
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active identity is unsafe"
                ):
                    provider.load_journal_state(chain)
            finally:
                os.chmod(active, 0o600)
                chain.close()

    def test_fifo_path_fails_without_waiting_for_a_writer(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, journal, chain = self.open_initialized_chain(directory)
            path = journal / "terminal-31"
            path.unlink()
            os.mkfifo(path, 0o600)
            os.chmod(path, 0o600)
            started = time.monotonic()
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "terminal-31 identity is unsafe"
                ):
                    provider.load_journal_state(chain)
                self.assertLess(time.monotonic() - started, 1)
            finally:
                chain.close()

    def test_replaced_path_is_rejected_after_descriptor_bound_read(self):
        with tempfile.TemporaryDirectory() as directory:
            _state, journal, chain = self.open_initialized_chain(directory)
            active = journal / "active"
            detached = journal / "active-detached"
            image = active.read_bytes()
            original_read = provider._read_journal_file_unlocked
            replaced = False

            def replace_active(descriptor):
                nonlocal replaced
                if not replaced:
                    replaced = True
                    active.rename(detached)
                    active.write_bytes(image)
                    os.chmod(active, 0o600)
                return original_read(descriptor)

            try:
                with mock.patch.object(
                    provider,
                    "_read_journal_file_unlocked",
                    side_effect=replace_active,
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "active identity is unsafe"
                    ):
                        provider.load_journal_state(chain)
                self.assertTrue(replaced)
                self.assertEqual(detached.read_bytes(), image)
                self.assertEqual(active.read_bytes(), image)
            finally:
                chain.close()

    def test_replaced_ancestor_is_rejected_after_complete_decode(self):
        with tempfile.TemporaryDirectory() as directory:
            state_path, _journal, chain = self.open_initialized_chain(directory)
            moved = pathlib.Path(directory) / "state-moved"
            original_decode = provider.decode_journal_state

            def replace_state(payloads):
                result = original_decode(payloads)
                state_path.rename(moved)
                state_path.mkdir()
                return result

            try:
                with mock.patch.object(
                    provider, "decode_journal_state", side_effect=replace_state
                ):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "state is unsafe"
                    ):
                        provider.load_journal_state(chain)
            finally:
                chain.close()


class JournalWritableOpenTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"

    def open_initialized_chain(self, directory):
        journal = pathlib.Path(directory) / "state" / "dwm-titus" / "system-management"
        chain = provider.open_journal_directory_chain(str(journal))
        provider.initialize_journal_layout(chain.directory_descriptor, self.boot_id)
        return journal, chain

    def test_retains_exact_fixed_writable_paths_under_exclusive_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            opened = {}
            lock_events = []
            original_open = os.open
            original_lock = provider._journal_lock

            def track_open(path, flags, *args, **kwargs):
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened[path] = (descriptor, flags)
                return descriptor

            @contextlib.contextmanager
            def observe_lock(descriptor, *, exclusive):
                lock_events.append(("enter", descriptor, exclusive))
                with original_lock(descriptor, exclusive=exclusive):
                    yield
                lock_events.append(("exit", descriptor, exclusive))

            try:
                with (
                    mock.patch.object(provider.os, "open", side_effect=track_open),
                    mock.patch.object(provider, "_journal_lock", side_effect=observe_lock),
                    mock.patch.object(
                        provider.os,
                        "listdir",
                        side_effect=AssertionError("directory enumeration is forbidden"),
                    ),
                    mock.patch.object(
                        provider.os,
                        "scandir",
                        side_effect=AssertionError("directory enumeration is forbidden"),
                    ),
                ):
                    with provider.open_writable_journal(chain) as journal:
                        self.assertEqual(
                            lock_events,
                            [("enter", chain.directory_descriptor, True)],
                        )
                        self.assertEqual(tuple(opened), provider.JOURNAL_NAMES)
                        journal.validate()
                        for name, (descriptor, flags) in opened.items():
                            self.assertEqual(journal.descriptor(name), descriptor)
                            self.assertEqual(flags & os.O_ACCMODE, os.O_RDWR)
                            self.assertTrue(flags & os.O_NONBLOCK)
                            self.assertTrue(flags & os.O_NOFOLLOW)
                            self.assertTrue(flags & os.O_CLOEXEC)

                self.assertEqual(
                    lock_events,
                    [
                        ("enter", chain.directory_descriptor, True),
                        ("exit", chain.directory_descriptor, True),
                    ],
                )
                self.assertTrue(journal.closed)
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "descriptor set is closed"
                ):
                    journal.descriptor("active")
                for descriptor, _flags in opened.values():
                    with self.assertRaises(OSError):
                        os.fstat(descriptor)
            finally:
                chain.close()

    def test_open_failure_closes_every_previously_retained_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            opened = []
            original_open = os.open

            def fail_later_open(path, flags, *args, **kwargs):
                if (
                    path == "terminal-05"
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    raise OSError(errno.EIO, "injected open failure")
                descriptor = original_open(path, flags, *args, **kwargs)
                if (
                    path in provider.JOURNAL_NAMES
                    and kwargs.get("dir_fd") == chain.directory_descriptor
                ):
                    opened.append(descriptor)
                return descriptor

            try:
                with mock.patch.object(provider.os, "open", side_effect=fail_later_open):
                    with self.assertRaisesRegex(
                        provider.JournalLayoutError,
                        "terminal-05 writable open failed",
                    ):
                        with provider.open_writable_journal(chain):
                            self.fail("journal opened after a fixed-path failure")
                self.assertGreater(len(opened), 1)
                for descriptor in opened:
                    with self.assertRaises(OSError):
                        os.fstat(descriptor)
            finally:
                chain.close()

    def test_fifo_path_is_rejected_without_waiting_for_a_peer(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            path = journal_path / "terminal-31"
            path.unlink()
            os.mkfifo(path, 0o600)
            os.chmod(path, 0o600)
            started = time.monotonic()
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "terminal-31 identity is unsafe"
                ):
                    with provider.open_writable_journal(chain):
                        self.fail("FIFO was accepted as a journal file")
                self.assertLess(time.monotonic() - started, 1)
            finally:
                chain.close()

    def test_replaced_path_is_rejected_before_releasing_the_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            active = journal_path / "active"
            detached = journal_path / "active-detached"
            image = active.read_bytes()
            held_descriptors = ()
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active identity is unsafe"
                ):
                    with provider.open_writable_journal(chain) as journal:
                        held_descriptors = tuple(
                            journal.descriptor(name) for name in provider.JOURNAL_NAMES
                        )
                        active.rename(detached)
                        active.write_bytes(image)
                        os.chmod(active, 0o600)
                self.assertEqual(detached.read_bytes(), image)
                self.assertEqual(active.read_bytes(), image)
                for descriptor in held_descriptors:
                    with self.assertRaises(OSError):
                        os.fstat(descriptor)
            finally:
                chain.close()

    def test_close_failure_does_not_mask_body_error(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            original_close_descriptors = provider._close_descriptors
            cleanup_calls = 0

            def close_descriptors_then_fail(descriptors):
                nonlocal cleanup_calls
                cleanup_calls += 1
                self.assertIsNone(original_close_descriptors(descriptors))
                return OSError(errno.EIO, "injected close failure")

            try:
                with mock.patch.object(
                    provider,
                    "_close_descriptors",
                    side_effect=close_descriptors_then_fail,
                ):
                    with self.assertRaisesRegex(
                        provider.JournalRecordError, "injected body error"
                    ):
                        with provider.open_writable_journal(chain):
                            raise provider.JournalRecordError("injected body error")
                self.assertEqual(cleanup_calls, 1)
            finally:
                chain.close()

    def test_successful_close_failure_inside_exception_handler_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            original_close_descriptors = provider._close_descriptors
            cleanup_calls = 0

            def close_descriptors_then_fail(descriptors):
                nonlocal cleanup_calls
                cleanup_calls += 1
                self.assertIsNone(original_close_descriptors(descriptors))
                return OSError(errno.EIO, "injected close failure")

            try:
                try:
                    raise RuntimeError("outer handled error")
                except RuntimeError:
                    with mock.patch.object(
                        provider,
                        "_close_descriptors",
                        side_effect=close_descriptors_then_fail,
                    ):
                        with self.assertRaisesRegex(
                            provider.JournalLayoutError,
                            "writable journal descriptor close failed",
                        ):
                            with provider.open_writable_journal(chain):
                                pass
                self.assertEqual(cleanup_calls, 1)
            finally:
                chain.close()


class JournalWritableCommitTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"

    def open_initialized_chain(self, directory):
        journal = pathlib.Path(directory) / "state" / "dwm-titus" / "system-management"
        chain = provider.open_journal_directory_chain(str(journal))
        provider.initialize_journal_layout(chain.directory_descriptor, self.boot_id)
        return journal, chain

    def test_commits_retained_path_between_complete_validations(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    index, frame = provider.commit_writable_journal_path(
                        journal, "active", ""
                    )

                    self.assertEqual(index, 1)
                    self.assertEqual(frame, provider.JournalFrame(2, ""))
                    self.assertEqual(
                        provider._read_journal_file_unlocked(
                            journal.descriptor("active")
                        ),
                        (index, frame),
                    )
            finally:
                chain.close()

    def test_replaced_target_is_rejected_before_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            active = journal_path / "active"
            detached = journal_path / "active-detached"
            image = active.read_bytes()
            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active identity is unsafe"
                ):
                    with provider.open_writable_journal(chain) as journal:
                        active.rename(detached)
                        active.write_bytes(image)
                        os.chmod(active, 0o600)
                        provider.commit_writable_journal_path(journal, "active", "")

                self.assertEqual(
                    provider.select_journal_frame(detached.read_bytes())[1].sequence,
                    1,
                )
                self.assertEqual(
                    provider.select_journal_frame(active.read_bytes())[1].sequence,
                    1,
                )
            finally:
                chain.close()

    def test_replaced_target_is_rejected_after_descriptor_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            active = journal_path / "active"
            detached = journal_path / "active-detached"
            image = active.read_bytes()
            original_commit = provider._commit_journal_file_unlocked

            def replace_after_commit(descriptor, payload):
                result = original_commit(descriptor, payload)
                active.rename(detached)
                active.write_bytes(image)
                os.chmod(active, 0o600)
                return result

            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active identity is unsafe"
                ):
                    with provider.open_writable_journal(chain) as journal:
                        with mock.patch.object(
                            provider,
                            "_commit_journal_file_unlocked",
                            side_effect=replace_after_commit,
                        ):
                            provider.commit_writable_journal_path(
                                journal, "active", ""
                            )

                self.assertEqual(
                    provider.select_journal_frame(detached.read_bytes())[1].sequence,
                    2,
                )
                self.assertEqual(
                    provider.select_journal_frame(active.read_bytes())[1].sequence,
                    1,
                )
            finally:
                chain.close()

    def test_unrelated_replaced_path_is_rejected_after_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            terminal = journal_path / "terminal-12"
            detached = journal_path / "terminal-12-detached"
            terminal_image = terminal.read_bytes()
            original_commit = provider._commit_journal_file_unlocked

            def replace_after_commit(descriptor, payload):
                result = original_commit(descriptor, payload)
                terminal.rename(detached)
                terminal.write_bytes(terminal_image)
                os.chmod(terminal, 0o600)
                return result

            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "terminal-12 identity is unsafe"
                ):
                    with provider.open_writable_journal(chain) as journal:
                        with mock.patch.object(
                            provider,
                            "_commit_journal_file_unlocked",
                            side_effect=replace_after_commit,
                        ):
                            provider.commit_writable_journal_path(
                                journal, "active", ""
                            )

                self.assertEqual(
                    provider.select_journal_frame(
                        (journal_path / "active").read_bytes()
                    )[1].sequence,
                    2,
                )
            finally:
                chain.close()

    def test_indeterminate_commit_revalidates_and_preserves_primary_error(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            active = journal_path / "active"
            detached = journal_path / "active-detached"
            image = active.read_bytes()
            commit_error = provider.JournalCommitError(
                "injected indeterminate commit"
            )

            def fail_after_replacement(_descriptor, _payload):
                active.rename(detached)
                active.write_bytes(image)
                os.chmod(active, 0o600)
                raise commit_error

            try:
                with self.assertRaises(provider.JournalCommitError) as caught:
                    with provider.open_writable_journal(chain) as journal:
                        with mock.patch.object(
                            provider,
                            "_commit_journal_file_unlocked",
                            side_effect=fail_after_replacement,
                        ):
                            provider.commit_writable_journal_path(journal, "active", "")

                self.assertIs(caught.exception, commit_error)
                self.assertIsInstance(
                    caught.exception.__cause__, provider.JournalLayoutError
                )
                self.assertIn(
                    "active identity is unsafe", str(caught.exception.__cause__)
                )
            finally:
                chain.close()


class JournalRetainedSessionTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"

    @contextlib.contextmanager
    def session(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "state" / "dwm-titus" / "system-management"
            with provider.open_journal_directory_chain(str(path)) as chain:
                provider.initialize_journal_layout(chain.directory_descriptor, self.boot_id)
                with provider.retain_writable_journal(chain) as journal:
                    yield path, chain, journal

    def begin(self, journal):
        return provider.begin_journal_operation(
            journal, "updates-refresh", "2026-09-04T18:00:00Z", "Starting refresh",
            transaction_path="/1_test", boot_id=self.boot_id,
        )

    def test_service_interval_releases_lock_but_retains_all_file_identities(self):
        with self.session() as (_path, chain, journal):
            identities = {
                name: (journal.descriptor(name), os.fstat(journal.descriptor(name)).st_ino)
                for name in provider.JOURNAL_NAMES
            }
            with provider._journal_lock(chain.directory_descriptor, exclusive=True):
                pass
            with provider.lock_writable_journal(journal):
                operation = self.begin(journal)
                with mock.patch.object(provider, "JOURNAL_LOCK_DEADLINE_SECONDS", 0.01):
                    with self.assertRaises(provider.JournalLockError):
                        with provider._journal_lock(chain.directory_descriptor, exclusive=True):
                            self.fail("checkpoint lock did not exclude another writer")
            with provider._journal_lock(chain.directory_descriptor, exclusive=True):
                pass
            with provider.lock_writable_journal(journal):
                self.assertEqual(provider.load_writable_journal_state(journal).active, operation)
                for name, (descriptor, inode) in identities.items():
                    self.assertEqual(journal.descriptor(name), descriptor)
                    self.assertEqual(os.fstat(descriptor).st_ino, inode)
        self.assertTrue(journal.closed)
        for descriptor, _inode in identities.values():
            with self.assertRaises(OSError):
                os.fstat(descriptor)

    def test_unlocked_state_reads_and_commits_are_rejected(self):
        with self.session() as (path, _chain, journal):
            before = (path / "active").read_bytes()
            with self.assertRaisesRegex(provider.JournalLockError, "exclusive interval"):
                provider.load_writable_journal_state(journal)
            with self.assertRaisesRegex(provider.JournalLockError, "exclusive interval"):
                provider.commit_writable_journal_path(journal, "active", "active\tempty")
            with self.assertRaisesRegex(provider.JournalLockError, "exclusive interval"):
                self.begin(journal)
            self.assertEqual((path / "active").read_bytes(), before)

    def test_reacquisition_observes_concurrent_checkpoint_and_rejects_stale_owner(self):
        with self.session() as (_path, chain, journal):
            with provider.lock_writable_journal(journal):
                pending = self.begin(journal)
            running = replace(pending, state="running")
            with provider.open_writable_journal(chain) as observer:
                provider.advance_journal_operation(observer, pending, running)
            with provider.lock_writable_journal(journal):
                self.assertEqual(provider.load_writable_journal_state(journal).active, running)
                with self.assertRaises(provider.JournalAdmissionError):
                    provider.advance_journal_operation(journal, pending, running)

    def test_replaced_file_during_service_wait_is_rejected_before_checkpoint(self):
        descriptors = ()
        with self.assertRaisesRegex(provider.JournalLayoutError, "active identity"):
            with self.session() as (path, _chain, journal):
                descriptors = tuple(journal.descriptor(name) for name in provider.JOURNAL_NAMES)
                active = path / "active"
                before = active.read_bytes()
                active.rename(path / "detached-active")
                active.write_bytes(before)
                active.chmod(0o600)
                with provider.lock_writable_journal(journal):
                    self.fail("replacement was accepted")
        for descriptor in descriptors:
            with self.assertRaises(OSError):
                os.fstat(descriptor)

    def test_replaced_directory_during_service_wait_is_rejected(self):
        with self.assertRaises(provider.JournalLayoutError):
            with self.session() as (path, _chain, journal):
                path.rename(path.with_name("detached-journal"))
                path.mkdir(mode=0o700)
                with provider.lock_writable_journal(journal):
                    self.fail("directory replacement was accepted")

    def test_nested_interval_and_body_error_release_lock(self):
        with self.session() as (_path, chain, journal):
            with self.assertRaisesRegex(RuntimeError, "service error"):
                with provider.lock_writable_journal(journal):
                    with self.assertRaisesRegex(provider.JournalLockError, "already active"):
                        with provider.lock_writable_journal(journal):
                            self.fail("nested interval was accepted")
                    raise RuntimeError("service error")
            self.assertFalse(journal._exclusive)
            with provider._journal_lock(chain.directory_descriptor, exclusive=True):
                pass
            with provider.lock_writable_journal(journal):
                self.assertIsNone(provider.load_writable_journal_state(journal).active)

    def test_contended_reacquisition_remains_bounded_and_can_be_retried(self):
        with self.session() as (_path, chain, journal):
            with provider._journal_lock(chain.directory_descriptor, exclusive=True):
                started = time.monotonic()
                with mock.patch.object(provider, "JOURNAL_LOCK_DEADLINE_SECONDS", 0.01):
                    with self.assertRaises(provider.JournalLockError):
                        with provider.lock_writable_journal(journal):
                            self.fail("contended interval was entered")
                self.assertLess(time.monotonic() - started, 1)
            self.assertFalse(journal._exclusive)
            with provider.lock_writable_journal(journal):
                self.assertIsNone(provider.load_writable_journal_state(journal).active)


class JournalLifecycleTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"
    started = "2026-09-04T18:00:00Z"
    finished = "2026-09-04T18:01:00Z"

    def test_fedora_transaction_paths_are_root_level_bounded_ids(self):
        for path in ("/18_adcbcaed", "/45_dafeca"):
            self.assertIsNotNone(provider.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path))
        for path in (
            "/org/freedesktop/PackageKit/transactions/18_adcbcaed",
            "/org/freedesktop/PackageKit", "/", "/18_adcbcaed/child",
            "/18_", "/18_" + "a" * 65, "/" + "1" * 21 + "_abcd",
            "/18_abcd\n", "/18_ab-cd",
        ):
            self.assertIsNone(provider.JOURNAL_PACKAGEKIT_PATH_PATTERN.fullmatch(path))

    @contextlib.contextmanager
    def journal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "state" / "dwm-titus" / "system-management"
            with provider.open_journal_directory_chain(str(path)) as chain:
                provider.initialize_journal_layout(
                    chain.directory_descriptor, self.boot_id
                )
                with provider.open_writable_journal(chain) as journal:
                    yield journal

    def begin(self, journal, action="updates-refresh"):
        args = {}
        if action in ("updates-refresh", "updates-install-all"):
            args["transaction_path"] = "/1_test"
            args["boot_id"] = self.boot_id
        if action == "updates-install-all":
            args.update(generation="a" * 64, boot_id=self.boot_id)
        return provider.begin_journal_operation(
            journal, action, self.started, "Starting operation", **args
        )

    def finish(self, journal, operation, **contributions):
        running = replace(operation, state="running", **contributions)
        provider.advance_journal_operation(journal, operation, running)
        terminal = replace(
            running,
            state="succeeded",
            finished_at=self.finished,
            terminal_monotonic=100 if running.kind in ("refresh", "update") else None,
        )
        provider.advance_journal_operation(journal, running, terminal)
        return terminal

    def image(self, journal, name):
        return os.pread(journal.descriptor(name), provider.JOURNAL_FILE_SIZE, 0)

    def test_pending_is_durable_and_blocks_overlap(self):
        with self.journal() as journal:
            operation = self.begin(journal)
            self.assertEqual(
                provider.load_writable_journal_state(journal).active, operation
            )
            self.assertEqual(operation.state, "pending")
            before = self.image(journal, "active")
            with self.assertRaises(provider.JournalAdmissionError):
                self.begin(journal)
            self.assertEqual(self.image(journal, "active"), before)

    def test_invalid_admission_arguments_never_commit(self):
        with self.journal() as journal:
            with mock.patch.object(provider, "commit_writable_journal_path") as commit:
                for action, args in (
                    ("unknown", {}),
                    ("updates-refresh", {"transaction_path": "/arbitrary"}),
                    ("timezone-set", {"generation": "a" * 64}),
                    (
                        "updates-install-all",
                        {
                            "generation": "a" * 64,
                            "transaction_path": "/1_test",
                            "boot_id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                        },
                    ),
                ):
                    with self.subTest(action=action):
                        with self.assertRaises(
                            (
                                provider.JournalRecordError,
                                provider.JournalAdmissionError,
                            )
                        ):
                            provider.begin_journal_operation(
                                journal, action, self.started, "Starting", **args
                            )
                commit.assert_not_called()

    def test_rejects_stale_identity_illegal_transition_and_progress_writes(self):
        with self.journal() as journal:
            pending = self.begin(journal)
            running = replace(pending, state="running")
            provider.advance_journal_operation(journal, pending, running)
            for expected, following in (
                (pending, running),
                (
                    running,
                    replace(
                        running,
                        transaction_path="/2_other",
                    ),
                ),
                (running, replace(running, state="authorizing")),
                (running, replace(running, detail="Progress only")),
            ):
                with self.subTest(following=following):
                    before = self.image(journal, "active")
                    with self.assertRaises(provider.JournalAdmissionError):
                        provider.advance_journal_operation(journal, expected, following)
                    self.assertEqual(self.image(journal, "active"), before)

    def test_restart_contributions_only_strengthen(self):
        with self.journal() as journal:
            pending = self.begin(journal, "updates-install-all")
            stronger = replace(
                pending, session_restart="security-session", application_restart=True
            )
            provider.advance_journal_operation(journal, pending, stronger)
            with self.assertRaises(provider.JournalAdmissionError):
                provider.advance_journal_operation(journal, stronger, pending)

    def test_every_kind_retains_exact_terminal_until_acknowledged(self):
        for action in provider.JOURNAL_OPERATION_ACTION_KINDS:
            with self.subTest(action=action), self.journal() as journal:
                terminal = self.finish(journal, self.begin(journal, action))
                restart_before = self.image(journal, "restart")
                provider.complete_journal_terminal(journal, boot_id=self.boot_id)
                state = provider.load_writable_journal_state(journal)
                self.assertIsNone(state.active)
                self.assertEqual(
                    state.handoff, provider.JournalHandoff(terminal.operation_id, 0)
                )
                self.assertEqual(state.cursor, 1)
                self.assertEqual(
                    provider.retained_journal_operation(journal, terminal.operation_id),
                    terminal,
                )
                with self.assertRaises(provider.JournalAdmissionError):
                    self.begin(journal)
                with self.assertRaises(provider.JournalAdmissionError):
                    provider.acknowledge_journal_handoff(journal, "op-" + "f" * 32)
                provider.acknowledge_journal_handoff(journal, terminal.operation_id)
                self.assertIsNone(provider.load_writable_journal_state(journal).handoff)
                self.assertEqual(
                    provider.retained_journal_operation(journal, terminal.operation_id),
                    terminal,
                )
                if terminal.kind != "update":
                    self.assertEqual(self.image(journal, "restart"), restart_before)

    def test_terminalization_recovers_before_and_after_every_commit(self):
        for action in (
            "updates-refresh",
            "updates-install-all",
            "timezone-set",
            "accounts-open",
        ):
            names = ["terminal-00", "cursor", "handoff", "active"]
            if action == "updates-install-all":
                names.insert(0, "restart")
            for target in names:
                for after in (False, True):
                    with (
                        self.subTest(action=action, target=target, after=after),
                        self.journal() as journal,
                    ):
                        contributions = {}
                        if action == "updates-install-all":
                            contributions = dict(
                                system_restart="system",
                                session_restart="security-session",
                                application_restart=True,
                            )
                        terminal = self.finish(
                            journal, self.begin(journal, action), **contributions
                        )
                        real_commit = provider.commit_writable_journal_path

                        def crash(journal, name, payload):
                            if name == target and not after:
                                raise provider.JournalCommitError(
                                    "injected before commit"
                                )
                            result = real_commit(journal, name, payload)
                            if name == target:
                                raise provider.JournalCommitError(
                                    "injected after commit"
                                )
                            return result

                        with mock.patch.object(
                            provider, "commit_writable_journal_path", side_effect=crash
                        ):
                            with self.assertRaises(provider.JournalCommitError):
                                provider.complete_journal_terminal(
                                    journal, boot_id=self.boot_id
                                )
                        provider.load_writable_journal_state(journal)
                        provider.complete_journal_terminal(
                            journal, boot_id=self.boot_id
                        )
                        state = provider.load_writable_journal_state(journal)
                        self.assertIsNone(state.active)
                        self.assertEqual(state.terminals[0], terminal)
                        self.assertEqual(state.cursor, 1)
                        self.assertEqual(
                            state.handoff.operation_id, terminal.operation_id
                        )
                        if action == "updates-install-all":
                            self.assertEqual(state.restart.system, "system")
                            self.assertEqual(state.restart.session, "security-session")
                            self.assertEqual(state.restart.application_cutoff, 100)

    def test_boot_and_login_boundaries_never_reapply_satisfied_contributions(self):
        for new_boot, login in (
            (self.boot_id, 101),
            ("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", None),
        ):
            with self.subTest(boot=new_boot), self.journal() as journal:
                terminal = self.finish(
                    journal,
                    self.begin(journal, "updates-install-all"),
                    system_restart="system",
                    session_restart="security-session",
                    application_restart=True,
                )
                provider.complete_journal_terminal(
                    journal, boot_id=new_boot, session_started=login
                )
                state = provider.load_writable_journal_state(journal)
                self.assertEqual(state.restart.session, "none")
                self.assertFalse(state.restart.application)
                self.assertEqual(
                    state.restart.system,
                    "system" if new_boot == self.boot_id else "none",
                )
                self.assertEqual(state.terminals[0], terminal)

    def test_ring_wrap_replays_older_exact_identity_not_newest_slot(self):
        with self.journal() as journal:
            terminals = []
            for _ in range(34):
                terminal = self.finish(journal, self.begin(journal))
                provider.complete_journal_terminal(journal)
                provider.acknowledge_journal_handoff(journal, terminal.operation_id)
                terminals.append(terminal)
            self.assertEqual(
                provider.retained_journal_operation(journal, terminals[2].operation_id),
                terminals[2],
            )
            with self.assertRaises(provider.JournalAdmissionError):
                provider.retained_journal_operation(journal, terminals[0].operation_id)
            self.assertEqual(provider.load_writable_journal_state(journal).cursor, 2)

    def test_pending_and_ack_commit_errors_preserve_durable_authority(self):
        for target in ("active", "handoff"):
            for after in (False, True):
                with self.subTest(target=target, after=after), self.journal() as journal:
                    operation = None
                    if target == "handoff":
                        operation = self.finish(journal, self.begin(journal))
                        provider.complete_journal_terminal(journal)
                    real_commit = provider.commit_writable_journal_path

                    def fail(journal, name, payload):
                        self.assertEqual(name, target)
                        if after:
                            real_commit(journal, name, payload)
                        raise provider.JournalCommitError("indeterminate commit")

                    with mock.patch.object(provider, "commit_writable_journal_path", side_effect=fail):
                        with self.assertRaises(provider.JournalCommitError):
                            if target == "active":
                                self.begin(journal)
                            else:
                                provider.acknowledge_journal_handoff(journal, operation.operation_id)
                    state = provider.load_writable_journal_state(journal)
                    if target == "active":
                        self.assertEqual(state.active is not None, after)
                    else:
                        self.assertEqual(state.handoff is None, after)
                        self.assertEqual(state.terminals[0], operation)

    def test_stale_terminal_timestamp_is_rejected_before_checkpoint(self):
        with self.journal() as journal:
            terminal = self.finish(journal, self.begin(journal, "updates-install-all"))
            provider.complete_journal_terminal(journal, boot_id=self.boot_id)
            provider.acknowledge_journal_handoff(journal, terminal.operation_id)
            pending = self.begin(journal)
            interrupted = replace(
                pending, state="interrupted", finished_at=self.finished,
                terminal_monotonic=99,
            )
            before = self.image(journal, "active")
            with self.assertRaises(provider.JournalRecordError):
                provider.advance_journal_operation(journal, pending, interrupted)
            self.assertEqual(self.image(journal, "active"), before)

    def test_refresh_requires_boot_reconciliation_without_storing_a_boot_field(self):
        with self.journal() as journal:
            terminal = self.finish(journal, self.begin(journal, "updates-install-all"))
            provider.complete_journal_terminal(journal, boot_id=self.boot_id)
            provider.acknowledge_journal_handoff(journal, terminal.operation_id)
            new_boot = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
            with self.assertRaises(provider.JournalAdmissionError):
                provider.begin_journal_operation(
                    journal, "updates-refresh", self.started, "Starting",
                    transaction_path="/18_adcbcaed", boot_id=new_boot,
                )
            provider.prune_journal_restart(journal, new_boot, None)
            pending = provider.begin_journal_operation(
                journal, "updates-refresh", self.started, "Starting",
                transaction_path="/18_adcbcaed", boot_id=new_boot,
            )
            self.assertIsNone(pending.boot_id)
            interrupted = replace(
                pending, state="interrupted", finished_at=self.finished,
                terminal_monotonic=1,
            )
            provider.advance_journal_operation(journal, pending, interrupted)
            before = self.image(journal, "restart")
            provider.complete_journal_terminal(journal)
            self.assertEqual(self.image(journal, "restart"), before)

    def test_terminal_pruning_shares_the_three_commit_restart_budget(self):
        for prune_before_terminal in (False, True):
            with self.subTest(prune_before_terminal=prune_before_terminal), self.journal() as journal:
                for cutoff, contributions in (
                    (100, {"session_restart": "session"}),
                    (200, {"application_restart": True}),
                ):
                    pending = self.begin(journal, "updates-install-all")
                    running = replace(pending, state="running", **contributions)
                    provider.advance_journal_operation(journal, pending, running)
                    terminal = replace(running, state="succeeded", finished_at=self.finished, terminal_monotonic=cutoff)
                    provider.advance_journal_operation(journal, running, terminal)
                    provider.complete_journal_terminal(journal, boot_id=self.boot_id)
                    provider.acknowledge_journal_handoff(journal, terminal.operation_id)
                pending = self.begin(journal, "updates-install-all")
                real_commit = provider.commit_writable_journal_path
                with mock.patch.object(provider, "commit_writable_journal_path", wraps=real_commit) as commits:
                    provider.prune_journal_restart(journal, self.boot_id, 150)
                    if prune_before_terminal:
                        provider.prune_journal_restart(journal, self.boot_id, 250)
                    running = replace(pending, state="running")
                    provider.advance_journal_operation(journal, pending, running)
                    terminal = replace(running, state="succeeded", finished_at=self.finished, terminal_monotonic=300)
                    provider.advance_journal_operation(journal, running, terminal)
                    provider.complete_journal_terminal(journal, boot_id=self.boot_id, session_started=250)
                self.assertEqual(sum(call.args[1] == "restart" for call in commits.call_args_list), 3)


class JournalAdmissionTests(unittest.TestCase):
    boot_id = "01234567-89ab-cdef-0123-456789abcdef"
    operation_id = "op-0123456789abcdef0123456789abcdef"

    def open_initialized_chain(self, directory):
        journal = pathlib.Path(directory) / "state" / "dwm-titus" / "system-management"
        chain = provider.open_journal_directory_chain(str(journal))
        provider.initialize_journal_layout(chain.directory_descriptor, self.boot_id)
        return journal, chain

    def operation(self, *, operation_id=None, state="running", slot=0):
        terminal = state in provider.JOURNAL_OPERATION_TERMINAL_STATES
        return provider.JournalOperation(
            operation_id or self.operation_id,
            "updates-refresh",
            "2026-09-04T18:00:00Z",
            "2026-09-04T18:01:00Z" if terminal else None,
            "refresh",
            state,
            None,
            "Refreshing update metadata",
            None,
            "/1_deadbeef",
            None,
            None,
            None,
            None,
            1 if terminal else None,
            slot,
        )

    def set_sequence(self, journal, name, sequence, payload):
        image = provider.encode_journal_frame(sequence, payload)
        descriptor = journal.descriptor(name)
        os.pwrite(descriptor, image + bytes(provider.JOURNAL_FRAME_SIZE), 0)
        os.fsync(descriptor)

    def test_loads_complete_state_and_selects_the_cursor_slot(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("cursor"), "31"
                    )
                    with mock.patch.object(
                        provider.os, "urandom", return_value=b"\xab" * 16
                    ) as urandom:
                        admission = provider.prepare_journal_admission(journal)

                    self.assertEqual(admission.slot, 31)
                    self.assertEqual(admission.operation_id, f"op-{'ab' * 16}")
                    urandom.assert_called_once_with(16)
                    self.assertEqual(admission.state.cursor, 31)
                    self.assertIsNone(admission.state.active)
                    self.assertIsNone(admission.state.handoff)
                    self.assertEqual(len(admission.state.terminals), 32)
                    self.assertEqual(
                        journal.descriptor("terminal-31"),
                        journal.descriptor(f"terminal-{admission.slot:02d}"),
                    )
            finally:
                chain.close()

    def test_retries_a_retained_terminal_collision(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            terminal = self.operation(
                operation_id=f"op-{'11' * 16}", state="succeeded", slot=0
            )
            try:
                with provider.open_writable_journal(chain) as journal:
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("terminal-00"),
                        provider.encode_journal_operation(terminal),
                    )
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("cursor"), "01"
                    )
                    with mock.patch.object(
                        provider.os,
                        "urandom",
                        side_effect=(b"\x11" * 16, b"\x22" * 16),
                    ) as urandom:
                        admission = provider.prepare_journal_admission(journal)

                    self.assertEqual(admission.slot, 1)
                    self.assertEqual(admission.operation_id, f"op-{'22' * 16}")
                    self.assertEqual(urandom.call_count, 2)
            finally:
                chain.close()

    def test_rejects_restart_only_collision_after_four_attempts(self):
        restart_operation_id = f"op-{'ff' * 16}"
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    for slot in range(provider.JOURNAL_TERMINAL_COUNT):
                        terminal = self.operation(
                            operation_id=f"op-{slot + 1:032x}",
                            state="succeeded",
                            slot=slot,
                        )
                        provider._commit_journal_file_unlocked(
                            journal.descriptor(f"terminal-{slot:02d}"),
                            provider.encode_journal_operation(terminal),
                        )
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("restart"),
                        provider.encode_journal_restart(
                            provider.JournalRestart(
                                self.boot_id,
                                restart_operation_id,
                                "none",
                                "none",
                                0,
                                False,
                                0,
                            )
                        ),
                    )
                    with mock.patch.object(
                        provider.os, "urandom", return_value=b"\xff" * 16
                    ) as urandom:
                        with self.assertRaisesRegex(
                            provider.JournalAdmissionError,
                            "collision limit reached",
                        ):
                            provider.prepare_journal_admission(journal)

                    self.assertEqual(
                        urandom.call_count, provider.JOURNAL_OPERATION_ID_ATTEMPTS
                    )
            finally:
                chain.close()

    def test_rng_failure_blocks_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    with mock.patch.object(
                        provider.os, "urandom", side_effect=OSError("unavailable")
                    ) as urandom:
                        with self.assertRaisesRegex(
                            provider.JournalAdmissionError,
                            "generation failed",
                        ):
                            provider.prepare_journal_admission(journal)

                    urandom.assert_called_once_with(16)
            finally:
                chain.close()

    def test_rejects_malformed_nested_state_before_randomness(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    admission = provider.prepare_journal_admission(journal)
                    terminal = self.operation(state="succeeded", slot=0)
                    cases = {
                        "restart record": replace(admission.state, restart=None),
                        "restart ID": replace(
                            admission.state,
                            restart=replace(
                                admission.state.restart,
                                last_applied_operation_id=17,
                            ),
                        ),
                        "active ID": replace(
                            admission.state,
                            active=replace(self.operation(), operation_id=[]),
                        ),
                        "terminal ID": replace(
                            admission.state,
                            terminals=(
                                replace(terminal, operation_id="op-bad"),
                                *admission.state.terminals[1:],
                            ),
                        ),
                    }
                    for name, malformed in cases.items():
                        with self.subTest(name=name), mock.patch.object(
                            provider.os, "urandom"
                        ) as urandom:
                            with self.assertRaisesRegex(
                                provider.JournalAdmissionError,
                                "state is invalid",
                            ):
                                provider.generate_journal_operation_id(malformed)

                            urandom.assert_not_called()
            finally:
                chain.close()

    def test_scans_from_cursor_for_the_first_slot_with_commit_headroom(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("cursor"), "31"
                    )
                    self.set_sequence(
                        journal,
                        "terminal-31",
                        provider.JOURNAL_SEQUENCE_MAX - 1,
                        "",
                    )
                    self.set_sequence(
                        journal,
                        "terminal-00",
                        provider.JOURNAL_SEQUENCE_MAX - 1,
                        "",
                    )

                    admission = provider.prepare_journal_admission(journal)

                    self.assertEqual(admission.state.cursor, 31)
                    self.assertEqual(admission.slot, 1)
            finally:
                chain.close()

    def test_rejects_admission_when_every_terminal_slot_lacks_headroom(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    for slot in range(provider.JOURNAL_TERMINAL_COUNT):
                        self.set_sequence(
                            journal,
                            f"terminal-{slot:02d}",
                            provider.JOURNAL_SEQUENCE_MAX - 1,
                            "",
                        )

                    with self.assertRaisesRegex(
                        provider.JournalAdmissionError,
                        "no reusable terminal slot",
                    ):
                        provider.prepare_journal_admission(journal)
            finally:
                chain.close()

    def test_rejects_each_control_path_without_commit_headroom(self):
        payloads = provider._initial_journal_payloads(self.boot_id)
        for name, required_commits in (
            provider.JOURNAL_CONTROL_ADMISSION_COMMITS.items()
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                _journal_path, chain = self.open_initialized_chain(directory)
                try:
                    with provider.open_writable_journal(chain) as journal:
                        self.set_sequence(
                            journal,
                            name,
                            provider.JOURNAL_SEQUENCE_MAX - required_commits,
                            payloads[name],
                        )

                        with self.assertRaisesRegex(
                            provider.JournalAdmissionError,
                            "control path has no commit headroom",
                        ):
                            provider.prepare_journal_admission(journal)
                finally:
                    chain.close()

    def test_accepts_control_paths_with_the_exact_required_headroom(self):
        payloads = provider._initial_journal_payloads(self.boot_id)
        for name, required_commits in (
            provider.JOURNAL_CONTROL_ADMISSION_COMMITS.items()
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                _journal_path, chain = self.open_initialized_chain(directory)
                try:
                    with provider.open_writable_journal(chain) as journal:
                        self.set_sequence(
                            journal,
                            name,
                            provider.JOURNAL_SEQUENCE_MAX - required_commits - 1,
                            payloads[name],
                        )

                        admission = provider.prepare_journal_admission(journal)

                        self.assertEqual(admission.slot, 0)
                finally:
                    chain.close()

    def test_nonterminal_active_operation_blocks_admission_without_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("active"),
                        provider.encode_journal_operation(self.operation()),
                    )
                    active_before = os.pread(
                        journal.descriptor("active"), provider.JOURNAL_FILE_SIZE, 0
                    )
                    with self.assertRaisesRegex(
                        provider.JournalAdmissionError, "admission is blocked"
                    ):
                        provider.prepare_journal_admission(journal)
                    self.assertEqual(
                        os.pread(
                            journal.descriptor("active"),
                            provider.JOURNAL_FILE_SIZE,
                            0,
                        ),
                        active_before,
                    )
            finally:
                chain.close()

    def test_valid_terminal_handoff_blocks_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            terminal = self.operation(state="succeeded", slot=7)
            try:
                with provider.open_writable_journal(chain) as journal:
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("terminal-07"),
                        provider.encode_journal_operation(terminal),
                    )
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("cursor"), "08"
                    )
                    provider._commit_journal_file_unlocked(
                        journal.descriptor("handoff"),
                        provider.encode_journal_handoff(
                            provider.JournalHandoff(self.operation_id, 7)
                        ),
                    )

                    with self.assertRaisesRegex(
                        provider.JournalAdmissionError, "admission is blocked"
                    ):
                        provider.prepare_journal_admission(journal)
            finally:
                chain.close()

    def test_malformed_fixed_path_names_the_path_and_blocks_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            _journal_path, chain = self.open_initialized_chain(directory)
            try:
                with provider.open_writable_journal(chain) as journal:
                    descriptor = journal.descriptor("terminal-12")
                    os.pwrite(descriptor, bytes(provider.JOURNAL_FILE_SIZE), 0)
                    os.fsync(descriptor)

                    with self.assertRaisesRegex(
                        provider.JournalLayoutError, "terminal-12 is malformed"
                    ):
                        provider.prepare_journal_admission(journal)
            finally:
                chain.close()

    def test_replaced_path_is_rejected_after_complete_decode(self):
        with tempfile.TemporaryDirectory() as directory:
            journal_path, chain = self.open_initialized_chain(directory)
            active = journal_path / "active"
            detached = journal_path / "active-detached"
            image = active.read_bytes()
            original_decode = provider.decode_journal_state

            def replace_active(payloads):
                state = original_decode(payloads)
                active.rename(detached)
                active.write_bytes(image)
                os.chmod(active, 0o600)
                return state

            try:
                with self.assertRaisesRegex(
                    provider.JournalLayoutError, "active identity is unsafe"
                ):
                    with provider.open_writable_journal(chain) as journal:
                        with mock.patch.object(
                            provider,
                            "decode_journal_state",
                            side_effect=replace_active,
                        ):
                            provider.prepare_journal_admission(journal)
            finally:
                chain.close()


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
