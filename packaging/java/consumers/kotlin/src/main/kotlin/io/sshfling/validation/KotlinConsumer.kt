package io.sshfling.validation

import io.sshfling.cli.SSHFling
import kotlin.system.exitProcess

object KotlinConsumer {
    @JvmStatic
    fun main(args: Array<String>) {
        exitProcess(SSHFling.run(args))
    }
}
