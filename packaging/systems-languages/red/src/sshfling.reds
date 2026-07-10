Red/System [
    Title: "SSHFling launcher API"
    Name: 'sshfling
    Type: 'module
    Version: 0.0.0
]

#switch OS [
    Windows   [#define SSHFLING-LIB "sshfling_launcher.dll"]
    macOS     [#define SSHFLING-LIB "libsshfling_launcher.dylib"]
    #default  [#define SSHFLING-LIB "libsshfling_launcher.so"]
]

#import [
    SSHFLING-LIB cdecl [
        launcher-version: "sshfling_launcher_version" [return: [c-string!]]
        launcher-run: "sshfling_launcher_run" [
            count [integer!]
            arguments [str-array!]
            return: [integer!]
        ]
        launcher-main: "sshfling_launcher_main" [
            count [integer!]
            arguments [str-array!]
            return: [integer!]
        ]
    ]
]

sshfling-version: func [return: [c-string!]][launcher-version]
sshfling-run: func [count [integer!] arguments [str-array!] return: [integer!]][
    launcher-run count arguments
]
sshfling-main: func [count [integer!] arguments [str-array!] return: [integer!]][
    launcher-main count arguments
]
