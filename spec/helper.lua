-- Minimal test helpers for spec/run.lua: test cases, equality checks and the tally.
local Helper = {
    dir = nil,    -- folder of the specs, set by spec/run.lua
    file = nil,   -- spec file being run, set by spec/run.lua
    passed = 0,
    failed = 0,
}

local function show(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end
    if type(value) ~= "table" then
        return tostring(value)
    end
    local keys = {}
    for key in pairs(value) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. " = " .. show(value[key])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- Runs one case at once. A failure is reported with the spec file, the case and the line.
function Helper.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        Helper.passed = Helper.passed + 1
    else
        Helper.failed = Helper.failed + 1
        print(string.format("FAIL %s: %s\n    %s", Helper.file or "?", name, tostring(err)))
    end
end

-- Equality, deep for tables. The error points at the line of the spec that called it.
function Helper.eq(actual, expected, label)
    if not same(actual, expected) then
        error(string.format("%sexpected %s, got %s", label and (label .. ": ") or "",
            show(expected), show(actual)), 2)
    end
end

return Helper
