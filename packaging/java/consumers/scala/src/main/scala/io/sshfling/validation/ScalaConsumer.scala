package io.sshfling.validation

import io.sshfling.cli.SSHFling

object ScalaConsumer:
  def main(args: Array[String]): Unit =
    System.exit(SSHFling.run(args))
