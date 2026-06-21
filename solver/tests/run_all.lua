-- run_all.lua — master test runner
-- Usage (from repo root): /opt/homebrew/bin/lua solver/tests/run_all.lua
--
-- During TDD step 1: all tests FAIL because solver/rules.lua is absent.
-- This is the expected "red" state.
--
-- During TDD step 2: tests turn GREEN as rules.lua is implemented.

-- Set up package path so that 'solver.tests.harness' and 'solver.rules' resolve
-- from the repo root (where this script is run from).
local repo_root = arg and arg[0] and arg[0]:match("^(.*)/solver/tests/run_all%.lua$")
if repo_root then
   package.path = repo_root .. "/?.lua;" .. package.path
   package.path = repo_root .. "/?/init.lua;" .. package.path
else
   -- Fallback: assume cwd is repo root
   package.path = "./?.lua;./?/init.lua;" .. package.path
end

print("=== Shenzhen Solitaire Solver — TDD Test Suite ===")
print("Interpreter: " .. _VERSION)
print("Package path: " .. package.path)
print("")

-- Attempt to load rules.lua to report its absence cleanly
local rules_ok, rules_err = pcall(require, "solver.rules")
if not rules_ok then
   print("[ EXPECTED ] solver/rules.lua not found — this is TDD step 1 (red phase).")
   print("  Error: " .. tostring(rules_err))
   print("")
end

-- Load and run each test module.
-- Each module calls H.test() internally and returns the harness H.
-- We collect all results from each harness and print a combined summary.
local test_modules = {
   "solver.tests.test_deal",
   "solver.tests.test_win",
   "solver.tests.test_moves",
   "solver.tests.test_solvable",
   "solver.tests.test_fixes",
}

local total_passed = 0
local total_failed = 0

for _, mod_name in ipairs(test_modules) do
   print("--- " .. mod_name .. " ---")
   local ok, H = pcall(require, mod_name)
   if not ok then
      print("  ERROR loading module: " .. tostring(H))
      total_failed = total_failed + 1
   else
      -- Print individual results from this module's harness
      for _, r in ipairs(H.results) do
         if r.pass then
            print(string.format("  PASS  %s", r.name))
         else
            print(string.format("  FAIL  %s", r.name))
            if r.reason then
               print(string.format("        reason: %s", r.reason))
            end
         end
      end
      total_passed = total_passed + H.passed
      total_failed = total_failed + H.failed
   end
   print("")
end

print("=== SUMMARY ===")
print(string.format("Total: %d passed / %d failed", total_passed, total_failed))

if total_failed > 0 then
   if not rules_ok then
      print("")
      print("All failures are EXPECTED: solver/rules.lua not yet written.")
      print("TDD red phase confirmed. Write rules.lua to make these tests pass.")
   end
   os.exit(1)
else
   print("All tests passed!")
   os.exit(0)
end
