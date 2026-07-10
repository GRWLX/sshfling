@[Link("sshfling_launcher")]
lib LibSSHFlingLauncher
  fun version = sshfling_launcher_version : UInt8*
  fun run = sshfling_launcher_run(count : LibC::SizeT, arguments : UInt8**) : Int32
end

module SSHFling
  VERSION = "0.0.0"

  def self.runtime_version : String
    String.new(LibSSHFlingLauncher.version)
  end

  def self.run(arguments : Array(String)) : Int32
    pointers = arguments.map(&.to_unsafe)
    base = pointers.empty? ? Pointer(Pointer(UInt8)).null : pointers.to_unsafe
    LibSSHFlingLauncher.run(pointers.size, base)
  end
end
