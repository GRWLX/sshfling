# Extract the semantic version from canonical `sshfling --version` output.
/^sshfling [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$/ {
    s/^sshfling //
    p
}
