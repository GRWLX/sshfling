.sshfling.configuredOr:{[name;fallback]
  value:getenv name;
  $[0=count value;fallback;value]};

.sshfling.sourceFile:string .z.f;
.sshfling.sourceDirectory:"/" sv -1_"/" vs .sshfling.sourceFile;
.sshfling.defaultRoot:"/" sv -1_"/" vs .sshfling.sourceDirectory;
.sshfling.defaultRoot:$[0=count .sshfling.defaultRoot;".";.sshfling.defaultRoot];

.sshfling.runtimePath:{
  root:.sshfling.configuredOr["SSHFLING_PACKAGE_ROOT";.sshfling.defaultRoot];
  .sshfling.configuredOr["SSHFLING_RUNTIME";root,"/runtime/sshfling.py"]};

.sshfling.templateDirectory:{
  root:.sshfling.configuredOr["SSHFLING_PACKAGE_ROOT";.sshfling.defaultRoot];
  .sshfling.configuredOr["SSHFLING_TEMPLATE_DIR";root,"/runtime/templates"]};

.sshfling.quote:{[value]
  $[any value in "'\r\n";::;enlist["'"],value,enlist "'"]};

.sshfling.run:{[args]
  pieces:(.sshfling.configuredOr["SSHFLING_PYTHON";"python3"];.sshfling.runtimePath[]),args;
  quoted:.sshfling.quote each pieces;
  if[any 0=count each quoted;:2];
  marker:"__SSHFLING_STATUS__";
  output:system (raze quoted,\:" ")," ; rc=$?; printf '\n",marker,"%d\n' \"$rc\"; exit 0";
  status:"J"$[marker~count[marker]#last output;count[marker]_last output;"1"];
  -1 raze -1_output;
  status};
