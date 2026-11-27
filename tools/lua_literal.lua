-- Deterministic Lua 5.1 literals for the bundled data importer.
local function keys(tableToSort)
    local result = {}
    for key in pairs(tableToSort or {}) do
        result[#result + 1] = key
    end
    table.sort(result, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        if type(a) == "boolean" then return a == false and b == true end
        return a < b
    end)
    return result
end

local keywords = {}
local keywordList = "and break do else elseif end false for function if in local nil not or repeat return " ..
    "then true until while"
for word in keywordList:gmatch("%a+") do keywords[word] = true end

local function literal(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" then
        -- Race masks pass 2^32, so whole numbers are written out in full.
        if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
            return string.format("%.0f", value)
        end
        return string.format("%.10g", value)
    end
    if kind == "boolean" then return tostring(value) end
    assert(kind == "table", "Unexpected literal type: " .. kind)
    local parts, nextIndex = {}, 1
    for _, key in ipairs(keys(value)) do
        if key == nextIndex then
            parts[#parts + 1] = literal(value[key])
            nextIndex = nextIndex + 1
        elseif type(key) == "string" and key:match("^[%a_][%w_]*$") and not keywords[key] then
            parts[#parts + 1] = key .. "=" .. literal(value[key])
        else
            parts[#parts + 1] = "[" .. literal(key) .. "]=" .. literal(value[key])
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

return keys, literal
