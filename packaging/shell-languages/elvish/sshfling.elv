use path

var version-value = '0.0.0'

fn version {
  put $version-value
}

fn package-root {
  if (and (has-env SSHFLING_PACKAGE_ROOT) (not-eq $E:SSHFLING_PACKAGE_ROOT '')) {
    put $E:SSHFLING_PACKAGE_ROOT
  } else {
    fail 'sshfling: set SSHFLING_PACKAGE_ROOT before using the Elvish module'
  }
}

fn runtime-path {
  if (and (has-env SSHFLING_RUNTIME) (not-eq $E:SSHFLING_RUNTIME '')) {
    put $E:SSHFLING_RUNTIME
  } else {
    path:join (package-root) libexec sshfling sshfling.py
  }
}

fn template-dir {
  if (and (has-env SSHFLING_TEMPLATE_DIR) (not-eq $E:SSHFLING_TEMPLATE_DIR '')) {
    put $E:SSHFLING_TEMPLATE_DIR
  } else {
    path:join (package-root) share sshfling templates
  }
}

fn run {|@arguments|
  var python = ''
  if (and (has-env SSHFLING_PYTHON) (not-eq $E:SSHFLING_PYTHON '')) {
    set python = $E:SSHFLING_PYTHON
  } elif (has-external python3) {
    set python = (search-external python3)
  } elif (has-external python) {
    set python = (search-external python)
  } else {
    fail 'sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable'
  }

  var template-env = 'SSHFLING_TEMPLATE_DIR='(template-dir)
  e:env PYTHONUNBUFFERED=1 $template-env $python (runtime-path) $@arguments
}
