#!/usr/bin/python3
"""Contract tests for the Phase 6 system-management snapshot."""

from __future__ import annotations

import hashlib
import importlib.util
import importlib.machinery
import pathlib
import sys
import unittest


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
