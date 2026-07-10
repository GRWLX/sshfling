program sshfling_main
    use sshfling, only: sshfling_argument, sshfling_run
    implicit none

    type(sshfling_argument), allocatable :: arguments(:)
    integer :: argument_count
    integer :: argument_length
    integer :: index
    integer :: status

    argument_count = command_argument_count()
    allocate(arguments(argument_count))
    do index = 1, argument_count
        call get_command_argument(index, length=argument_length)
        allocate(character(len=argument_length) :: arguments(index)%value)
        call get_command_argument(index, value=arguments(index)%value)
    end do

    status = sshfling_run(arguments)
    if (status /= 0) stop status
end program sshfling_main
