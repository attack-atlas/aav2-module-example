-- Test runner: `lua tests/run.lua` from the repo root (Lua 5.3+).
-- Loads the parser exactly as the worker would (as a chunk with the host
-- API installed as the global `aav2`), feeds the fixture, and asserts the
-- normalized output.
package.path = "./?.lua;" .. package.path
local json = require("tests.json")

aav2 = { json_decode = json.decode }  -- host API stand-in

local parser = dofile("parser/subfinder.lua")
local failures = 0

local function check(name, cond, detail)
  if cond then
    print("PASS  " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. (detail and ("  -- " .. detail) or ""))
  end
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

-- 1. fixture: noise-tolerant parse, dedupe, lower-casing
local out = parser.parse(read("tests/fixtures/raw.txt"))
local fqdns = {}
for _, a in ipairs(out.assets) do
  check("asset type is subdomain (" .. a.fqdn .. ")", a.type == "subdomain")
  fqdns[#fqdns + 1] = a.fqdn
end
check("fixture yields 3 unique subdomains", #out.assets == 3, table.concat(fqdns, ","))
check("order + normalization", table.concat(fqdns, ",") == "api.example.com,www.example.com,mail.example.com",
  table.concat(fqdns, ","))
check("parse_skipped counts noise/scalar/hostless lines", out.parse_skipped == 4, tostring(out.parse_skipped))
check("edges is an empty list", type(out.edges) == "table" and #out.edges == 0)

-- 2. empty output is success with zero assets
local empty = parser.parse("")
check("empty input -> zero assets", #empty.assets == 0 and empty.parse_skipped == 0)

-- 3. a non-string host is skipped, not crashed on
local weird = parser.parse('{"host":42}\n{"host":null}\n[1,2]')
check("non-string host / arrays are skipped", #weird.assets == 0 and weird.parse_skipped == 3,
  tostring(weird.parse_skipped))

-- 4. sandbox expectation: the parser must not need io/os
local env = { aav2 = aav2, string = string, table = table, type = type, ipairs = ipairs, pairs = pairs,
              tostring = tostring, tonumber = tonumber }
local chunk = assert(loadfile("parser/subfinder.lua", "t", env))
local sandboxed = chunk()
local sb = sandboxed.parse('{"host":"a.example.com"}')
check("runs in a sandbox without io/os", #sb.assets == 1 and sb.assets[1].fqdn == "a.example.com")

if failures > 0 then
  print(failures .. " failure(s)")
  os.exit(1)
end
print("all tests passed")
