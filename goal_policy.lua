local M = {}

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

function M.build_completed_goal(goal)
  return {
    status = "complete",
    updated_at = goal.updated_at,
  }
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

return M
