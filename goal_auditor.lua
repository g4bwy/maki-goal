local M = {}

local Store = require("goal_store")
local Settings = require("goal_settings")
local Contracts = require("goal_contracts")
local Tasks = require("goal_tasks")

-- Maximum length for completion and verification summaries in audit prompt
M.MAX_SUMMARY_LEN = 2000

-- Check if auditor should run for this goal
-- Returns true if auditor is enabled globally AND the goal doesn't have skip_auditor set
function M.should_audit(goal)
  if not goal then
    return false
  end
  if Settings.is_auditor_disabled() then
    return false
  end
  if goal.skip_auditor == true then
    return false
  end
  return true
end

-- Extract success criteria from the objective text
-- Looks for a "Success criteria:" section or bullet points
local function extract_success_criteria(objective)
  if not objective or type(objective) ~= "string" then
    return nil
  end

  -- Try to find a dedicated success criteria section
  local criteria = objective:match("[Ss]uccess criteria%s*:%s*(.-)\n\n")
  if criteria and criteria:match("%S") then
    return criteria
  end

  -- Try single-line format
  criteria = objective:match("[Ss]uccess criteria%s*:%s*(.*)")
  if criteria and criteria:match("%S") then
    return criteria
  end

  return nil
end

-- Build the full audit prompt text
function M.build_audit_prompt(goal, completion_summary, verification_summary)
  local lines = {}

  -- Header
  lines[#lines + 1] = "# Goal Completion Audit"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "You are an independent auditor. Your job is to verify that the agent's"
  lines[#lines + 1] = "claim of goal completion is legitimate and thoroughly verified."
  lines[#lines + 1] = ""

  -- Goal objective
  lines[#lines + 1] = "## Goal Objective"
  lines[#lines + 1] = ""
  lines[#lines + 1] = goal.objective or "(no objective)"
  lines[#lines + 1] = ""

  -- Success criteria (if extractable)
  local criteria = extract_success_criteria(goal.objective)
  if criteria then
    lines[#lines + 1] = "## Success Criteria"
    lines[#lines + 1] = ""
    lines[#lines + 1] = criteria
    lines[#lines + 1] = ""
  end

  -- Verification contract (if any)
  if Contracts.has_contract(goal) then
    lines[#lines + 1] = "## Verification Contract"
    lines[#lines + 1] = ""
    lines[#lines + 1] = goal.verification_contract
    lines[#lines + 1] = ""
  end

  -- Agent's completion summary
  if completion_summary and completion_summary ~= "" then
    lines[#lines + 1] = "## Agent's Completion Summary"
    lines[#lines + 1] = ""
    lines[#lines + 1] = completion_summary:sub(1, M.MAX_SUMMARY_LEN)
    lines[#lines + 1] = ""
  end

  -- Agent's verification evidence
  if verification_summary and verification_summary ~= "" then
    lines[#lines + 1] = "## Agent's Verification Evidence"
    lines[#lines + 1] = ""
    lines[#lines + 1] = verification_summary:sub(1, M.MAX_SUMMARY_LEN)
    lines[#lines + 1] = ""
  end

  -- Task summary (if tasks exist)
  if goal.tasks and #goal.tasks > 0 then
    lines[#lines + 1] = "## Task Summary"
    lines[#lines + 1] = ""
    lines[#lines + 1] = Tasks.render_task_summary(goal.tasks)
    lines[#lines + 1] = ""
    local tree = Tasks.render_task_tree(goal.tasks)
    if tree ~= "" then
      lines[#lines + 1] = tree
      lines[#lines + 1] = ""
    end
  end

  -- Audit instructions
  lines[#lines + 1] = "## Audit Instructions"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Perform a thorough audit of this claimed completion:"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "1. Inspect the workspace (read-only). Verify that actual artifacts exist."
  lines[#lines + 1] = "2. Check that ALL success criteria from the objective are met."
  lines[#lines + 1] = "3. If a verification contract exists, verify the agent's evidence satisfies it."
  lines[#lines + 1] = "4. If tasks exist, verify all tasks are completed with valid evidence."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Reject the completion if:"
  lines[#lines + 1] = "- The work is scaffold-only, stub, or alpha quality."
  lines[#lines + 1] = "- Success criteria are not demonstrably met."
  lines[#lines + 1] = "- Verification contract evidence is missing or weak."
  lines[#lines + 1] = "- The completion summary is vague or hand-wavy."
  lines[#lines + 1] = "- Tests are not run, not passing, or not meaningful."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "End your response with exactly one of these markers:"
  lines[#lines + 1] = "- <approved/>   if the completion is verified and legitimate"
  lines[#lines + 1] = "- <disapproved/> if the completion is insufficient or unverifiable"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Include a brief report explaining your decision before the marker."

  return table.concat(lines, "\n")
end

-- Run the audit. In the Lua plugin context, this builds the audit prompt
-- and returns a structured result. The actual LLM audit happens when the
-- prompt is sent to the auditor model (configured in settings).
function M.run_audit(goal, completion_summary, verification_summary)
  if not M.should_audit(goal) then
    return {
      audited = false,
      approved = true,
      report = "Audit skipped (disabled or goal.skip_auditor set).",
    }
  end

  local prompt = M.build_audit_prompt(goal, completion_summary, verification_summary)

  local auditor_cfg = Settings.auditor_config()
   local model = auditor_cfg.model
   local thinking_level = auditor_cfg.thinkingLevel

   return {
     audited = true,
     prompt = prompt,
     model = model,
     thinking_level = thinking_level,
    -- These fields are populated after the LLM responds:
    -- approved = true/false
    -- report = auditor's explanation text
  }
end

-- Parse the auditor's response looking for <approved/> or <disapproved/> markers
function M.parse_audit_result(text)
  if not text or type(text) ~= "string" then
    return nil, "No audit response text"
  end

  -- Check for approved marker
  if text:find("<approved%s*/>") then
    -- Extract report text before the marker
    local report = text:match("(.-)<approved%s*/>")
    return true, (report or ""):match("^%s*(.-)%s*$")
  end

  -- Check for disapproved marker
  if text:find("<disapproved%s*/>") then
    local report = text:match("(.-)<disapproved%s*/>")
    return false, (report or ""):match("^%s*(.-)%s*$")
  end

  return nil, "Audit response missing <approved/> or <disapproved/> marker"
end

-- Format the audit result for display
function M.audit_result_text(approved, auditor_report)
  if approved == nil then
    return "Audit inconclusive: " .. (auditor_report or "no report")
  end

  local lines = {}
  if approved then
    lines[#lines + 1] = "Audit APPROVED."
  else
    lines[#lines + 1] = "Audit DISAPPROVED."
  end

  if auditor_report and auditor_report ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Auditor report:"
    lines[#lines + 1] = auditor_report
  end

  return table.concat(lines, "\n")
end

-- Build a deferred archival event. Instead of archiving immediately in the
-- tool handler, this sets a flag on the goal. The TurnEnd autocmd checks
-- this flag and performs the actual archival.
function M.build_deferred_archival_event(goal, completion_summary, verification_summary, auditor_report)
  if not goal then
    return nil
  end

  goal._deferred_archive = true
  goal._deferred_archive_data = {
    completion_summary = completion_summary,
    verification_summary = verification_summary,
    auditor_report = auditor_report,
    auditor_approved = goal._auditor_approved,
  }

  return goal
end

-- Check if a goal has a pending deferred archival and process it.
-- Returns the archival result or nil if no deferred archival is pending.
function M.process_deferred_archive(goal, pool)
  if not goal or not goal._deferred_archive then
    return nil
  end

  local data = goal._deferred_archive_data or {}

  -- Perform the archival
  local archived, err = Store.archive_goal(goal)
  if not archived then
    return nil, "Deferred archival failed: " .. tostring(err)
  end

  -- Clean up from pool
  if pool then
    pool[goal.id] = nil
  end

  -- Clear the deferred flags
  goal._deferred_archive = nil
  goal._deferred_archive_data = nil

  return archived, data
end

return M
