program sshfling_fortran_consumer
    use sshfling, only: sshfling_argument, sshfling_run, sshfling_version
    implicit none

    type(sshfling_argument) :: arguments(1)
    character(len=64) :: expected
    integer :: status

    call get_command_argument(1, expected)
    if (trim(expected) /= sshfling_version) then
        error stop "Fortran library version mismatch"
    end if
    arguments(1)%value = "--version"
    status = sshfling_run(arguments)
    if (status /= 0) stop status
end program sshfling_fortran_consumer
