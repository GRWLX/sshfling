use std::env;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

fn collect_files(root: &Path, current: &Path, files: &mut Vec<String>) -> io::Result<()> {
    let mut entries = fs::read_dir(current)?.collect::<Result<Vec<_>, _>>()?;
    entries.sort_by_key(|entry| entry.file_name());

    for entry in entries {
        let path = entry.path();
        if path.is_dir() {
            collect_files(root, &path, files)?;
        } else if path.is_file() {
            let relative = path
                .strip_prefix(root)
                .expect("runtime file must remain below its root")
                .to_string_lossy()
                .replace('\\', "/");
            files.push(relative);
        }
    }
    Ok(())
}

fn main() -> io::Result<()> {
    println!("cargo:rerun-if-changed=runtime");

    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let runtime_dir = manifest_dir.join("runtime");
    let mut files = Vec::new();
    collect_files(&manifest_dir, &runtime_dir, &mut files)?;

    let output = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("bundled_files.rs");
    let mut generated = File::create(output)?;
    writeln!(generated, "&[")?;
    for relative in files {
        writeln!(
            generated,
            "    ({relative:?}, include_bytes!(concat!(env!(\"CARGO_MANIFEST_DIR\"), \"/{relative}\")) as &'static [u8]),"
        )?;
    }
    writeln!(generated, "]")?;
    Ok(())
}
