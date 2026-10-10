-- Minimal JSON decoder — TEST-ONLY stand-in for the worker's host API
-- (aav2.json_decode). Handles objects, arrays, strings (with \" \\ \/ \b
-- \f \n \r \t \uXXXX for BMP), numbers, true/false/null. Returns nil on any
-- syntax error or trailing garbage, like the host function.
local J = {}

local function skip_ws(s, i)
  return s:find("[^ \t\r\n]", i) or #s + 1
end

local decode_value

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8_char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
  return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
end

local function decode_string(s, i)
  local out, j = {}, i + 1
  while true do
    local c = s:sub(j, j)
    if c == "" then return nil end
    if c == '"' then return table.concat(out), j + 1 end
    if c == "\\" then
      local e = s:sub(j + 1, j + 1)
      if e == "u" then
        local hex = s:sub(j + 2, j + 5)
        if not hex:match("^%x%x%x%x$") then return nil end
        out[#out + 1] = utf8_char(tonumber(hex, 16))
        j = j + 6
      elseif escapes[e] then
        out[#out + 1] = escapes[e]
        j = j + 2
      else
        return nil
      end
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
end

function decode_value(s, i)
  i = skip_ws(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local obj = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "}" then return obj, i + 1 end
    while true do
      if s:sub(i, i) ~= '"' then return nil end
      local k; k, i = decode_string(s, i)
      if not k then return nil end
      i = skip_ws(s, i)
      if s:sub(i, i) ~= ":" then return nil end
      local v; v, i = decode_value(s, i + 1)
      if i == nil then return nil end
      obj[k] = v
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == "}" then return obj, i + 1 end
      if d ~= "," then return nil end
      i = skip_ws(s, i + 1)
    end
  elseif c == "[" then
    local arr = {}
    i = skip_ws(s, i + 1)
    if s:sub(i, i) == "]" then return arr, i + 1 end
    while true do
      local v; v, i = decode_value(s, i)
      if i == nil then return nil end
      arr[#arr + 1] = v
      i = skip_ws(s, i)
      local d = s:sub(i, i)
      if d == "]" then return arr, i + 1 end
      if d ~= "," then return nil end
      i = i + 1
    end
  elseif c == '"' then
    return decode_string(s, i)
  elseif s:sub(i, i + 3) == "true" then return true, i + 4
  elseif s:sub(i, i + 4) == "false" then return false, i + 5
  elseif s:sub(i, i + 3) == "null" then return J.null, i + 4
  else
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if num and #num > 0 and tonumber(num) then return tonumber(num), i + #num end
    return nil
  end
end

J.null = setmetatable({}, { __tostring = function() return "null" end })

function J.decode(s)
  local ok, v, i = pcall(decode_value, s, 1)
  if not ok or i == nil then return nil end
  if skip_ws(s, i) <= #s then return nil end -- trailing garbage
  return v
end

return J
