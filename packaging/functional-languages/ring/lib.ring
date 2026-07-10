func pathdirectory cPath
    nLast = 0
    for nIndex = 1 to len(cPath)
        cCharacter = substr(cPath, nIndex, 1)
        if cCharacter = "/" nLast = nIndex ok
        if cCharacter = "\\" nLast = nIndex ok
    next
    if nLast = 0 return "" ok
    return substr(cPath, 1, nLast)

func packageroot
    cRoot = pathdirectory(filename())
    if cRoot = "" cRoot = currentdir() ok
    return cRoot

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
    cRoot = configuredor("SSHFLING_PACKAGE_ROOT", packageroot())
    return configuredor("SSHFLING_RUNTIME", cRoot + "/runtime/sshfling.py")

func templatedirectory
    cRoot = configuredor("SSHFLING_PACKAGE_ROOT", packageroot())
    return configuredor("SSHFLING_TEMPLATE_DIR", cRoot + "/runtime/templates")

func normalizedstatus nStatus
    if nStatus < 0 return 127 ok
    if nStatus > 255 return floor(nStatus / 256) ok
    return nStatus

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
    cTemplate = safearg(templatedirectory())
    if cTemplate = "" return 2 ok
    return normalizedstatus(system("SSHFLING_TEMPLATE_DIR=" + cTemplate + " PYTHONUNBUFFERED='1' " + cCommand))
