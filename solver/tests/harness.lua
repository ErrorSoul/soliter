-- Test harness factory for solver/rules.lua
-- Run with: /opt/homebrew/bin/lua solver/tests/run_all.lua
-- (from repo root)
--
-- Usage in test modules:
--   local new_harness = require("solver.tests.harness")
--   local H = new_harness()
--   H.test("name", function(rules) ... return true/false, "reason" end)
--   return H
--
-- Each require("solver.tests.harness") call returns the factory function.
-- Each H = new_harness() creates a fresh result table (no shared state).

-- Attempt to load rules.lua once at module load time.
-- All harness instances share this result (rules either exists or doesn't).
local rules_ok, rules_module = pcall(function()
   return require("solver.rules")
end)

local RULES        = rules_ok and rules_module or nil
local RULES_ABSENT = not rules_ok

-- Factory: returns a new independent harness instance.
local function new_harness()
   local H = {
      passed  = 0,
      failed  = 0,
      results = {},
      rules   = RULES,
      rules_absent = RULES_ABSENT,
   }

   -- Helper: assert equality, print diff on mismatch
   function H.assert_eq(label, got, expected)
      if got == expected then return true end
      io.write(string.format("  MISMATCH in '%s':\n    got:      %s\n    expected: %s\n",
         label, tostring(got), tostring(expected)))
      return false
   end

   -- Register and immediately run a single test.
   -- test_fn(rules) -> (bool, reason|nil)
   function H.test(name, test_fn)
      local ok, err = pcall(function()
         if H.rules_absent then
            table.insert(H.results, { name=name, pass=false,
               reason="rules.lua absent (expected during TDD step 1)" })
            H.failed = H.failed + 1
            return
         end
         local pass, reason = test_fn(H.rules)
         if pass then
            H.passed = H.passed + 1
            table.insert(H.results, { name=name, pass=true })
         else
            H.failed = H.failed + 1
            table.insert(H.results, { name=name, pass=false,
               reason=reason or "assertion failed" })
         end
      end)
      if not ok then
         H.failed = H.failed + 1
         table.insert(H.results, { name=name, pass=false,
            reason="EXCEPTION: " .. tostring(err) })
      end
   end

   function H.report()
      print("\n=== TEST RESULTS ===")
      for _, r in ipairs(H.results) do
         if r.pass then
            print(string.format("  PASS  %s", r.name))
         else
            print(string.format("  FAIL  %s  -- %s", r.name, r.reason or "?"))
         end
      end
      print(string.format("\n%d passed / %d failed", H.passed, H.failed))
      if H.rules_absent then
         print("(All failures are expected: rules.lua not yet written -- TDD red phase)")
      end
      return H.failed == 0
   end

   return H
end

return new_harness
