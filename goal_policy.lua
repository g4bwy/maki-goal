local M = {}

local Contracts = require("goal_contracts")
local Tasks = require("goal_tasks")
local Settings = require("goal_settings")

function M.is_unfinished(goal)
  return goal and goal.status ~= "complete"
end

function M.is_runnable(status)
  return status == "active"
end

function M.is_completable(status)
  return status == "active" or status == "paused"
end

function M.validate_completion(goal)
  if not goal then
    return false, "No goal is set."
  end
  if not M.is_completable(goal.status) then
    return false, "Goal is " .. goal.status .. "; cannot mark complete."
  end
  return true
end

function M.validate_pause(goal)
  if not goal then
    return false, "No goal is set."
  end
  if not M.is_runnable(goal.status) then
    return false, "Goal is " .. goal.status .. "; cannot pause."
  end
  return true
end

function M.validate_resume(goal)
  if not goal then
    return false, "No goal is set. Use /goal-set or /sisyphus-set to start."
  end
  if goal.status == "complete" then
    return false, "Goal is complete. Use /goal-set to start a new one."
  end
  if goal.status == "active" and goal.auto_continue then
    return false, "Goal is already running."
  end
  return true
end

function M.validate_abort(goal)
  if not goal then
    return false, "No goal is set."
  end
  if goal.status == "complete" then
    return false, "Goal is complete; cannot abort."
  end
  return true
end

function M.validate_tweak(goal)
  if not goal then
    return false, "No goal is set."
  end
  if goal.status == "complete" then
    return false, "Goal is complete; cannot tweak."
  end
  return true
end

function M.build_paused_goal(goal, reason, suggested_action)
  return {
    status = "paused",
    auto_continue = false,
    stop_reason = "agent",
    pause_reason = reason,
    pause_suggested_action = suggested_action,
    updated_at = goal.updated_at,
  }
end

function M.build_aborted_goal(goal, reason)
  return {
    status = "paused",
    auto_continue = false,
    stop_reason = "agent",
    pause_reason = "Aborted: " .. reason,
    updated_at = goal.updated_at,
  }
end

function M.build_completed_goal(goal, verification_summary)
  local result = {
    status = "complete",
    updated_at = goal.updated_at,
  }
  if verification_summary then
    result.verification_summary = verification_summary
  end
  return result
end

function M.build_resumed_goal(goal)
  return {
    status = "active",
    auto_continue = true,
    stop_reason = nil,
    pause_reason = nil,
    pause_suggested_action = nil,
    updated_at = goal.updated_at,
  }
end

function M.build_tweaked_goal(goal, new_objective)
  return {
    objective = new_objective,
    updated_at = goal.updated_at,
  }
end

function M.status_label(goal)
  if not goal then
    return "none"
  end
  return goal.status or "unknown"
end

-- Validates that goal_update does not attempt to change the objective
function M.validate_objective_immutable(updates)
  if not updates then
    return true
  end
  -- Immutable objective: only /goal-tweak flow may change the objective
  if updates.objective ~= nil then
    return false, "Cannot change objective through goal_update. Use /goal-tweak instead."
  end
  return true
end

-- Validates that tweak is only called during tweak_state
function M.validate_tweak_requires_flow(goal)
  if not goal then
    return false, "No goal is set."
  end
  if goal.tweak_state ~= "active" then
    return false, "Tweak is only allowed during an active /goal-tweak flow."
  end
  return true
end

-- Validates completion including contract requirements
function M.validate_completion_with_contracts(goal, verification_summary)
  local ok, err = M.validate_completion(goal)
  if not ok then
    return false, err
  end
  if Settings.contracts_enabled() then
    ok, err = Contracts.validate_completion(goal, verification_summary)
    if not ok then
      return false, err
    end
  end
  return true
end

-- Checks if there are pending tasks. Returns a soft guard warning text (does NOT block).
function M.validate_task_gate(goal)
  if not goal or not goal.tasks then
    return nil
  end
  if not Settings.tasks_enabled() then
    return nil
  end
  local pending = Tasks.count_pending(goal.tasks)
  if pending > 0 then
    return ("Warning: %d pending task(s) remain. Completion is allowed but consider finishing tasks first."):format(pending)
  end
  return nil
end

-- Returns true if goal.skip_auditor is true
function M.is_auditor_skipped(goal)
  if not goal then
    return false
  end
  return goal.skip_auditor == true
end

return M
