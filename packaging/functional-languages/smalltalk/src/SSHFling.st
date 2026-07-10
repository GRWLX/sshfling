Object subclass: SSHFling [
    <category: 'SSHFling'>

    SSHFling class >> configured: name ifAbsent: fallback [
        | value |
        value := Smalltalk getenv: name.
        ^(value isNil or: [value isEmpty]) ifTrue: [fallback value] ifFalse: [value]
    ]

    SSHFling class >> runtimePath [
        ^self configured: 'SSHFLING_RUNTIME' ifAbsent: [
            (self configured: 'SSHFLING_PACKAGE_ROOT' ifAbsent: [Directory working name]),
            Directory pathSeparator, 'runtime', Directory pathSeparator, 'sshfling.py'
        ]
    ]

    SSHFling class >> templateDirectory [
        ^self configured: 'SSHFLING_TEMPLATE_DIR' ifAbsent: [
            (self configured: 'SSHFLING_PACKAGE_ROOT' ifAbsent: [Directory working name]),
            Directory pathSeparator, 'runtime', Directory pathSeparator, 'templates'
        ]
    ]

    SSHFling class >> shellQuote: value [
        (value includes: $') ifTrue: [^nil].
        (value includes: Character nl) ifTrue: [^nil].
        (value includes: Character cr) ifTrue: [^nil].
        ^'''', value, ''''
    ]

    SSHFling class >> system: command [
        <cCall: 'system' returning: #int args: #(#string)>
    ]

    SSHFling class >> run: arguments [
        | python pieces quoted status |
        (arguments allSatisfy: [:each | each isString]) ifFalse: [^2].
        python := self configured: 'SSHFLING_PYTHON' ifAbsent: ['python3'].
        pieces := {python. self runtimePath}, arguments.
        quoted := pieces collect: [:each | self shellQuote: each].
        (quoted includes: nil) ifTrue: [^2].
        status := self system: (quoted inject: '' into: [:command :piece |
            command isEmpty ifTrue: [piece] ifFalse: [command, ' ', piece]
        ]).
        status < 0 ifTrue: [^127].
        ^(status bitShift: -8) bitAnd: 255
    ]
]
