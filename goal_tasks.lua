local M = {}

M.VALID_STATUSES = { pending = true, complete = true, skipped = true }
M.MAX_EVIDENCE_LEN = 200

local function now_iso()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function deep_clone_table(t)
  if type(t) ~= "table" then
    return t
  end
  local cloned = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      cloned[k] = deep_clone_table(v)
    else
      cloned[k] = v
    end
  end
  return cloned
end

-- Collect all tasks into a flat list (preorder traversal)
local function flatten_tasks(tasks, acc)
  if not tasks then
    return acc
  end
  acc = acc or {}
  for _, task in ipairs(tasks) do
    acc[#acc + 1] = task
    if task.subtasks and #task.subtasks > 0 then
      flatten_tasks(task.subtasks, acc)
    end
  end
  return acc
end

-- BFS traversal yielding tasks level by level
local function bfs_tasks(tasks)
  if not tasks then
    return {}
  end
  local queue = {}
  local result = {}
  for _, t in ipairs(tasks) do
    queue[#queue + 1] = t
  end
  while #queue > 0 do
    local current = table.remove(queue, 1)
    result[#result + 1] = current
    if current.subtasks then
      for _, st in ipairs(current.subtasks) do
        queue[#queue + 1] = st
      end
    end
  end
  return result
end

-- Compute max nesting depth of task tree (leaf = 0, empty = -1)
local function max_depth(tasks)
  if not tasks or #tasks == 0 then
    return -1
  end
  local best = 0
  for _, task in ipairs(tasks) do
    local d = 1
    if task.subtasks and #task.subtasks > 0 then
      d = d + max_depth(task.subtasks)
    end
    if d > best then
      best = d
    end
  end
  return best
end

-- Check if all subtasks of a task are complete
local function all_subtasks_complete(task)
  if not task.subtasks or #task.subtasks == 0 then
    return true
  end
  for _, st in ipairs(task.subtasks) do
    if st.status ~= "complete" then
      return false
    end
  end
  return true
end

function M.new_task(id, title)
  return {
    id = id,
    title = title,
    status = "pending",
    evidence = nil,
    skip_reason = nil,
    completed_at = nil,
    verification_contract = nil,
    subtasks = {},
  }
end

function M.new_task_with_contract(id, title, contract)
  local task = M.new_task(id, title)
  task.verification_contract = contract
  return task
end

function M.validate_task_id(tasks, id)
  if not tasks or not id then
    return false, "tasks and id are required"
  end
  local all = flatten_tasks(tasks)
  for _, t in ipairs(all) do
    if t.id == id then
      return false, "Duplicate task id: " .. id
    end
  end
  return true
end

function M.validate_subtask_depth(tasks, max_depth)
  if not max_depth then
    return true
  end
  local depth = max_depth(tasks)
  if depth > max_depth then
    return false, "Subtask depth " .. depth .. " exceeds limit " .. max_depth
  end
  return true
end

function M.find_task(tasks, id)
  if not tasks or not id then
    return nil
  end
  for _, task in ipairs(tasks) do
    if task.id == id then
      return task
    end
    if task.subtasks and #task.subtasks > 0 then
      local found = M.find_task(task.subtasks, id)
      if found then
        return found
      end
    end
  end
  return nil
end

function M.update_task(tasks, id, updates)
  if not tasks or not id or not updates then
    return false, "tasks, id, and updates are required"
  end
  local task = M.find_task(tasks, id)
  if not task then
    return false, "Task not found: " .. id
  end
  for k, v in pairs(updates) do
    task[k] = v
  end
  return true
end

function M.complete_task(tasks, id, evidence)
  if not tasks or not id then
    return false, "tasks and id are required"
  end
  local task = M.find_task(tasks, id)
  if not task then
    return false, "Task not found: " .. id
  end
  if task.status == "complete" then
    return false, "Task is already complete"
  end
  if task.status == "skipped" then
    return false, "Task is skipped; cannot complete"
  end
  if not all_subtasks_complete(task) then
    return false, "Cannot complete: all subtasks must be complete first"
  end
  if M.requires_verification(task) then
    local ok, err = M.validate_completion(task, evidence)
    if not ok then
      return false, err
    end
  end
  task.status = "complete"
  task.completed_at = now_iso()
  if evidence then
    task.evidence = evidence:sub(1, M.MAX_EVIDENCE_LEN)
  end
  return true
end

function M.skip_task(tasks, id, reason)
  if not tasks or not id then
    return false, "tasks and id are required"
  end
  local task = M.find_task(tasks, id)
  if not task then
    return false, "Task not found: " .. id
  end
  if task.status == "complete" then
    return false, "Task is already complete; cannot skip"
  end
  task.status = "skipped"
  task.skip_reason = reason
  if task.subtasks then
    for _, st in ipairs(task.subtasks) do
      if st.status == "pending" then
        st.status = "skipped"
        st.skip_reason = "Parent skipped: " .. (reason or "no reason")
      end
    end
  end
  return true
end

function M.count_tasks(tasks)
  if not tasks then
    return 0
  end
  return #flatten_tasks(tasks)
end

function M.count_pending(tasks)
  if not tasks then
    return 0
  end
  local count = 0
  for _, t in ipairs(flatten_tasks(tasks)) do
    if t.status == "pending" then
      count = count + 1
    end
  end
  return count
end

function M.count_complete(tasks)
  if not tasks then
    return 0
  end
  local count = 0
  for _, t in ipairs(flatten_tasks(tasks)) do
    if t.status == "complete" then
      count = count + 1
    end
  end
  return count
end

function M.has_pending(tasks)
  if not tasks then
    return false
  end
  for _, t in ipairs(flatten_tasks(tasks)) do
    if t.status == "pending" then
      return true
    end
  end
  return false
end

function M.first_pending(tasks)
  if not tasks then
    return nil
  end
  for _, t in ipairs(bfs_tasks(tasks)) do
    if t.status == "pending" then
      return t
    end
  end
  return nil
end

function M.render_task_tree(tasks, indent)
  if not tasks then
    return ""
  end
  indent = indent or ""
  local lines = {}
  for _, task in ipairs(tasks) do
    local prefix
    if task.status == "complete" then
      prefix = "[x]"
    elseif task.status == "skipped" then
      prefix = "[-]"
    else
      prefix = "[ ]"
    end
    local contract_marker = task.verification_contract and " *" or ""
    lines[#lines + 1] = indent .. prefix .. " " .. task.title .. contract_marker

    if task.skip_reason and task.status == "skipped" then
      lines[#lines + 1] = indent .. "    (skipped: " .. task.skip_reason .. ")"
    end
    if task.evidence and task.status == "complete" then
      lines[#lines + 1] = indent .. "    (evidence: " .. task.evidence .. ")"
    end

    if task.subtasks and #task.subtasks > 0 then
      local sub = M.render_task_tree(task.subtasks, indent .. "  ")
      if sub ~= "" then
        lines[#lines + 1] = sub
      end
    end
  end
  return table.concat(lines, "\n")
end

function M.render_task_summary(tasks)
  if not tasks then
    return "No tasks"
  end
  local total = M.count_tasks(tasks)
  local pending = M.count_pending(tasks)
  local complete = M.count_complete(tasks)
  local skipped = total - pending - complete
  local parts = { total .. " task(s)" }
  if pending > 0 then
    parts[#parts + 1] = pending .. " pending"
  end
  if complete > 0 then
    parts[#parts + 1] = complete .. " done"
  end
  if skipped > 0 then
    parts[#parts + 1] = skipped .. " skipped"
  end
  return table.concat(parts, ", ")
end

function M.normalize_task_list(tasks)
  if not tasks then
    return {}
  end
  local normalized = {}
  for _, raw in ipairs(tasks) do
    local task = {}
    task.id = raw.id or nil
    task.title = raw.title or "Untitled"
    task.status = M.VALID_STATUSES[raw.status] and raw.status or "pending"
    task.evidence = raw.evidence and raw.evidence:sub(1, M.MAX_EVIDENCE_LEN) or nil
    task.skip_reason = raw.skip_reason or nil
    task.completed_at = raw.completed_at or nil
    task.verification_contract = raw.verification_contract or nil
    task.subtasks = M.normalize_task_list(raw.subtasks)
    normalized[#normalized + 1] = task
  end
  return normalized
end

function M.clone_task_list(tasks)
  return deep_clone_table(tasks)
end

function M.requires_verification(task)
  if not task then
    return false
  end
  return task.verification_contract ~= nil and task.verification_contract ~= ""
end

function M.validate_completion(task, evidence)
  if not task then
    return false, "No task provided"
  end
  if M.requires_verification(task) then
    if not evidence or evidence == "" then
      return false, "Verification contract requires evidence"
    end
    if #evidence > M.MAX_EVIDENCE_LEN then
      return false, "Evidence exceeds max length (" .. M.MAX_EVIDENCE_LEN .. " chars)"
    end
  end
  return true
end

return M
