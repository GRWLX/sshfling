let () =
  if Array.length Sys.argv <> 2 then failwith "missing smoke-project path";
  let smoke = Sys.argv.(1) in
  if Sshfling.run [ "--version" ] <> 0 then failwith "version failed";
  if
    Sshfling.run
      [ "init"; smoke; "--force"; "--session-seconds"; "60" ]
    <> 0
  then failwith "init failed";
  let wrapper = Filename.concat smoke "production/sshfling-session" in
  if not (Sys.file_exists wrapper) then failwith "session wrapper missing"
