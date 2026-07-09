package io.sshfling.validation;

import io.sshfling.cli.SSHFling;

public final class MavenConsumer {
    private MavenConsumer() {
    }

    public static void main(String[] args) {
        System.exit(SSHFling.run(args));
    }
}
