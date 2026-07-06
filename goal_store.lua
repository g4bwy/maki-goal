local M = {}

M.ACTIVE_DIR = "active"
M.ARCHIVED_DIR = "archived"
M.FOCUS_FILE = "focus.json"
M.AUDITOR_FILE = "auditor.json"

local function goals_base_dir()
  local state = maki.env.state_dir()
  if not state then
    return nil, "cannot resolve state dir"
  end
  return maki.fs.joinpath(state, "goals")
end

local function ensure_dirs()
  local base, err = goals_base_dir()
  if not base then
    return nil, err
  end
  local ok, mkdir_err = maki.fs.mkdir(maki.fs.joinpath(base, M.ACTIVE_DIR), { parents = true })
  if not ok then
    return nil, "mkdir active: " .. tostring(mkdir_err)
  end
  ok, mkdir_err = maki.fs.mkdir(maki.fs.joinpath(base, M.ARCHIVED_DIR), { parents = true })
  if not ok then
    return nil, "mkdir archived: " .. tostring(mkdir_err)
  end
  return base
end

function M.now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.new_goal_id()
  local t = tostring(os.time()):reverse():sub(1, 8)
  local r = tostring(math.random(100000, 999999))
  return t .. "-" .. r
end

function M.safe_id_part(value)
  if not value or value == "" then
    return "goal"
  end
  local safe = value:gsub("[^a-zA-Z0-9_-]", "_"):sub(1, 80)
  return safe or "goal"
end

function M.goal_file_path(goal)
  local base, err = goals_base_dir()
  if not base then
    return nil, err
  end
  if goal.status == "complete" or goal.status == "archived" then
    return maki.fs.joinpath(base, M.ARCHIVED_DIR, "goal_" .. goal.id .. ".json"), nil
  end
  return maki.fs.joinpath(base, M.ACTIVE_DIR, "active_goal_" .. goal.id .. ".json"), nil
end

function M.write_goal(goal)
  local base, err = ensure_dirs()
  if not base then
    return nil, err
  end
  local path, err = M.goal_file_path(goal)
  if not path then
    return nil, err
  end
  goal.updated_at = M.now_iso()
  local ok, write_err = maki.fs.write(path, maki.json.encode(goal))
  if not ok then
    return nil, "write error: " .. tostring(write_err)
  end
  return true
end

function M.read_goal(path)
  local content, err = maki.fs.read(path)
  if not content then
    return nil, err
  end
  local ok, goal = pcall(maki.json.decode, content)
  if not ok then
    return nil, "json parse error: " .. tostring(goal)
  end
  return goal
end

function M.focus_path()
  local base, err = goals_base_dir()
  if not base then
    return nil, err
  end
  return maki.fs.joinpath(base, M.FOCUS_FILE)
end

function M.write_focus(goal_id, reason)
  local base, err = ensure_dirs()
  if not base then
    return nil, err
  end
  local path, err = M.focus_path()
  if not path then
    return nil, err
  end
  local data = {
    version = 1,
    focused_goal_id = goal_id,
    reason = reason or "selected",
  }
  local ok, write_err = maki.fs.write(path, maki.json.encode(data))
  if not ok then
    return nil, "write error: " .. tostring(write_err)
  end
  return true
end

function M.read_focus()
  local path, err = M.focus_path()
  if not path then
    return nil, err
  end
  local content = maki.fs.read(path)
  if not content then
    return nil
  end
  local ok, data = pcall(maki.json.decode, content)
  if not ok then
    return nil
  end
  if not data or data.version ~= 1 then
    return nil
  end
  return data.focused_goal_id, data.reason
end

function M.read_active_pool()
  local base, err = goals_base_dir()
  if not base then
    return nil, err
  end
  local active_dir = maki.fs.joinpath(base, M.ACTIVE_DIR)
  local entries = maki.fs.dir(active_dir)
  if not entries then
    return {}
  end
  local pool = {}
  for _, entry in ipairs(entries) do
    if entry[2] == "file" and entry[1]:match("^active_goal_.*%.json$") then
      local path = maki.fs.joinpath(active_dir, entry[1])
      local goal, _ = M.read_goal(path)
      if goal and goal.status ~= "complete" then
        pool[goal.id] = goal
      end
    end
  end
  return pool
end

function M.open_goals(pool)
  local goals = {}
  for _, goal in pairs(pool) do
    if goal.status ~= "complete" then
      goals[#goals + 1] = goal
    end
  end
  table.sort(goals, function(a, b)
    return (a.created_at or "") < (b.created_at or "")
  end)
  return goals
end

function M.resolve_focus(pool)
  local focused_id, _ = M.read_focus()
  if focused_id and pool[focused_id] and pool[focused_id].status ~= "complete" then
    return focused_id
  end
  local open = M.open_goals(pool)
  if #open == 1 then
    return open[1].id
  end
  return nil
end

function M.focused_goal(pool, focused_id)
  if not focused_id then
    return nil
  end
  return pool[focused_id]
end

function M.archive_goal(goal)
  local base, err = ensure_dirs()
  if not base then
    return nil, err
  end
  local archived_dir = maki.fs.joinpath(base, M.ARCHIVED_DIR)
  local archived = maki.json.decode(maki.json.encode(goal))
  archived.status = goal.status == "complete" and "complete" or "paused"
  archived.archived_at = M.now_iso()
  local path = maki.fs.joinpath(archived_dir, "goal_" .. archived.id .. ".json")
  local ok, write_err = maki.fs.write(path, maki.json.encode(archived))
  if not ok then
    return nil, "archive write error: " .. tostring(write_err)
  end

  local active_dir = maki.fs.joinpath(base, M.ACTIVE_DIR)
  local active_path = maki.fs.joinpath(active_dir, "active_goal_" .. goal.id .. ".json")
  local meta = maki.fs.metadata(active_path)
  if meta then
    maki.fs.rm(active_path)
  end
  return archived
end

function M.auditor_config_path()
  local base, err = goals_base_dir()
  if not base then
    return nil, err
  end
  return maki.fs.joinpath(base, M.AUDITOR_FILE)
end

function M.load_auditor_config()
  local path, err = M.auditor_config_path()
  if not path then
    return nil, err
  end
  local content = maki.fs.read(path)
  if not content then
    return { enabled = false }
  end
  local ok, data = pcall(maki.json.decode, content)
  if not ok then
    return { enabled = false }
  end
  if not data then
    return { enabled = false }
  end
  if data.enabled == nil then
    data.enabled = false
  end
  return data
end

function M.save_auditor_config(config)
  local path, err = M.auditor_config_path()
  if not path then
    return nil, err
  end
  local ok, write_err = maki.fs.write(path, maki.json.encode(config))
  if not ok then
    return nil, "write error: " .. tostring(write_err)
  end
end

function M.create_goal(config)
  return {
    id = M.new_goal_id(),
    objective = config.objective,
    status = "active",
    auto_continue = config.auto_continue ~= false,
    sisyphus = config.sisyphus == true,
    created_at = M.now_iso(),
    updated_at = M.now_iso(),
    usage = { tokens_used = 0, active_seconds = 0 },
  }
end

return M
