    .text
    .globl sshfling_assembly_version
    .type sshfling_assembly_version, @function
sshfling_assembly_version:
    jmp sshfling_launcher_version@PLT
    .size sshfling_assembly_version, .-sshfling_assembly_version

    .globl sshfling_assembly_run
    .type sshfling_assembly_run, @function
sshfling_assembly_run:
    jmp sshfling_launcher_run@PLT
    .size sshfling_assembly_run, .-sshfling_assembly_run

    .section .note.GNU-stack,"",@progbits
