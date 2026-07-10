use "lib:sshfling_launcher"
use @sshfling_launcher_version[Pointer[U8]]()
use @sshfling_launcher_run[I32](count: USize, arguments: Pointer[Pointer[U8] tag] tag)

primitive SSHFling
  fun version(): String val => "0.0.0"

  fun runtime_version(): String val =>
    recover val String.from_cstring(@sshfling_launcher_version()) end

  fun run(arguments: ReadSeq[String val]): I32 =>
    let pointers = Array[Pointer[U8] tag](arguments.size())
    for argument in arguments.values() do
      pointers.push(argument.cstring())
    end
    @sshfling_launcher_run(arguments.size(), pointers.cpointer())
