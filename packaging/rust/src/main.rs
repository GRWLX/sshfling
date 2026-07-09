fn main() {
    if let Err(error) = sshfling::run(std::env::args_os().skip(1)) {
        if !error.is_cli_exit() {
            eprintln!("sshfling: {error}");
        }
        std::process::exit(error.exit_code());
    }
}
