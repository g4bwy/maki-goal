local M = {}

M.MAX_SUMMARY_LEN = 500

-- Known section headers that bound a Verification contract block
local SECTION_HEADERS = {
  "objective", "success criteria", "verification contract",
  "context", "constraints", "notes", "background", "acceptance criteria",
}

-- Build a case-insensitive pattern that matches any known section header at start of line
local function section_header_pattern()
  local parts = {}
  for _, h in ipairs(SECTION_HEADERS) do
    parts[#parts + 1] = h
  end
  return "^%s*(" .. table.concat(parts, "|") .. ")%s*:"
end

-- Strip leading/trailing whitespace from a string
local function trim(s)
  if not s then
    return nil
  end
  return s:match("^%s*(.-)%s*$")
end

-- Split text into lines, preserving line endings for reconstruction
local function split_lines(text)
  local lines = {}
  for line in text:gmatch("([^\r\n]*)\r?\n?") do
    lines[#lines + 1] = line
  end
  return lines
end

function M.extract_contract(objective)
  if not objective or type(objective) ~= "string" then
    return nil, objective
  end

  local header_pat = section_header_pattern()
  local lines = split_lines(objective)

  local contract_start = nil
  for i, line in ipairs(lines) do
    if line:lower():match("^%s*verification contract%s*:") then
      contract_start = i
      break
    end
  end

  if not contract_start then
    return nil, objective
  end

  -- Extract contract text: from the header line to the next section header or end
  local contract_lines = {}
  local cleaned_lines = {}

  -- Add lines before the contract section to cleaned
  for i = 1, contract_start - 1 do
    cleaned_lines[#cleaned_lines + 1] = lines[i]
  end

  -- First line of contract: everything after "Verification contract:"
  local first_line = lines[contract_start]
  local after_colon = first_line:match("^%s*verification contract%s*:%s*(.*)")
  if after_colon and after_colon ~= "" then
    contract_lines[#contract_lines + 1] = after_colon
  end

  -- Collect subsequent lines until next section header or end
  local in_contract = true
  for i = contract_start + 1, #lines do
    local line = lines[i]
    if in_contract and line:lower():match(header_pat) and not line:lower():match("^%s*verification contract%s*:") then
      in_contract = false
    end
    if in_contract then
      contract_lines[#contract_lines + 1] = line
    else
      cleaned_lines[#cleaned_lines + 1] = line
    end
  end

  local contract = trim(table.concat(contract_lines, "\n"))
  if not contract or contract == "" then
    -- Contract section existed but was empty; treat as no contract
    return nil, objective
  end

  local cleaned = trim(table.concat(cleaned_lines, "\n"))
  if not cleaned or cleaned == "" then
    cleaned = nil
  end

  return contract, cleaned
end

function M.has_contract(goal)
  if not goal then
    return false
  end
  return goal.verification_contract ~= nil and goal.verification_contract ~= ""
end

function M.validate_completion(goal, verification_summary)
  if not goal then
    return false, "No goal provided"
  end
  if not M.has_contract(goal) then
    return true
  end
  if not verification_summary or verification_summary == "" then
    return false, "Verification contract requires a verification summary"
  end
  if #verification_summary > M.MAX_SUMMARY_LEN then
    return false, "Verification summary exceeds max length (" .. M.MAX_SUMMARY_LEN .. " chars)"
  end
  return true
end

function M.contract_prompt_block(goal)
  if not M.has_contract(goal) then
    return ""
  end
  local contract = goal.verification_contract
  local lines = {
    "## Verification Contract",
    "",
    "Before marking this goal complete, you must satisfy the following contract:",
    "",
    contract,
    "",
    "Provide a verification_summary when completing the goal that demonstrates",
    "the contract requirements have been met.",
  }
  return table.concat(lines, "\n")
end

function M.build_auditor_evidence_block(goal, verification_summary)
  if not M.has_contract(goal) then
    return ""
  end
  local lines = {
    "## Contract Verification",
    "",
    "**Contract:**",
    "",
    goal.verification_contract,
    "",
  }
  if verification_summary and verification_summary ~= "" then
    lines[#lines + 1] = "**Verification Summary:**"
    lines[#lines + 1] = ""
    lines[#lines + 1] = verification_summary
    lines[#lines + 1] = ""
  else
    lines[#lines + 1] = "**Verification Summary:** (not provided)"
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

return M
