namespace eval ::sshfling {
    variable package_version "0.0.0"
    variable module_dir [file dirname [file normalize [info script]]]
}

proc ::sshfling::version {} {
    variable package_version
    return $package_version
}

proc ::sshfling::runtime_path {} {
    variable module_dir
    return [file join $module_dir runtime sshfling.py]
}

proc ::sshfling::template_dir {} {
    variable module_dir
    return [file join $module_dir runtime templates]
}

proc ::sshfling::python_candidates {} {
    set candidates {}
    if {[info exists ::env(SSHFLING_PYTHON)] && [string trim $::env(SSHFLING_PYTHON)] ne ""} {
        lappend candidates [list $::env(SSHFLING_PYTHON)]
    }
    if {$::tcl_platform(platform) eq "windows"} {
        lappend candidates [list py -3] [list python] [list python3]
    } else {
        lappend candidates [list python3] [list python]
    }
    return $candidates
}

proc ::sshfling::_command_available {candidate} {
    set program [lindex $candidate 0]
    return [expr {[auto_execok $program] ne ""}]
}

proc ::sshfling::_normalize_template_modes {} {
    foreach relative {
        native/sshfling-linux-account
        native/sshfling-unix-identity
        production/sshfling-login-shell
        production/sshfling-session
        scripts/create-network.sh
        scripts/generate-ssh-key.sh
        scripts/install-local.sh
        scripts/uninstall-local.sh
        ssh-client/entrypoint.sh
        ssh-server/entrypoint.sh
        ssh-server/limited-session.sh
    } {
        set path [file join [template_dir] {*}[split $relative /]]
        if {[file isfile $path]} {
            catch {file attributes $path -permissions 0755}
        }
    }
}

proc ::sshfling::_restore_environment {name existed value} {
    if {$existed} {
        set ::env($name) $value
    } else {
        unset -nocomplain ::env($name)
    }
}

proc ::sshfling::run {args} {
    _normalize_template_modes

    set had_template [info exists ::env(SSHFLING_TEMPLATE_DIR)]
    set old_template [expr {$had_template ? $::env(SSHFLING_TEMPLATE_DIR) : ""}]
    set had_unbuffered [info exists ::env(PYTHONUNBUFFERED)]
    set old_unbuffered [expr {$had_unbuffered ? $::env(PYTHONUNBUFFERED) : ""}]
    if {!$had_template || [string trim $old_template] eq ""} {
        set ::env(SSHFLING_TEMPLATE_DIR) [template_dir]
    }
    if {!$had_unbuffered} {
        set ::env(PYTHONUNBUFFERED) 1
    }

    try {
        foreach candidate [python_candidates] {
            if {![_command_available $candidate]} {
                continue
            }

            set command [concat $candidate [list [runtime_path]] $args]
            set failed [catch {
                exec {*}$command <@stdin >@stdout 2>@stderr
            } message options]
            if {!$failed} {
                return 0
            }

            set error_code [dict get $options -errorcode]
            if {[lindex $error_code 0] eq "CHILDSTATUS"} {
                return [lindex $error_code 2]
            }
            if {[lindex $error_code 0] eq "CHILDKILLED"} {
                puts stderr "sshfling: Python runtime was terminated: $message"
                return 1
            }
            puts stderr "sshfling: could not execute [lindex $candidate 0]: $message"
            return 127
        }

        puts stderr "sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable"
        return 127
    } finally {
        _restore_environment SSHFLING_TEMPLATE_DIR $had_template $old_template
        _restore_environment PYTHONUNBUFFERED $had_unbuffered $old_unbuffered
    }
}

package provide sshfling 0.0.0
