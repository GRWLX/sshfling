package io.sshfling.validation

import io.sshfling.cli.SSHFling

final class GroovyGradleConsumer {
    static void main(String[] args) {
        System.exit(SSHFling.run(args))
    }
}
