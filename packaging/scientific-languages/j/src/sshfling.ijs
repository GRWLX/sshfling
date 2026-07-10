coclass 'sshfling'

configuredor=: 4 : 0
  value=. getenv x
  if. (0 -: value) +. 0=#value do. y return. end.
  value
)

runtimepath=: 3 : 0
  root=. 'SSHFLING_PACKAGE_ROOT' configuredor jpath '~addons/sshfling'
  'SSHFLING_RUNTIME' configuredor root,'/runtime/sshfling.py'
)

templatedirectory=: 3 : 0
  root=. 'SSHFLING_PACKAGE_ROOT' configuredor jpath '~addons/sshfling'
  'SSHFLING_TEMPLATE_DIR' configuredor root,'/runtime/templates'
)

shellquote=: 3 : 0
  '''',(y rplc ('''';'''"''"''')),''''
)

run=: 3 : 0
  if. -. fexist runtimepath'' do. 127 return. end.
  python=. 'SSHFLING_PYTHON' configuredor 'python3'
  pieces=. (<python),(<runtimepath''),y
  quoted=. shellquote each pieces
  if. +./ 0=# each quoted do. 2 return. end.
  command=. ; quoted ,each <' '
  marker=. '__SSHFLING_STATUS__'
  output=. 2!:0 command,'; rc=$?; printf "',marker,'%d" "$rc"; exit 0'
  markerindex=. 1 i.~ marker E. output
  if. markerindex=#output do. 1 return. end.
  payload=. markerindex {. output
  if. #payload do. echo payload }.~ - LF={:payload end.
  ". (markerindex+#marker) }. output
)

cocurrent 'base'
