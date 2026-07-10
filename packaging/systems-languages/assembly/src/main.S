    .text
    .globl main
    .type main, @function
main:
    jmp sshfling_launcher_main@PLT
    .size main, .-main

    .section .note.GNU-stack,"",@progbits
