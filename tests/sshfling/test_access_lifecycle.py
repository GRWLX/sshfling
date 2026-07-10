import argparse
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SSHFLING_PATH = REPO_ROOT / "bin" / "sshfling"


def load_sshfling(path=SSHFLING_PATH):
    loader = importlib.machinery.SourceFileLoader("sshfling_under_test", str(path))
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

    def test_template_copy_restores_declared_executable_mode(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source-script"
            destination = root / "project/scripts/install-local.sh"
            source.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            source.chmod(0o644)

            status = self.sshfling.copy_template_file(
                source,
                destination,
                force=True,
                mode=0o755,
            )

            self.assertEqual(status, "copied")
            self.assertEqual(destination.stat().st_mode & 0o777, 0o755)

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
        self.patch("sshd_configuration_files", lambda: [])
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
        self.assertIn("jq", missing)

    def test_managed_accounts_use_root_owned_dispatcher_path(self) -> None:
        self.assertEqual(
            self.sshfling.managed_login_shell_path("/usr/local/libexec/sshfling-session"),
            Path("/usr/local/libexec/sshfling-login-shell"),
        )

    def test_forced_session_executables_reject_writable_parent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            unsafe_parent = Path(tmp) / "unsafe"
            unsafe_parent.mkdir()
            unsafe_parent.chmod(0o777)
            self.patch("is_admin", lambda: True)

            with self.assertRaisesRegex(self.sshfling.SSHFlingError, "non-root-managed directory"):
                self.sshfling.prepare_root_managed_parent(
                    unsafe_parent / "sshfling-session",
                    "install forced-session executables",
                )

    def test_managed_login_shell_binds_wrapper_and_policy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            wrapper = root / "sshfling-session"
            policy = root / "policy.json"
            destination = root / "sshfling-login-shell"

            result = self.sshfling.install_managed_login_shell(wrapper, policy, destination)

            content = destination.read_text(encoding="utf-8")
            self.assertIn(f"expected_wrapper={wrapper}", content)
            self.assertIn(f"expected_policy={policy}", content)
            self.assertIn(f"expected_bash={self.sshfling.trusted_root_executable('bash')}", content)
            self.assertTrue(destination.stat().st_mode & 0o111)
            self.assertEqual(result["path"], str(destination))

            with self.assertRaisesRegex(self.sshfling.SSHFlingError, "force-command-safe"):
                self.sshfling.install_managed_login_shell(
                    root / "unsafe wrapper",
                    policy,
                    destination,
                )

    def test_sshd_environment_validation_rejects_user_controlled_loader_variables(self) -> None:
        class Result:
            returncode = 0
            stderr = ""

            def __init__(self, stdout=""):
                self.stdout = stdout

        calls = []

        def safe_run(command, **kwargs):
            calls.append(command)
            if command[1] == "-T":
                return Result("acceptenv LANG\nacceptenv LC_*\npermituserenvironment no\n")
            return Result()

        self.patch("run", safe_run)
        result = self.sshfling.validate_sshd_effective(
            "senv",
            require_safe_environment=True,
        )
        self.assertEqual(result["validated_environment"], "sshd -T")
        self.assertEqual([command[1] for command in calls], ["-t", "-T"])

        unsafe_outputs = [
            "acceptenv LANG\npermituserenvironment yes\n",
            "acceptenv LANG\npermituserenvironment .ssh/environment\n",
            "acceptenv LD_PRELOAD\npermituserenvironment no\n",
            "acceptenv LD_*\npermituserenvironment no\n",
            "acceptenv BASH_FUNC_*\npermituserenvironment no\n",
            "acceptenv *\npermituserenvironment no\n",
            "acceptenv LANG\n",
        ]
        for output in unsafe_outputs:
            with self.subTest(output=output):
                self.sshfling.run = lambda command, **kwargs: Result(output if command[1] == "-T" else "")
                with self.assertRaisesRegex(self.sshfling.SSHFlingError, "Unsafe sshd environment policy"):
                    self.sshfling.validate_sshd_effective(
                        "senv",
                        require_safe_environment=True,
                    )

        self.sshfling.run = lambda command, **kwargs: Result(
            "permitopen none.example:22\npermituserenvironment no\n"
            if command[1] == "-T" else ""
        )
        with self.assertRaises(self.sshfling.SSHFlingError):
            self.sshfling.validate_sshd_effective(
                "senv",
                expected_lines=["permitopen none"],
            )

        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "sshd_config"
            config.write_text(
                "PermitUserEnvironment no\n"
                "Match Address 10.0.0.0/8\n"
                "    AcceptEnv LD_* BASH_FUNC_*\n",
                encoding="utf-8",
            )
            self.sshfling.run = safe_run
            self.sshfling.sshd_configuration_files = lambda: [config]
            with self.assertRaises(self.sshfling.SSHFlingError) as raised:
                self.sshfling.validate_sshd_effective(
                    "senv",
                    require_safe_environment=True,
                )
            matches = raised.exception.details["dangerous_accept_env"]
            self.assertTrue(any(item["source"] == str(config) for item in matches))

    def test_password_rollback_preserves_login_shell_when_created_user_delete_fails(self) -> None:
        username = "srollback"
        identity = {"username": username, "uid": 1234, "gid": 1234, "home": f"/home/{username}"}
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            wrapper = root / "sshfling-session"
            login_shell = root / "sshfling-login-shell"
            args = argparse.Namespace(
                username=username,
                policy_file=str(root / "policy.json"),
                access_level=None,
                time=30,
                seconds=None,
                allow_existing_user=False,
                password_grant_dir=str(root / "grants"),
                password_sshd_config_dir=str(root / "sshd_config.d"),
                session_wrapper=str(wrapper),
                dry_run=False,
                validate=True,
                json=True,
            )
            self.patch("require_root", lambda action: None)
            self.patch("require_password_host_tools", lambda: None)
            self.patch("is_root_equivalent_user", lambda value: False)
            self.patch("unix_user_exists", lambda value: False)
            self.patch("prune_password_grants", lambda *values, **kwargs: [])
            self.patch(
                "ensure_unix_user",
                lambda *values, **kwargs: {"user": username, "created": True, "identity": identity},
            )
            self.patch("provision_session_locks", lambda *values, **kwargs: {"session_locks": "provisioned"})
            self.patch("reload_sshd", lambda: {"reloaded": "sshd"})
            validation_calls = []
            self.patch(
                "validate_sshd_effective",
                lambda *values, **kwargs: validation_calls.append(kwargs) or {"validated": True},
            )
            self.patch(
                "set_user_password",
                lambda *values, **kwargs: (_ for _ in ()).throw(self.sshfling.SSHFlingError("password failure")),
            )
            self.patch(
                "delete_password_user",
                lambda *values, **kwargs: (_ for _ in ()).throw(self.sshfling.SSHFlingError("delete failure")),
            )

            with self.assertRaises(self.sshfling.SSHFlingError) as raised:
                self.sshfling.cmd_setup_password(args)

            self.assertTrue(login_shell.exists())
            self.assertTrue(wrapper.exists())
            preserved = [
                item for item in raised.exception.details["rollback"]
                if item.get("path") in {str(wrapper), str(login_shell)} and item.get("status") == "preserved"
            ]
            self.assertEqual(len(preserved), 2)
            self.assertTrue(validation_calls[0]["require_safe_environment"])

    def test_password_rollback_preserves_enforcement_when_native_create_cleanup_fails(self) -> None:
        username = "scleanup"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            wrapper = root / "sshfling-session"
            login_shell = root / "sshfling-login-shell"
            config_path = root / "sshd_config.d" / f"91-sshfling-password-{username}.conf"
            metadata_path = root / "grants" / f"{username}.json"
            args = argparse.Namespace(
                username=username,
                policy_file=str(root / "policy.json"),
                access_level=None,
                time=30,
                seconds=None,
                allow_existing_user=False,
                password_grant_dir=str(root / "grants"),
                password_sshd_config_dir=str(root / "sshd_config.d"),
                session_wrapper=str(wrapper),
                dry_run=False,
                validate=True,
                json=True,
            )
            cleanup_record = {
                "record": "result",
                "status": "cleanup-failed",
                "user": username,
                "created": "true",
                "cleanup_confirmed": "false",
            }
            self.patch("require_root", lambda action: None)
            self.patch("require_password_host_tools", lambda: None)
            self.patch("is_root_equivalent_user", lambda value: False)
            self.patch("unix_user_exists", lambda value: False)
            self.patch("prune_password_grants", lambda *values, **kwargs: [])
            self.patch("reload_sshd", lambda: {"reloaded": "sshd"})
            self.patch("validate_sshd_effective", lambda *values, **kwargs: {"validated": True})
            self.patch(
                "ensure_unix_user",
                lambda *values, **kwargs: (_ for _ in ()).throw(
                    self.sshfling.SSHFlingError(
                        "native cleanup failed",
                        action="create",
                        records=[cleanup_record],
                    )
                ),
            )
            self.patch(
                "delete_password_user",
                lambda *values, **kwargs: self.fail("outer rollback must not delete an unverified residual account"),
            )

            with self.assertRaises(self.sshfling.SSHFlingError) as raised:
                self.sshfling.cmd_setup_password(args)

            self.assertTrue(wrapper.exists())
            self.assertTrue(login_shell.exists())
            self.assertTrue(config_path.exists())
            self.assertFalse(metadata_path.exists())
            preserved = {
                item["path"] for item in raised.exception.details["rollback"]
                if item.get("status") == "preserved" and "path" in item
            }
            self.assertEqual(preserved, {str(wrapper), str(login_shell), str(config_path)})
            self.assertTrue(any(item.get("native_result") == cleanup_record for item in raised.exception.details["rollback"]))

    def test_native_session_lock_tool_matches_supported_platforms(self) -> None:
        original_platform = self.sshfling.sys.platform
        self.addCleanup(setattr, self.sshfling.sys, "platform", original_platform)
        self.patch("command_path", lambda name: f"/usr/bin/{name}" if name == "lockf" else None)

        self.sshfling.sys.platform = "linux"
        self.assertIsNone(self.sshfling.native_session_lock_tool_path())
        self.sshfling.sys.platform = "darwin"
        self.assertEqual(self.sshfling.native_session_lock_tool_path(), "/usr/bin/lockf")
        self.sshfling.sys.platform = "freebsd14"
        self.assertEqual(self.sshfling.native_session_lock_tool_path(), "/usr/bin/lockf")

    def test_lock_provisioning_invokes_root_owned_bash_in_privileged_mode(self) -> None:
        class Result:
            returncode = 0
            stderr = ""
            stdout = "result\tstatus=provisioned\tuser=slocks\tuid=1234\tslots=10\tlock_root=/locks/1234\n"

        captured = []
        trusted_bash = self.sshfling.trusted_root_executable("bash")
        self.patch("run", lambda command, **kwargs: captured.append(command) or Result())

        result = self.sshfling.provision_session_locks(
            "/usr/local/libexec/sshfling-session",
            "slocks",
            expected_identity={"uid": 1234},
        )

        self.assertEqual(captured[0][:2], [str(trusted_bash), "-p"])
        self.assertEqual(result["session_locks"], "provisioned")

    def test_password_user_create_race_is_not_claimed_without_explicit_consent(self) -> None:
        username = "srace"

        class CreatedElsewhere:
            returncode = 0
            stderr = ""
            stdout = ""

        records = [{"record": "result", "status": "present", "user": username, "created": "false"}]
        identity = {"username": username, "uid": 1234, "gid": 1234, "home": f"/home/{username}"}
        self.patch("unix_user_exists", lambda value: False)
        self.patch("run_native_linux_account", lambda *args, **kwargs: (CreatedElsewhere(), records))
        self.patch("unix_user_identity", lambda value: identity)

        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "appeared during setup"):
            self.sshfling.ensure_unix_user(username, "/bin/sh")

        result = self.sshfling.ensure_unix_user(username, "/bin/sh", allow_existing=True)
        self.assertFalse(result["created"])
        self.assertEqual(result["identity"], identity)

    def test_password_user_create_rejects_wrong_login_shell_result(self) -> None:
        username = "swrongshell"

        class SuccessfulBackend:
            returncode = 0
            stderr = ""
            stdout = ""

        records = [{
            "record": "result",
            "status": "created",
            "user": username,
            "created": "true",
            "shell": "/bin/bash",
        }]
        self.patch("unix_user_exists", lambda value: False)
        self.patch("run_native_linux_account", lambda *args, **kwargs: (SuccessfulBackend(), records))

        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "wrong login shell"):
            self.sshfling.ensure_unix_user(username, "/usr/local/libexec/sshfling-login-shell")

    def test_set_password_rejects_success_without_matching_result(self) -> None:
        class SuccessfulBackend:
            returncode = 0
            stderr = ""
            stdout = ""

        self.patch("run_native_linux_account", lambda *args, **kwargs: (SuccessfulBackend(), []))
        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "0 result records"):
            self.sshfling.set_user_password("sresult", "secret")

        wrong_user = [{
            "record": "result",
            "status": "updated",
            "user": "someoneelse",
            "password_set": "true",
        }]
        self.patch("run_native_linux_account", lambda *args, **kwargs: (SuccessfulBackend(), wrong_user))
        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "wrong user"):
            self.sshfling.set_user_password("sresult", "secret")

    def test_host_create_user_race_does_not_write_ownership_marker(self) -> None:
        username = "shostrace"

        class CreatedElsewhere:
            returncode = 0
            stderr = ""
            stdout = ""

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ca_pub = root / "ca.pub"
            ca_pub.write_text("ssh-ed25519 AAAAunit\n", encoding="utf-8")
            args = argparse.Namespace(
                user=username,
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
                create_user=True,
                dry_run=False,
                validate=True,
                reload=False,
                json=True,
            )
            records = [{"record": "result", "status": "present", "user": username, "created": "false"}]
            identity = {"username": username, "uid": 1234, "gid": 1234, "home": f"/home/{username}"}
            self.patch("require_root", lambda action: None)
            self.patch("require_native_policy_parser", lambda dry_run=False: None)
            self.patch("require_native_session_lock_tool", lambda dry_run=False: None)
            self.patch("require_native_identity_backend", lambda: None)
            self.patch("require_sshd_for_validation", lambda validate, dry_run=False: None)
            self.patch("unix_user_exists", lambda value: False)
            self.patch("run_native_linux_account", lambda *values, **kwargs: (CreatedElsewhere(), records))
            self.patch("unix_user_identity", lambda value: identity)
            self.patch(
                "provision_session_locks",
                lambda *values, **kwargs: {"user": username, "session_locks": "provisioned"},
            )
            validation_calls = []
            self.patch(
                "validate_sshd_effective",
                lambda *values, **kwargs: validation_calls.append(kwargs) or {"validated": True},
            )
            self.patch("write_host_user_marker", lambda *values, **kwargs: self.fail("race-created user must not be marked as owned"))

            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(self.sshfling.cmd_host_install(args), 0)

            self.assertFalse((root / "host-users" / f"{username}.json").exists())
            self.assertTrue(validation_calls[0]["require_safe_environment"])

    def test_host_rollback_preserves_enforcement_when_created_user_delete_fails(self) -> None:
        username = "shostrollback"

        class CreatedUser:
            returncode = 0
            stderr = ""
            stdout = ""

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ca_pub = root / "ca.pub"
            ca_pub.write_text("ssh-ed25519 AAAAunit\n", encoding="utf-8")
            wrapper = root / "sshfling-session"
            login_shell = root / "sshfling-login-shell"
            sshd_config = root / "sshd_config.conf"
            marker = root / "host-users" / f"{username}.json"
            identity = {"username": username, "uid": 1234, "gid": 1234, "home": f"/home/{username}"}
            args = argparse.Namespace(
                user=username,
                ca_pub=str(ca_pub),
                trusted_ca=str(root / "trusted_ca.pub"),
                principals_dir=str(root / "principals"),
                session_wrapper=str(wrapper),
                sshd_config=str(sshd_config),
                host_user_marker_dir=str(root / "host-users"),
                principal=None,
                max_time=None,
                max_connections=None,
                policy_file=str(root / "policy.json"),
                access_level=None,
                create_user=True,
                dry_run=False,
                validate=True,
                reload=False,
                json=True,
            )
            self.patch("require_root", lambda action: None)
            self.patch("require_native_policy_parser", lambda dry_run=False: None)
            self.patch("require_native_session_lock_tool", lambda dry_run=False: None)
            self.patch("require_native_identity_backend", lambda: None)
            self.patch("require_certificate_user_tools", lambda dry_run=False: None)
            self.patch("require_sshd_for_validation", lambda validate, dry_run=False: None)
            self.patch("unix_user_exists", lambda value: False)

            def create_user(action, value, shell, **kwargs):
                self.assertEqual(action, "create-certificate-user")
                return CreatedUser(), [{
                    "record": "result",
                    "status": "created",
                    "user": value,
                    "created": "true",
                    "unlocked": "true",
                    "shell": shell,
                    "uid": "1234",
                    "gid": "1234",
                    "home": f"/home/{value}",
                }]

            self.patch("run_native_linux_account", create_user)
            self.patch("unix_user_identity", lambda value: identity)
            self.patch("provision_session_locks", lambda *values, **kwargs: {"session_locks": "provisioned"})
            self.patch(
                "validate_sshd_effective",
                lambda *values, **kwargs: (_ for _ in ()).throw(self.sshfling.SSHFlingError("validation failure")),
            )
            self.patch(
                "delete_password_user",
                lambda *values, **kwargs: {"user": username, "status": "skipped-user-mismatch"},
            )

            with self.assertRaises(self.sshfling.SSHFlingError) as raised:
                self.sshfling.cmd_host_install(args)

            self.assertTrue(wrapper.exists())
            self.assertTrue(login_shell.exists())
            self.assertTrue(sshd_config.exists())
            self.assertTrue(marker.exists())
            self.assertFalse((root / "trusted_ca.pub").exists())
            self.assertFalse((root / "principals" / username).exists())
            preserved = {
                item["path"] for item in raised.exception.details["rollback"]
                if item.get("status") == "preserved"
            }
            self.assertEqual(
                preserved,
                {str(wrapper), str(login_shell), str(sshd_config), str(marker)},
            )

    def test_host_rollback_preserves_enforcement_when_native_create_cleanup_fails(self) -> None:
        username = "shostcleanup"
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ca_pub = root / "ca.pub"
            ca_pub.write_text("ssh-ed25519 AAAAunit\n", encoding="utf-8")
            wrapper = root / "sshfling-session"
            login_shell = root / "sshfling-login-shell"
            sshd_config = root / "sshd_config.conf"
            marker = root / "host-users" / f"{username}.json"
            args = argparse.Namespace(
                user=username,
                ca_pub=str(ca_pub),
                trusted_ca=str(root / "trusted_ca.pub"),
                principals_dir=str(root / "principals"),
                session_wrapper=str(wrapper),
                sshd_config=str(sshd_config),
                host_user_marker_dir=str(root / "host-users"),
                principal=None,
                max_time=None,
                max_connections=None,
                policy_file=str(root / "policy.json"),
                access_level=None,
                create_user=True,
                dry_run=False,
                validate=True,
                reload=False,
                json=True,
            )
            cleanup_record = {
                "record": "result",
                "status": "cleanup-failed",
                "user": username,
                "created": "true",
                "cleanup_confirmed": "false",
            }
            self.patch("require_root", lambda action: None)
            self.patch("require_native_policy_parser", lambda dry_run=False: None)
            self.patch("require_native_session_lock_tool", lambda dry_run=False: None)
            self.patch("require_native_identity_backend", lambda: None)
            self.patch("require_certificate_user_tools", lambda dry_run=False: None)
            self.patch("require_sshd_for_validation", lambda validate, dry_run=False: None)
            self.patch("unix_user_exists", lambda value: False)
            self.patch(
                "run_native_linux_account",
                lambda *values, **kwargs: (_ for _ in ()).throw(
                    self.sshfling.SSHFlingError(
                        "native cleanup failed",
                        action="create-certificate-user",
                        records=[cleanup_record],
                    )
                ),
            )
            self.patch(
                "delete_password_user",
                lambda *values, **kwargs: self.fail("outer rollback must not delete an unverified residual account"),
            )

            with self.assertRaises(self.sshfling.SSHFlingError) as raised:
                self.sshfling.cmd_host_install(args)

            self.assertTrue(wrapper.exists())
            self.assertTrue(login_shell.exists())
            self.assertTrue(sshd_config.exists())
            self.assertFalse(marker.exists())
            self.assertFalse((root / "trusted_ca.pub").exists())
            self.assertFalse((root / "principals" / username).exists())
            preserved = {
                item["path"] for item in raised.exception.details["rollback"]
                if item.get("status") == "preserved" and "path" in item
            }
            self.assertEqual(preserved, {str(wrapper), str(login_shell), str(sshd_config)})
            self.assertTrue(any(item.get("native_result") == cleanup_record for item in raised.exception.details["rollback"]))

    def test_unix_identity_backend_failure_is_not_treated_as_missing(self) -> None:
        class FailedIdentity:
            returncode = 3
            stderr = "identity lookup failed"
            stdout = ""

        self.patch("native_unix_identity_helper", lambda required=False: Path("/native/helper"))
        self.patch("run", lambda *args, **kwargs: FailedIdentity())

        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "identity lookup failed"):
            self.sshfling.unix_user_identity("sidentity")

    def test_native_unix_identity_classifies_uid_zero_alias(self) -> None:
        self.patch("native_unix_identity_helper", lambda required=False: Path("/native/helper"))
        self.patch(
            "run_native_unix_identity",
            lambda username: {
                "record": "result",
                "status": "present",
                "user": username,
                "uid": "0",
                "gid": "0",
                "home": "/root-alias",
            },
        )

        self.assertTrue(self.sshfling.is_root_equivalent_user("rootalias"))
        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "root-equivalent"):
            self.sshfling.validate_access_level_for_username("rootalias", "standard")

    def test_native_unix_identity_rejects_noncanonical_ids(self) -> None:
        self.patch("native_unix_identity_helper", lambda required=False: Path("/native/helper"))
        self.patch(
            "run_native_unix_identity",
            lambda username: {
                "record": "result",
                "status": "present",
                "user": username,
                "uid": "00",
                "gid": "1000",
                "home": "/home/noncanonical",
            },
        )

        with self.assertRaisesRegex(self.sshfling.SSHFlingError, "invalid identity"):
            self.sshfling.unix_user_identity("noncanonical")

    def test_custom_prefix_install_discovers_native_account_helper(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            prefix = Path(tmp)
            cli = prefix / "bin" / "sshfling"
            helper = prefix / "libexec" / "sshfling" / "sshfling-linux-account"
            identity_helper = prefix / "libexec" / "sshfling" / "sshfling-unix-identity"
            cli.parent.mkdir(parents=True)
            helper.parent.mkdir(parents=True)
            shutil.copy2(SSHFLING_PATH, cli)
            shutil.copy2(REPO_ROOT / "native" / "sshfling-linux-account", helper)
            shutil.copy2(REPO_ROOT / "native" / "sshfling-unix-identity", identity_helper)

            installed = load_sshfling(cli)

            self.assertEqual(installed.native_linux_account_helper(), helper.resolve())
            self.assertEqual(installed.native_unix_identity_helper(), identity_helper.resolve())

    def test_bundled_package_discovers_native_helpers_without_environment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_dir = Path(tmp) / "sshfling"
            cli = package_dir / "cli.py"
            helper_dir = package_dir / "templates" / "native"
            helper_dir.mkdir(parents=True)
            shutil.copy2(SSHFLING_PATH, cli)
            shutil.copy2(REPO_ROOT / "native" / "sshfling-linux-account", helper_dir)
            shutil.copy2(REPO_ROOT / "native" / "sshfling-unix-identity", helper_dir)

            installed = load_sshfling(cli)

            self.assertEqual(
                installed.native_linux_account_helper(),
                (helper_dir / "sshfling-linux-account").resolve(),
            )
            self.assertEqual(
                installed.native_unix_identity_helper(),
                (helper_dir / "sshfling-unix-identity").resolve(),
            )

    def test_privileged_helper_discovery_ignores_environment_override(self) -> None:
        if not self.sshfling.is_admin():
            self.skipTest("privileged helper discovery requires an administrative test process")
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "sshfling-linux-account"
            fake.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            fake.chmod(0o755)
            previous = os.environ.get("SSHFLING_LINUX_ACCOUNT_HELPER")
            os.environ["SSHFLING_LINUX_ACCOUNT_HELPER"] = str(fake)
            self.addCleanup(
                lambda: (
                    os.environ.pop("SSHFLING_LINUX_ACCOUNT_HELPER", None)
                    if previous is None
                    else os.environ.__setitem__("SSHFLING_LINUX_ACCOUNT_HELPER", previous)
                )
            )

            helper = self.sshfling.native_linux_account_helper(required=True)
            self.assertNotEqual(helper, fake.resolve())

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
