local M = {}

local Tasks = require("goal_tasks")
local Contracts = require("goal_contracts")
local Settings = require("goal_settings")

local STATUS_MARKERS = {
  active = { "[active]", "todo_in_progress" },
  paused = { "[paused]", "todo_pending" },
  complete = { "[done]", "todo_completed" },
}

local function truncate(s, max_len)
  max_len = max_len or 60
  if #s <= max_len then
    return s
  end
  return s:sub(1, max_len - 3) .. "..."
end

function M.status_hint(goal)
  if not goal then
    maki.ui.set_status_hint(nil)
    return
  end
  local marker = STATUS_MARKERS[goal.status] or STATUS_MARKERS.active
  local obj = truncate(goal.objective or "", 50)
  local hint_parts = { { marker[1] .. " " .. obj, marker[2] } }
  if goal.tasks and Tasks.count_tasks(goal.tasks) > 0 then
    local completed = Tasks.count_complete(goal.tasks)
    local total = Tasks.count_tasks(goal.tasks)
    hint_parts[#hint_parts + 1] = { " (" .. completed .. "/" .. total .. " tasks)" }
  end
  maki.ui.set_status_hint(hint_parts)
end

function M.clear_status_hint()
  maki.ui.set_status_hint(nil)
end

function M.build_goal_list_text(pool, focused_id)
  local open = {}
  for _, goal in pairs(pool) do
    if goal.status ~= "complete" then
      open[#open + 1] = goal
    end
  end
  table.sort(open, function(a, b)
    return (a.created_at or "") < (b.created_at or "")
  end)

  if #open == 0 then
    return "No open goals. Use /goal-set or /sisyphus-set to start."
  end

  local lines = { string.format("Open goals: %d", #open), "" }
  for _, goal in ipairs(open) do
    local focused = goal.id == focused_id and "*" or " "
    local mode = goal.sisyphus and "sisyphus" or "goal"
    local obj = truncate(goal.objective or "", 55)
    lines[#lines + 1] = string.format("%s %s -- %s · %s", focused, goal.id, goal.status, mode)
    lines[#lines + 1] = "  " .. obj
  end
  return table.concat(lines, "\n")
end

function M.build_goal_detail(goal)
  if not goal then
    return "No goal is set. Use /goal-set <objective> or /sisyphus-set <objective> to start immediately."
  end
  local lines = {
    "Goal: " .. (goal.objective or ""),
    "Status: " .. (goal.status or "unknown"),
    "Auto-continue: " .. (goal.auto_continue and "on" or "off"),
  }
  if goal.sisyphus then
    lines[#lines + 1] = "Mode: Sisyphus (ordered sequential execution)"
  end
  if goal.pause_reason then
    lines[#lines + 1] = "Pause reason: " .. goal.pause_reason
  end
  if goal.pause_suggested_action then
    lines[#lines + 1] = "Suggested action: " .. goal.pause_suggested_action
  end
  if goal.stop_reason then
    lines[#lines + 1] = "Stop reason: " .. goal.stop_reason
  end
  if Contracts.has_contract(goal) then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Verification contract:"
    lines[#lines + 1] = goal.verification_contract
  end
  if goal.tasks and Tasks.count_tasks(goal.tasks) > 0 then
    lines[#lines + 1] = ""
    local completed = Tasks.count_complete(goal.tasks)
    local total = Tasks.count_tasks(goal.tasks)
    lines[#lines + 1] = "Tasks: " .. completed .. "/" .. total .. " complete"
    lines[#lines + 1] = Tasks.render_task_tree(goal.tasks)
  end
  return table.concat(lines, "\n")
end

function M.build_completion_report(goal, summary, auditor_report)
  local lines = {}
  if auditor_report then
    lines[#lines + 1] = "Goal audit approved."
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Auditor approval:"
    lines[#lines + 1] = auditor_report
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = "Goal complete."
  if summary then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Completion summary:"
    lines[#lines + 1] = summary
  end
  if Contracts.has_contract(goal) and goal.verification_summary then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Verification summary:"
    lines[#lines + 1] = goal.verification_summary
  end
  if goal.tasks and Tasks.count_tasks(goal.tasks) > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = M.build_task_list_text(goal)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = M.build_goal_detail(goal)
  return table.concat(lines, "\n")
end

function M.build_goal_created_report(goal)
  local lines = {
    "Goal confirmed and created.",
    "",
    "Finalized goal:",
    "",
    goal.objective or "",
  }
  if Contracts.has_contract(goal) then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Verification contract:"
    lines[#lines + 1] = goal.verification_contract
  end
  if goal.tasks and Tasks.count_tasks(goal.tasks) > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = M.build_task_list_text(goal)
  end
  return table.concat(lines, "\n")
end

function M.build_task_list_text(goal)
  if not goal or not goal.tasks then
    return ""
  end
  local total = Tasks.count_tasks(goal.tasks)
  if total == 0 then
    return ""
  end
  local completed = Tasks.count_complete(goal.tasks)
  local lines = {
    "Tasks: " .. completed .. "/" .. total .. " complete",
    Tasks.render_task_tree(goal.tasks),
  }
  return table.concat(lines, "\n")
end

function M.build_proposal_text(goal, tasks)
  local lines = {
    "Proposed goal:",
    "",
    goal.objective or "",
  }
  if Contracts.has_contract(goal) then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Verification contract:"
    lines[#lines + 1] = goal.verification_contract
  end
  if tasks and Tasks.count_tasks(tasks) > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Tasks:"
    lines[#lines + 1] = Tasks.render_task_tree(tasks)
  end
  return table.concat(lines, "\n")
end

return M
