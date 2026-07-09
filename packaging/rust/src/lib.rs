//! Rust launcher API for the bundled SSHFling command-line runtime.

use std::env;
use std::error::Error as StdError;
use std::ffi::{OsStr, OsString};
use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

/// Version of this launcher crate.
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

static BUNDLED_FILES: &[(&str, &[u8])] = include!(concat!(env!("OUT_DIR"), "/bundled_files.rs"));

const EXECUTABLE_FILES: &[&str] = &[
    "runtime/sshfling.py",
    "runtime/templates/native/sshfling-linux-account",
    "runtime/templates/native/sshfling-unix-identity",
    "runtime/templates/production/sshfling-session",
    "runtime/templates/scripts/create-network.sh",
    "runtime/templates/scripts/generate-ssh-key.sh",
    "runtime/templates/scripts/install-local.sh",
    "runtime/templates/scripts/uninstall-local.sh",
    "runtime/templates/ssh-client/entrypoint.sh",
    "runtime/templates/ssh-server/entrypoint.sh",
    "runtime/templates/ssh-server/limited-session.sh",
];

/// Executable and fixed arguments for a possible Python interpreter.
#[derive(Debug, Clone, Eq, PartialEq)]
pub struct PythonCandidate {
    pub program: OsString,
    pub args: Vec<OsString>,
}

/// Error returned by the Rust launcher.
#[derive(Debug)]
pub enum Error {
    CliExit(i32),
    Io(io::Error),
    PythonNotFound,
}

impl Error {
    /// Exit status suitable for the launcher process.
    pub fn exit_code(&self) -> i32 {
        match self {
            Self::CliExit(code) if *code > 0 => *code,
            _ => 1,
        }
    }

    /// Whether the bundled Python CLI already reported this error.
    pub fn is_cli_exit(&self) -> bool {
        matches!(self, Self::CliExit(_))
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::CliExit(code) => write!(formatter, "sshfling exited with status {code}"),
            Self::Io(error) => write!(formatter, "could not run sshfling: {error}"),
            Self::PythonNotFound => write!(
                formatter,
                "Python 3 is required; set SSHFLING_PYTHON to its executable"
            ),
        }
    }
}

impl StdError for Error {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Io(error) => Some(error),
            _ => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

/// Returns interpreter choices in platform preference order.
pub fn python_candidates() -> Vec<PythonCandidate> {
    let mut candidates = Vec::with_capacity(4);
    if let Some(configured) = env::var_os("SSHFLING_PYTHON").filter(|value| !value.is_empty()) {
        candidates.push(PythonCandidate {
            program: configured,
            args: Vec::new(),
        });
    }
    if cfg!(windows) {
        candidates.push(PythonCandidate {
            program: OsString::from("py"),
            args: vec![OsString::from("-3")],
        });
        candidates.push(PythonCandidate {
            program: OsString::from("python"),
            args: Vec::new(),
        });
        candidates.push(PythonCandidate {
            program: OsString::from("python3"),
            args: Vec::new(),
        });
    } else {
        candidates.push(PythonCandidate {
            program: OsString::from("python3"),
            args: Vec::new(),
        });
        candidates.push(PythonCandidate {
            program: OsString::from("python"),
            args: Vec::new(),
        });
    }
    candidates
}

/// Executes SSHFling with inherited standard streams.
pub fn run<I, S>(args: I) -> Result<(), Error>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let runtime = RuntimeDirectory::create()?;
    let cli_args: Vec<OsString> = args
        .into_iter()
        .map(|arg| arg.as_ref().to_os_string())
        .collect();

    for candidate in python_candidates() {
        let mut command = Command::new(&candidate.program);
        command
            .args(&candidate.args)
            .arg(runtime.script_path())
            .args(&cli_args)
            .env("PYTHONUNBUFFERED", "1")
            .env("SSHFLING_TEMPLATE_DIR", runtime.template_dir());

        match command.status() {
            Ok(status) if status.success() => return Ok(()),
            Ok(status) => return Err(Error::CliExit(status.code().unwrap_or(1))),
            Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
            Err(error) => return Err(Error::Io(error)),
        }
    }
    Err(Error::PythonNotFound)
}

struct RuntimeDirectory {
    root: PathBuf,
}

impl RuntimeDirectory {
    fn create() -> io::Result<Self> {
        let root = create_temp_directory()?;
        let runtime = Self { root };
        if let Err(error) = runtime.write_files() {
            let _ = fs::remove_dir_all(&runtime.root);
            return Err(error);
        }
        Ok(runtime)
    }

    fn write_files(&self) -> io::Result<()> {
        for (relative, data) in BUNDLED_FILES {
            let path = self.root.join(relative);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(&path, data)?;
            set_file_mode(&path, EXECUTABLE_FILES.contains(relative))?;
        }
        Ok(())
    }

    fn script_path(&self) -> PathBuf {
        self.root.join("runtime/sshfling.py")
    }

    fn template_dir(&self) -> PathBuf {
        self.root.join("runtime/templates")
    }
}

impl Drop for RuntimeDirectory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn create_temp_directory() -> io::Result<PathBuf> {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    for attempt in 0..100 {
        let path = env::temp_dir().join(format!(
            "sshfling-rust-{}-{nonce}-{attempt}",
            std::process::id()
        ));
        match fs::create_dir(&path) {
            Ok(()) => return Ok(path),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(error),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "could not reserve a temporary SSHFling runtime directory",
    ))
}

#[cfg(unix)]
fn set_file_mode(path: &Path, executable: bool) -> io::Result<()> {
    use std::os::unix::fs::PermissionsExt;

    let mode = if executable { 0o755 } else { 0o644 };
    fs::set_permissions(path, fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
fn set_file_mode(_path: &Path, _executable: bool) -> io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn configured_python_is_first() {
        env::set_var("SSHFLING_PYTHON", "/opt/python-custom");
        let candidates = python_candidates();
        env::remove_var("SSHFLING_PYTHON");

        assert_eq!(
            candidates.first().map(|candidate| &candidate.program),
            Some(&OsString::from("/opt/python-custom"))
        );
    }

    #[test]
    fn runtime_contains_required_resources_and_cleans_up() {
        let runtime = RuntimeDirectory::create().unwrap();
        let root = runtime.root.clone();

        assert!(runtime.script_path().is_file());
        assert!(runtime.template_dir().join(".env.example").is_file());
        assert!(runtime.template_dir().join("secrets/.gitkeep").is_file());
        assert!(runtime
            .template_dir()
            .join("systemd/sshfling-prune.timer")
            .is_file());

        drop(runtime);
        assert!(!root.exists());
    }

    #[test]
    fn release_version_was_injected() {
        assert_ne!(VERSION, "0.0.0");
    }

    #[test]
    fn library_run_executes_cli() {
        run(["--version"]).unwrap();
    }
}
