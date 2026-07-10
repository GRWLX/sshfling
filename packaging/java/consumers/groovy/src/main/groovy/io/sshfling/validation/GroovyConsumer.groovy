package io.sshfling.validation

import io.sshfling.cli.SSHFling

final class GroovyConsumer {
    static void main(String[] args) {
        System.exit(SSHFling.run(args))
    }
}
