local sshfling = {}

sshfling.VERSION = "0.0.0"
sshfling.ROCK_VERSION = "0.0.0-1"

local function normalize_path(path)
  return (path:gsub("\\", "/"))
end

local function dirname(path)
  path = normalize_path(path):gsub("/+$", "")
  return path:match("^(.*)/[^/]+$") or "."
end

local function module_directory()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return dirname(source)
end

local function shell_quote(value)
  value = tostring(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function execute_status(command)
  local first, reason, code = os.execute(command)
  if type(first) == "number" then
    if first > 255 then
      return math.floor(first / 256)
    end
    return first
  end
  if first == true then
    return code or 0
  end
  if reason == "exit" then
    return code or 1
  end
  return 1
end

local function command_available(command)
  if command:find("/", 1, true) then
    local handle = io.open(command, "rb")
    if handle then
      handle:close()
      return true
    end
    return false
  end
  return execute_status("command -v " .. shell_quote(command) .. " >/dev/null 2>&1") == 0
end

function sshfling.version()
  return sshfling.VERSION
end

function sshfling.runtime_path()
  local configured = os.getenv("SSHFLING_RUNTIME")
  if configured and configured ~= "" then
    return configured
  end
  return module_directory() .. "/runtime/sshfling.py"
end

function sshfling.template_dir()
  local configured = os.getenv("SSHFLING_TEMPLATE_DIR")
  if configured and configured ~= "" then
    return configured
  end
  return module_directory() .. "/runtime/templates"
end

function sshfling.python_candidates()
  local candidates = {}
  local configured = os.getenv("SSHFLING_PYTHON")
  if configured and configured ~= "" then
    candidates[#candidates + 1] = configured
  end
  candidates[#candidates + 1] = "python3"
  candidates[#candidates + 1] = "python"
  return candidates
end

function sshfling.run(arguments)
  arguments = arguments or {}
  if type(arguments) ~= "table" then
    error("sshfling.run expects an array-like table of arguments", 2)
  end

  local runtime = sshfling.runtime_path()
  local templates = sshfling.template_dir()
  local runtime_handle = io.open(runtime, "rb")
  if not runtime_handle then
    io.stderr:write("sshfling: bundled runtime is missing: " .. runtime .. "\n")
    return 127
  end
  runtime_handle:close()
  for _, python in ipairs(sshfling.python_candidates()) do
    if command_available(python) then
      local command = "PYTHONUNBUFFERED=1 SSHFLING_TEMPLATE_DIR=" .. shell_quote(templates)
      command = command .. " " .. shell_quote(python) .. " " .. shell_quote(runtime)
      for index = 1, #arguments do
        command = command .. " " .. shell_quote(arguments[index])
      end
      return execute_status(command)
    end
  end

  io.stderr:write("sshfling: Python 3 is required; set SSHFLING_PYTHON to its executable\n")
  return 127
end

return sshfling
