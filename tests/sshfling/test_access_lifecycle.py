import argparse
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SSHFLING_PATH = REPO_ROOT / "bin" / "sshfling"


def load_sshfling():
    loader = importlib.machinery.SourceFileLoader("sshfling_under_test", str(SSHFLING_PATH))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def write_grant(root: Path, username: str, metadata: dict, config_path: Path | None = None) -> Path:
    if config_path is not None:
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text(f"# Managed by sshfling password grant for {username}.\nMatch User {username}\n", encoding="utf-8")
        metadata["config_path"] = str(config_path)
    path = root / f"{username}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def grant_metadata(username: str, expires_at: int, created_user: bool = True) -> dict:
    metadata = {
        "version": 1,
        "auth": "password",
        "managed_by": "sshfling",
        "username": username,
        "created_user": created_user,
        "created_at": int(time.time()) - 120,
        "seconds": 30,
        "expires_at": expires_at,
        "session_wrapper": "/usr/local/libexec/sshfling-session",
        "policy_file": "/etc/sshfling/policy.json",
        "access_level": "standard",
    }
    if created_user:
        metadata.update({"user_uid": 1234, "user_gid": 1234, "user_home": f"/home/{username}"})
    return metadata


def write_cert_session(root: Path, username: str, expires_at: int) -> Path:
    material_dir = root / f"{username}-20260709T000000Z-deadbeef"
    material_dir.mkdir(parents=True)
    private_key = material_dir / "id_ed25519"
    public_key = material_dir / "id_ed25519.pub"
    certificate = material_dir / "id_ed25519-cert.pub"
    for path in [private_key, public_key, certificate]:
        path.write_text(f"{path.name}\n", encoding="utf-8")
    metadata = {
        "version": 1,
        "managed_by": "sshfling",
        "auth": "certificate",
        "username": username,
        "principal": username,
        "created_at": int(time.time()) - 120,
        "seconds": 30,
        "expires_at": expires_at,
        "private_key": str(private_key),
        "public_key": str(public_key),
        "certificate": str(certificate),
    }
    metadata_path = material_dir / "sshfling-cert.json"
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return metadata_path


class SSHFlingAccessLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sshfling = load_sshfling()

    def patch(self, name, value):
        original = getattr(self.sshfling, name)
        setattr(self.sshfling, name, value)
        self.addCleanup(lambda: setattr(self.sshfling, name, original))

    def patch_safe_identity(self, username: str) -> None:
        identity = {"username": username, "uid": 1234, "gid": 1234, "home": f"/home/{username}"}
        self.patch("is_root_equivalent_user", lambda value: False)
        self.patch("unix_user_identity", lambda value: identity if value == username else None)
        self.patch("unix_identity_mismatch", lambda value, expected: None)

    def test_prune_targeted_delete_removes_expired_created_user_only_after_session_cleanup(self) -> None:
        username = "sunitdel"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config_path = root / "sshd_config.d" / f"91-sshfling-password-{username}.conf"
            write_grant(root, username, grant_metadata(username, int(time.time()) - 5), config_path)
            self.patch_safe_identity(username)
            self.patch("command_path", lambda name: f"/usr/bin/{name}" if name in {"userdel", "ps"} else None)
            self.patch("cleanup_password_grant_sessions", lambda value, dry_run=False: {"username": value, "killed": 1, "pids": [42]})
            self.patch("delete_password_user", lambda value, dry_run=False, expected_identity=None: {"user": value, "deleted": True})
            self.patch("lock_password_user", lambda *args, **kwargs: self.fail("created user should be deleted, not locked"))

            results = self.sshfling.prune_password_grants(root, username=username, delete_users=True)

            self.assertEqual(len(results), 1)
            result = results[0]
            self.assertEqual(result["status"], "pruned")
            self.assertEqual(result["sessions"]["killed"], 1)
            self.assertTrue(result["config"]["removed"])
            self.assertTrue(result["metadata"]["removed"])
            self.assertTrue(result["user"]["deleted"])
            self.assertFalse(config_path.exists())
            self.assertFalse((root / f"{username}.json").exists())

    def test_prune_delete_users_preserves_active_grant_without_mutation(self) -> None:
        username = "sactive"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config_path = root / "sshd_config.d" / f"91-sshfling-password-{username}.conf"
            metadata_path = write_grant(root, username, grant_metadata(username, int(time.time()) + 300), config_path)
            self.patch("is_root_equivalent_user", lambda value: False)
            self.patch("remove_password_grant_config", lambda *args, **kwargs: self.fail("active grant config must not be removed"))
            self.patch("cleanup_password_grant_sessions", lambda *args, **kwargs: self.fail("active grant sessions must not be killed"))
            self.patch("delete_password_user", lambda *args, **kwargs: self.fail("active user must not be deleted"))
            self.patch("lock_password_user", lambda *args, **kwargs: self.fail("active user must not be locked"))

            results = self.sshfling.prune_password_grants(root, username=username, delete_users=True)

            self.assertEqual(results[0]["status"], "active")
            self.assertTrue(config_path.exists())
            self.assertTrue(metadata_path.exists())

    def test_prune_delete_users_preflights_userdel_before_config_removal(self) -> None:
        username = "snodelete"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config_path = root / "sshd_config.d" / f"91-sshfling-password-{username}.conf"
            metadata_path = write_grant(root, username, grant_metadata(username, int(time.time()) - 5), config_path)
            self.patch_safe_identity(username)
            self.patch("command_path", lambda name: None if name == "userdel" else f"/usr/bin/{name}")
            self.patch("remove_password_grant_config", lambda *args, **kwargs: self.fail("config must not be removed without userdel"))
            self.patch("cleanup_password_grant_sessions", lambda *args, **kwargs: self.fail("sessions must not be killed without userdel"))

            results = self.sshfling.prune_password_grants(root, username=username, delete_users=True)

            self.assertEqual(results[0]["status"], "skipped-delete-prerequisite")
            self.assertIn("userdel is required", results[0]["reason"])
            self.assertTrue(config_path.exists())
            self.assertTrue(metadata_path.exists())

    def test_prune_delete_users_locks_existing_user_instead_of_deleting(self) -> None:
        username = "sexisting"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config_path = root / "sshd_config.d" / f"91-sshfling-password-{username}.conf"
            write_grant(root, username, grant_metadata(username, int(time.time()) - 5, created_user=False), config_path)
            self.patch("is_root_equivalent_user", lambda value: False)
            self.patch("cleanup_password_grant_sessions", lambda value, dry_run=False: {"username": value, "killed": 0, "pids": []})
            self.patch("lock_password_user", lambda value, dry_run=False, expected_identity=None: {"user": value, "locked": True, "expired": True})
            self.patch("delete_password_user", lambda *args, **kwargs: self.fail("existing user must not be deleted"))

            results = self.sshfling.prune_password_grants(root, username=username, delete_users=True)

            user = results[0]["user"]
            self.assertTrue(user["locked"])
            self.assertTrue(user["existing_user"])
            self.assertEqual(user["delete_skipped"], "existing Unix user was not created by sshfling")

    def test_cert_prune_removes_only_expired_generated_material(self) -> None:
        now = int(time.time())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            expired_metadata = write_cert_session(root, "scertold", now - 5)
            active_metadata = write_cert_session(root, "scertactive", now + 300)
            expired_dir = expired_metadata.parent
            active_dir = active_metadata.parent

            results = self.sshfling.prune_certificate_sessions(root, username="scertold")

            self.assertEqual(len(results), 1)
            result = results[0]
            self.assertEqual(result["status"], "pruned")
            self.assertTrue(result["private_key"]["removed"])
            self.assertTrue(result["public_key"]["removed"])
            self.assertTrue(result["certificate"]["removed"])
            self.assertTrue(result["metadata"]["removed"])
            self.assertFalse(expired_dir.exists())
            self.assertTrue(active_metadata.exists())
            self.assertTrue((active_dir / "id_ed25519").exists())

    def test_cert_prune_all_accepts_certificate_principal_names(self) -> None:
        now = int(time.time())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            targeted_metadata = write_cert_session(root, "Deploy.User", now - 5)
            all_metadata = write_cert_session(root, "Deploy.User2", now - 5)
            targeted_dir = targeted_metadata.parent
            all_dir = all_metadata.parent

            targeted_results = self.sshfling.prune_certificate_sessions(root, username="Deploy.User")

            self.assertEqual(len(targeted_results), 1)
            self.assertEqual(targeted_results[0]["status"], "pruned")
            self.assertFalse(targeted_dir.exists())
            self.assertTrue(all_metadata.exists())

            results = self.sshfling.prune_certificate_sessions(root, all_sessions=True)
            self.assertEqual(len(results), 1)
            self.assertEqual(results[0]["status"], "pruned")
            self.assertFalse(all_dir.exists())

    def test_setup_json_errors_are_stable_for_certificate_flags_and_missing_lifetime(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = self.sshfling.main(["--json", "--public-key", "ssh-ed25519 AAAAunit", "--dry-run"])
        self.assertEqual(code, 2)
        payload = json.loads(stdout.getvalue())
        self.assertFalse(payload["ok"])
        self.assertIn("Certificate setup options require --certificate", payload["error"]["message"])

        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = self.sshfling.main(["--json", "setup", "--certificate"])
        self.assertEqual(code, 2)
        payload = json.loads(stdout.getvalue())
        self.assertFalse(payload["ok"])
        self.assertIn("explicit -t/--time", payload["error"]["message"])

    def test_setup_routes_to_password_by_default_and_certificate_only_when_explicit(self) -> None:
        calls = []
        self.patch("cmd_setup_password", lambda args: calls.append(("password", args.username)) or 0)
        self.patch("cmd_setup_certificate", lambda args: calls.append(("certificate", args.username)) or 0)

        password_args = argparse.Namespace(
            password=False,
            certificate=False,
            time=60,
            seconds=None,
            username="sdefault",
            ca_key_explicit=False,
            login_user_explicit=False,
            public_key=None,
            public_key_file=None,
            out=None,
            session_dir_explicit=False,
            key_id=None,
            source_address=None,
            no_pty=False,
        )
        cert_args = argparse.Namespace(**{**vars(password_args), "certificate": True, "username": "scert"})

        self.assertEqual(self.sshfling.cmd_setup(password_args), 0)
        self.assertEqual(self.sshfling.cmd_setup(cert_args), 0)
        self.assertEqual(calls, [("password", "sdefault"), ("certificate", "scert")])

    def test_doctor_dependency_inventory_reports_mode_specific_missing_tools(self) -> None:
        self.patch("command_path", lambda name: "/usr/bin/ssh" if name == "ssh" else None)
        payload = self.sshfling.dependency_inventory("password-server")

        self.assertFalse(payload["ok"])
        self.assertEqual(payload["dependency_ownership"], "platform-managed")
        missing = {item["name"] for item in payload["missing_required"]}
        self.assertIn("sshd", missing)
        self.assertIn("useradd", missing)
        self.assertIn("userdel", missing)

    def test_dependency_inventory_omits_failed_version_probe_output(self) -> None:
        class FailedProbe:
            returncode = 1
            stdout = ""
            stderr = "scp: unknown option -- V\n"

        self.patch("run", lambda *args, **kwargs: FailedProbe())

        self.assertIsNone(self.sshfling.command_version("scp", "/usr/bin/scp"))
        self.assertIsNone(self.sshfling.command_version("ssh", "/usr/bin/ssh"))

    def test_host_install_requires_sshd_before_writing_when_validation_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ca_pub = root / "ca.pub"
            ca_pub.write_text("ssh-ed25519 AAAAunit\n", encoding="utf-8")
            args = argparse.Namespace(
                user="svalidator",
                ca_pub=str(ca_pub),
                trusted_ca=str(root / "trusted_ca.pub"),
                principals_dir=str(root / "principals"),
                session_wrapper=str(root / "sshfling-session"),
                sshd_config=str(root / "sshd_config.conf"),
                host_user_marker_dir=str(root / "host-users"),
                principal=None,
                max_time=None,
                max_connections=None,
                policy_file=str(root / "policy.json"),
                access_level=None,
                create_user=False,
                dry_run=False,
                validate=True,
                reload=False,
                json=True,
            )
            self.patch("require_root", lambda action: None)
            self.patch("command_path", lambda name: None if name == "sshd" else f"/usr/bin/{name}")

            with self.assertRaisesRegex(self.sshfling.SSHFlingError, "sshd is required"):
                self.sshfling.cmd_host_install(args)

            self.assertFalse((root / "trusted_ca.pub").exists())
            self.assertFalse((root / "sshd_config.conf").exists())

    def test_audit_field_value_redacts_secret_named_fields(self) -> None:
        for key in ["password", "issuer_token", "private_key", "public_key", "certificate", "cookie", "authorization"]:
            self.assertEqual(self.sshfling.audit_field_value(key, "raw-secret"), self.sshfling.AUDIT_REDACTED)
        self.assertEqual(self.sshfling.audit_field_value("username", "s123"), "s123")


if __name__ == "__main__":
    unittest.main()
