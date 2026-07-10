module sshfling
    use, intrinsic :: iso_c_binding, only: c_char, c_int, c_loc, c_null_char, c_ptr, c_size_t
    implicit none
    private

    character(len=*), parameter, public :: sshfling_version = "0.0.0"

    type, public :: sshfling_argument
        character(len=:), allocatable :: value
    end type sshfling_argument

    public :: sshfling_run

    interface
        function launcher_run_strided(count, values, stride) &
            bind(C, name="sshfling_launcher_run_strided") result(status)
            import :: c_int, c_ptr, c_size_t
            integer(c_size_t), value :: count
            type(c_ptr), value :: values
            integer(c_size_t), value :: stride
            integer(c_int) :: status
        end function launcher_run_strided
    end interface

contains

    integer function sshfling_run(arguments) result(status)
        type(sshfling_argument), intent(in) :: arguments(:)
        character(kind=c_char), allocatable, target :: storage(:, :)
        integer :: argument_count
        integer :: index
        integer :: offset
        integer :: width

        argument_count = size(arguments)
        width = 1
        do index = 1, argument_count
            if (.not. allocated(arguments(index)%value)) then
                status = 2
                return
            end if
            width = max(width, len(arguments(index)%value) + 1)
        end do

        allocate(storage(width, max(1, argument_count)))
        storage = c_null_char
        do index = 1, argument_count
            do offset = 1, len(arguments(index)%value)
                storage(offset, index) = arguments(index)%value(offset:offset)
            end do
        end do

        status = int(launcher_run_strided( &
            int(argument_count, c_size_t), &
            c_loc(storage(1, 1)), &
            int(width, c_size_t)))
    end function sshfling_run

end module sshfling
