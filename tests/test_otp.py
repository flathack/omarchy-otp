from __future__ import annotations

import base64
import importlib.machinery
import json
import multiprocessing
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from io import StringIO
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
OTP = importlib.machinery.SourceFileLoader(
    "omarchy_otp", str(ROOT / "bin" / "omarchy-otp")
).load_module()


def hold_store_lock(ready, release) -> None:
    with OTP.store_lock():
        ready.set()
        release.wait(timeout=2)


class TotpTests(unittest.TestCase):
    def test_rfc_6238_vectors(self) -> None:
        raw_secrets = {
            "SHA1": b"12345678901234567890",
            "SHA256": b"12345678901234567890123456789012",
            "SHA512": b"1234567890123456789012345678901234567890123456789012345678901234",
        }
        vectors = {
            59: ("94287082", "46119246", "90693936"),
            1111111109: ("07081804", "68084774", "25091201"),
            1111111111: ("14050471", "67062674", "99943326"),
            1234567890: ("89005924", "91819424", "93441116"),
            2000000000: ("69279037", "90698825", "38618901"),
            20000000000: ("65353130", "77737706", "47863826"),
        }

        for timestamp, expected in vectors.items():
            actual = []
            for algorithm in ("SHA1", "SHA256", "SHA512"):
                secret = base64.b32encode(raw_secrets[algorithm]).decode().rstrip("=")
                code, _ = OTP.totp(
                    {
                        "name": "RFC test",
                        "secret": secret,
                        "digits": 8,
                        "period": 30,
                        "algorithm": algorithm,
                    },
                    timestamp,
                )
                actual.append(code)
            self.assertEqual(tuple(actual), expected)

    def test_parse_otpauth_url(self) -> None:
        account = OTP.parse_otpauth(
            "otpauth://totp/Example%20Co:alice%40example.com"
            "?secret=JBSWY3DPEHPK3PXP&issuer=Example%20Co&digits=8&period=60&algorithm=SHA256"
        )
        self.assertEqual(account["name"], "alice@example.com")
        self.assertEqual(account["issuer"], "Example Co")
        self.assertEqual(account["digits"], 8)
        self.assertEqual(account["period"], 60)
        self.assertEqual(account["algorithm"], "SHA256")

    def test_merges_bitwarden_totp_items_without_duplicates(self) -> None:
        existing = [
            OTP.normalize_account({"name": "Existing", "secret": "JBSWY3DPEHPK3PXP"})
        ]
        items = [
            {"name": "Duplicate", "login": {"totp": "JBSWY3DPEHPK3PXP"}},
            {
                "name": "Work login",
                "login": {
                    "totp": "otpauth://totp/Example:old-name"
                    "?secret=KRUGS4ZANFZSAYJA&issuer=Example&digits=8&period=60"
                },
            },
            {"name": "No OTP", "login": {"username": "user@example.com"}},
            {"name": "Broken", "login": {"totp": "not-base32!"}},
        ]

        merged, imported, duplicates, invalid = OTP.merge_bitwarden_accounts(existing, items)

        self.assertEqual(imported, 1)
        self.assertEqual(duplicates, 1)
        self.assertEqual(invalid, 1)
        self.assertEqual(len(merged), 2)
        self.assertEqual(merged[1]["name"], "Work login")
        self.assertEqual(merged[1]["issuer"], "Example")
        self.assertEqual(merged[1]["digits"], 8)
        self.assertEqual(merged[1]["period"], 60)

    def test_rejects_malformed_accounts_cleanly(self) -> None:
        for value in (None, [], "secret"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    OTP.normalize_account(value)

        with self.assertRaises(ValueError):
            OTP.normalize_account(
                {"name": "Broken", "secret": "JBSWY3DPEHPK3PXP", "digits": None}
            )

    def test_display_rows_never_include_secrets(self) -> None:
        secret = "JBSWY3DPEHPK3PXP"
        rows = OTP.display_rows([{"name": "Example", "secret": secret}])
        serialized = json.dumps(rows)
        self.assertNotIn(secret, serialized)
        self.assertEqual(rows[0]["name"], "Example")
        uuid.UUID(rows[0]["id"])
        self.assertIn("code", rows[0])
        self.assertIn("counter", rows[0])

    def test_clipboard_clear_preserves_newer_content(self) -> None:
        with (
            mock.patch.object(sys, "stdin", StringIO("123456")),
            mock.patch.object(time, "sleep"),
            mock.patch.object(
                subprocess,
                "run",
                return_value=SimpleNamespace(returncode=0, stdout="new content"),
            ) as run,
        ):
            self.assertEqual(OTP.command_clear(30), 0)
        run.assert_called_once_with(
            ["wl-paste", "--no-newline"],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_clipboard_clear_removes_unchanged_code(self) -> None:
        paste = SimpleNamespace(returncode=0, stdout="123456")
        cleared = SimpleNamespace(returncode=0, stdout="")
        with (
            mock.patch.object(sys, "stdin", StringIO("123456")),
            mock.patch.object(time, "sleep"),
            mock.patch.object(subprocess, "run", side_effect=[paste, cleared]) as run,
        ):
            self.assertEqual(OTP.command_clear(30), 0)
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[1], mock.call(["wl-copy", "--clear"], check=False))


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.old_dir = OTP.CONFIG_DIR
        self.old_file = OTP.CONFIG_FILE
        OTP.CONFIG_DIR = Path(self.temporary.name) / "config" / "omarchy-otp"
        OTP.CONFIG_FILE = OTP.CONFIG_DIR / "accounts.json"

    def tearDown(self) -> None:
        OTP.CONFIG_DIR = self.old_dir
        OTP.CONFIG_FILE = self.old_file
        self.temporary.cleanup()

    def test_store_permissions_and_round_trip(self) -> None:
        account = OTP.normalize_account(
            {"name": "Example", "secret": "JBSWY3DPEHPK3PXP"}
        )
        OTP.save_accounts([account])

        self.assertEqual(OTP.load_accounts(), [account])
        self.assertEqual(os.stat(OTP.CONFIG_DIR).st_mode & 0o777, 0o700)
        self.assertEqual(os.stat(OTP.CONFIG_FILE).st_mode & 0o777, 0o600)
        self.assertEqual(
            os.stat(OTP.CONFIG_DIR / "accounts.lock").st_mode & 0o777, 0o600
        )

    def test_legacy_encrypted_store_migrates_ids_with_backup(self) -> None:
        legacy = {
            "name": "Legacy",
            "issuer": "Example",
            "secret": "JBSWY3DPEHPK3PXP",
            "digits": 6,
            "period": 30,
            "algorithm": "SHA1",
        }
        OTP.ensure_store()
        key = b"k" * 32
        OTP.write_json_file(OTP.CONFIG_FILE, OTP.encrypt_accounts([legacy], key))

        with mock.patch.object(OTP, "store_key", return_value=key):
            migrated = OTP.load_accounts()

        uuid.UUID(migrated[0]["id"])
        active = json.loads(OTP.CONFIG_FILE.read_text(encoding="utf-8"))
        self.assertTrue(OTP.encrypted_document(active))
        self.assertEqual(OTP.decrypt_accounts(active, key), migrated)
        backups = list(OTP.CONFIG_DIR.glob("accounts.json.backup-*"))
        self.assertEqual(len(backups), 1)
        backup = json.loads(backups[0].read_text(encoding="utf-8"))
        self.assertEqual(OTP.decrypt_accounts(backup, key), [legacy])

    def test_store_lock_serializes_access(self) -> None:
        OTP.ensure_store()
        context = multiprocessing.get_context("fork")
        ready = context.Event()
        release = context.Event()
        process = context.Process(target=hold_store_lock, args=(ready, release))
        process.start()
        self.assertTrue(ready.wait(timeout=2))

        finished = threading.Event()
        loader = threading.Thread(target=lambda: (OTP.load_accounts(), finished.set()))
        loader.start()
        self.assertFalse(finished.wait(timeout=0.1))
        release.set()
        self.assertTrue(finished.wait(timeout=2))
        loader.join(timeout=2)
        process.join(timeout=2)

        self.assertEqual(process.exitcode, 0)

    def test_encrypted_store_round_trip_and_authentication(self) -> None:
        account = OTP.normalize_account(
            {"name": "Encrypted", "secret": "JBSWY3DPEHPK3PXP"}
        )
        OTP.save_accounts([account])
        backup = OTP.CONFIG_DIR / "accounts.json.backup-test"
        backup.write_text(json.dumps([account]), encoding="utf-8")
        os.chmod(backup, 0o600)
        key = b"k" * 32

        with mock.patch.object(OTP, "store_key", return_value=key):
            converted, unchanged = OTP.convert_store_files(encrypt=True)
            self.assertEqual((converted, unchanged), (2, 0))
            serialized = OTP.CONFIG_FILE.read_text(encoding="utf-8")
            self.assertNotIn(account["secret"], serialized)
            self.assertEqual(OTP.load_accounts(), [account])

            account2 = OTP.normalize_account(
                {"name": "Second", "secret": "KRUGS4ZANFZSAYJA"}
            )
            OTP.save_accounts([account, account2])
            self.assertEqual(OTP.load_accounts(), [account, account2])

            document = json.loads(OTP.CONFIG_FILE.read_text(encoding="utf-8"))
            ciphertext = bytearray(base64.b64decode(document["ciphertext"]))
            ciphertext[-1] ^= 1
            document["ciphertext"] = base64.b64encode(ciphertext).decode()
            OTP.write_json_file(OTP.CONFIG_FILE, document)
            with self.assertRaisesRegex(ValueError, "failed authentication"):
                OTP.load_accounts()

    def test_encrypted_store_can_be_decrypted(self) -> None:
        account = OTP.normalize_account(
            {"name": "Example", "secret": "JBSWY3DPEHPK3PXP"}
        )
        OTP.save_accounts([account])
        key = b"k" * 32

        with mock.patch.object(OTP, "store_key", return_value=key):
            OTP.convert_store_files(encrypt=True, include_backups=False)
            converted, unchanged = OTP.convert_store_files(
                encrypt=False, include_backups=False
            )

        self.assertEqual((converted, unchanged), (1, 0))
        self.assertEqual(json.loads(OTP.CONFIG_FILE.read_text()), [account])

    def test_existing_encrypted_store_never_creates_a_replacement_key(self) -> None:
        account = OTP.normalize_account(
            {"name": "Example", "secret": "JBSWY3DPEHPK3PXP"}
        )
        OTP.ensure_store()
        key = b"k" * 32
        OTP.write_json_file(OTP.CONFIG_FILE, OTP.encrypt_accounts([account], key))

        with mock.patch.object(OTP, "store_key", return_value=key) as get_key:
            converted, unchanged = OTP.convert_store_files(
                encrypt=True, include_backups=False
            )

        self.assertEqual((converted, unchanged), (0, 1))
        get_key.assert_called_once_with(create=False)

    def test_remove_updates_encrypted_store(self) -> None:
        first = OTP.normalize_account(
            {"name": "First", "secret": "JBSWY3DPEHPK3PXP"}
        )
        second = OTP.normalize_account(
            {"name": "Second", "secret": "KRUGS4ZANFZSAYJA"}
        )
        OTP.save_accounts([first, second])
        key = b"k" * 32

        with (
            mock.patch.object(OTP, "store_key", return_value=key),
            mock.patch.object(sys, "stdout", new_callable=StringIO),
        ):
            OTP.convert_store_files(encrypt=True, include_backups=False)
            self.assertEqual(OTP.command_remove(0, assume_yes=True), 0)
            self.assertEqual(OTP.load_accounts(), [second])

        serialized = OTP.CONFIG_FILE.read_text(encoding="utf-8")
        self.assertNotIn(first["secret"], serialized)
        self.assertNotIn(second["secret"], serialized)

    def test_remove_uses_stable_id_after_reordering(self) -> None:
        first = OTP.normalize_account(
            {"name": "First", "secret": "JBSWY3DPEHPK3PXP"}
        )
        second = OTP.normalize_account(
            {"name": "Second", "secret": "KRUGS4ZANFZSAYJA"}
        )
        OTP.save_accounts([second, first])

        with mock.patch.object(sys, "stdout", new_callable=StringIO):
            self.assertEqual(OTP.command_remove(first["id"], assume_yes=True), 0)

        self.assertEqual(OTP.load_accounts(), [second])

    def test_rejects_symlinked_store(self) -> None:
        OTP.CONFIG_DIR.mkdir(mode=0o700, parents=True)
        target = OTP.CONFIG_DIR / "real.json"
        target.write_text("[]\n", encoding="utf-8")
        OTP.CONFIG_FILE.symlink_to(target)
        with self.assertRaises(ValueError):
            OTP.ensure_store()


if __name__ == "__main__":
    unittest.main()
