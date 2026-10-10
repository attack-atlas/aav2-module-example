-- subfinder parser module (Lua runtime) — aav2 normalized output, schema v1.
--
-- Contract (mirrors the aav2 parser pipeline):
--   input : raw captured output as ONE string (JSON lines from `subfinder -json`,
--           possibly interleaved with log noise, ANSI escapes, CRLF line ends)
--   output: { assets = {...}, edges = {...}, parse_skipped = <int> }
--           each asset is { type = "subdomain", fqdn = "<host>" }
--
-- Host API (provided by the worker's Lua runtime; sandboxed — no io/os):
--   aav2.json_decode(s) -> table|nil   decode one JSON value, nil on error
--
-- Pure function: no globals written, no I/O.

local M = {}

local function trim_cr(line)
  return (line:gsub("\r$", ""))
end

function M.parse(raw)
  local assets, seen, skipped = {}, {}, 0
  for raw_line in (raw .. "\n"):gmatch("(.-)\n") do
    local line = trim_cr(raw_line)
    if #line > 0 then
      local rec = aav2.json_decode(line)
      local host = type(rec) == "table" and rec.host or nil
      if type(host) == "string" and #host > 0 then
        host = host:lower()
        if not seen[host] then
          seen[host] = true
          assets[#assets + 1] = { type = "subdomain", fqdn = host }
        end
      else
        skipped = skipped + 1   -- noise, scalar JSON, or object without .host
      end
    end
  end
  return { assets = assets, edges = {}, parse_skipped = skipped }
end

return M
