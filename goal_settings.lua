local M = {}

local SETTINGS_FILE = "settings.json"

local DEFAULTS = {
   disableTasks = false,
   disableContracts = false,
   subtaskDepth = 1,
   auditor = {
     model = nil,
     thinkingLevel = nil,
     disabled = false,
   },
}

local function goals_base_dir()
  local state = maki.env.state_dir()
  if not state then
    return nil, "cannot resolve state dir"
  end
  return maki.fs.joinpath(state, "goals")
end

local cached_settings = nil

function M.settings_path()
  local base, err = goals_base_dir()
  if not base then
    return nil, err
  end
  return maki.fs.joinpath(base, SETTINGS_FILE)
end

function M.load()
  local path, err = M.settings_path()
  if not path then
    return nil, err
  end
  local content = maki.fs.read(path)
  if not content then
    return DEFAULTS
  end
  local ok, data = pcall(maki.json.decode, content)
  if not ok then
    return DEFAULTS
  end
  if not data or type(data) ~= "table" then
    return DEFAULTS
  end
  local settings = {}
  for k, v in pairs(DEFAULTS) do
    if k == "auditor" then
      settings.auditor = {}
      for ak, av in pairs(v) do
        settings.auditor[ak] = data.auditor and data.auditor[ak] ~= nil and data.auditor[ak] or av
      end
    else
      settings[k] = data[k] ~= nil and data[k] or v
    end
  end
  cached_settings = settings
  return settings
end

function M.save(settings)
  local path, err = M.settings_path()
  if not path then
    return nil, err
  end
  local base, _ = goals_base_dir()
  if base then
    local ok, mkdir_err = maki.fs.mkdir(base, { parents = true })
    if not ok then
      return nil, "mkdir error: " .. tostring(mkdir_err)
    end
  end
  local ok, write_err = maki.fs.write(path, maki.json.encode(settings))
  if not ok then
    return nil, "write error: " .. tostring(write_err)
  end
  cached_settings = settings
  return true
end

function M.tasks_enabled()
  local settings = cached_settings or M.load()
  return not settings.disableTasks
end

function M.contracts_enabled()
  local settings = cached_settings or M.load()
  return not settings.disableContracts
end

function M.max_subtask_depth()
  local settings = cached_settings or M.load()
  return settings.subtaskDepth
end

function M.auditor_config()
   local settings = cached_settings or M.load()
   return {
     model = settings.auditor and settings.auditor.model,
     thinkingLevel = settings.auditor and settings.auditor.thinkingLevel,
     disabled = settings.auditor and settings.auditor.disabled == true,
   }
end

function M.is_auditor_disabled()
  local settings = cached_settings or M.load()
  return settings.auditor and settings.auditor.disabled == true
end

function M.update(key, value)
  local settings = cached_settings or M.load()
  if key:find("[.]") then
    local parts = {}
    for part in key:gmatch("([^%.]+)") do
      parts[#parts + 1] = part
    end
    local current = settings
    for i = 1, #parts - 1 do
      if not current[parts[i]] then
        return false, "key path not found: " .. key
      end
      current = current[parts[i]]
    end
    current[parts[#parts]] = value
  else
    settings[key] = value
  end
  cached_settings = settings
  return M.save(settings)
end

function M.update_auditor(field, value)
  local settings = cached_settings or M.load()
  if not settings.auditor then
    settings.auditor = {}
  end
  settings.auditor[field] = value
  cached_settings = settings
  return M.save(settings)
end

function M.reset()
  cached_settings = nil
  return M.save(DEFAULTS)
end

local ListPicker = require("maki.list_picker")

local function notify(msg)
  maki.ui.flash(msg)
end

local function format_value(key, value)
  if value == nil then
    return "(not set)"
  end
  if type(value) == "boolean" then
    return value and "true" or "false"
  end
  return tostring(value)
end

local SETTINGS_LIST = {
   { key = "disableTasks", label = "Disable Tasks", type = "bool" },
   { key = "disableContracts", label = "Disable Contracts", type = "bool" },
   { key = "subtaskDepth", label = "Subtask Depth", type = "int", min = 0, max = 5 },
   { key = "auditor.disabled", label = "Auditor Disabled", type = "bool" },
}

local function build_settings_items(settings)
   local items = {}
   for _, s in ipairs(SETTINGS_LIST) do
     local value
     if s.key:find("[.]") then
       local parts = {}
       for part in s.key:gmatch("([^%.]+)") do
         parts[#parts + 1] = part
       end
       value = settings[parts[1]] and settings[parts[1]][parts[2]]
     else
       value = settings[s.key]
     end
     items[#items + 1] = {
       label = s.label,
       detail = format_value(s.key, value),
     }
   end
   return items
 end

 local function get_current_value(settings, s)
   if s.key:find("[.]") then
     local parts = {}
     for part in s.key:gmatch("([^%.]+)") do
       parts[#parts + 1] = part
     end
     return settings[parts[1]] and settings[parts[1]][parts[2]]
   end
   return settings[s.key]
 end

 local function cmd_goal_settings()
   while true do
     local settings = M.load()
     local items = build_settings_items(settings)

     local event = ListPicker.open(items, {
       title = " Goal Settings ",
       submit_keys = { "enter" },
       footer = {
         { "Enter", "toggle/change" },
         { "Esc", "close" },
       },
     })

     if event.type ~= "choice" or event.index < 1 or event.index > #items then
       return
     end

     local s = SETTINGS_LIST[event.index]
     settings = M.load()
     local current_value = get_current_value(settings, s)

      if s.type == "bool" then
        local new_value = not current_value
        M.update(s.key, new_value)
        notify(s.label .. " = " .. tostring(new_value))

      elseif s.type == "int" then
        local next_val = current_value + 1
        if next_val > s.max then
          next_val = s.min
        end
        M.update(s.key, next_val)
        notify(s.label .. " = " .. next_val)
      end
    end
  end

maki.api.register_command({
  name = "/goal-settings",
  description = "View and toggle plugin settings",
  handler = cmd_goal_settings,
})

return M
