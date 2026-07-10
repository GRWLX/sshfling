cSSHFlingRoot = justfilepath(filename())
if cSSHFlingRoot = "" cSSHFlingRoot = currentdir() ok

func configuredor cName, cDefault
    cValue = sysget(cName)
    if cValue = "" return cDefault ok
    return cValue

func safearg cValue
    if substr(cValue, "'") > 0 return "" ok
    if substr(cValue, char(10)) > 0 return "" ok
    if substr(cValue, char(13)) > 0 return "" ok
    return "'" + cValue + "'"

func runtimepath
    cRoot = configuredor("SSHFLING_PACKAGE_ROOT", cSSHFlingRoot)
    return configuredor("SSHFLING_RUNTIME", cRoot + "/runtime/sshfling.py")

func templatedirectory
    cRoot = configuredor("SSHFLING_PACKAGE_ROOT", cSSHFlingRoot)
    return configuredor("SSHFLING_TEMPLATE_DIR", cRoot + "/runtime/templates")

func run aArgs
    if fexists(runtimepath()) = 0 return 127 ok
    aCommand = [configuredor("SSHFLING_PYTHON", "python3"), runtimepath()]
    for cArgument in aArgs add(aCommand, cArgument) next
    cCommand = ""
    for cArgument in aCommand
        cQuoted = safearg(cArgument)
        if cQuoted = "" return 2 ok
        if cCommand != "" cCommand += " " ok
        cCommand += cQuoted
    next
    # SSHFLING_TEMPLATE_DIR is normally found beside SSHFLING_RUNTIME.
    return system(cCommand)
