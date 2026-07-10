if {![package vsatisfies [package provide Tcl] 8.6]} {
    return
}

package ifneeded sshfling 0.0.0 [list source [file join $dir sshfling.tcl]]
