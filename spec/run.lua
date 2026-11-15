-- Runs every spec/*_spec.lua with only the plugin's pure modules reachable; exits 1 on a failure.
--
--   cd vendor/koreader-emu/lib/koreader && ./luajit "$OLDPWD/spec/run.lua" [name_spec.lua ...]

local spec_dir = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local plugin_dir = spec_dir .. "/../chessbook.koplugin"

-- Only the plugin and the specs can be required, never KOReader, even when this runs from the
-- KOReader folder: a module of chess/ or model/ that needs KOReader fails to load here.
package.path = plugin_dir .. "/?.lua;" .. spec_dir .. "/?.lua"
package.cpath = ""

local Helper = require("helper")
Helper.dir = spec_dir

local function spec_files()
    if arg[1] then
        return { unpack(arg) }
    end
    local files = {}
    local listing = io.popen('ls -1 "' .. spec_dir .. '"')
    for name in listing:lines() do
        if name:match("_spec%.lua$") then
            files[#files + 1] = name
        end
    end
    listing:close()
    table.sort(files)
    return files
end

local started = os.clock()
for _, name in ipairs(spec_files()) do
    Helper.file = name
    local chunk, err = loadfile(spec_dir .. "/" .. name)
    if chunk then
        local ok, run_err = pcall(chunk)
        if not ok then
            Helper.failed = Helper.failed + 1
            print(string.format("FAIL %s: error outside a test\n    %s", name, tostring(run_err)))
        end
    else
        Helper.failed = Helper.failed + 1
        print(string.format("FAIL %s: cannot load\n    %s", name, tostring(err)))
    end
end

print(string.format("%d passed, %d failed (%.1f s)", Helper.passed, Helper.failed,
    os.clock() - started))
os.exit(Helper.failed == 0 and 0 or 1)
