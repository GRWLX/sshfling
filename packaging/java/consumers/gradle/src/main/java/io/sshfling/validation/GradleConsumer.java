package io.sshfling.validation;

import io.sshfling.cli.SSHFling;

public final class GradleConsumer {
    private GradleConsumer() {
    }

    public static void main(String[] args) {
        System.exit(SSHFling.run(args));
    }
}
