vim.notify("Loaded nvim.lua")

local quickfix_title = "Odin compiler errors"
local function odin_errors_to_quickfix(text)
    local items = {}

    -- Matches:
    -- D:/path/file.odin(13:18) Error: message
    local pattern = "^(.+)%((%d+):(%d+)%)%s+([^:]+):%s*(.+)$"

    for line in text:gmatch("[^\r\n]+") do
        local filename, lnum, col, severity, message = line:match(pattern)

        if filename then
            local type_map = {
                Error = "E",
                Warning = "W",
                Note = "I",
                Info = "I",
            }

            table.insert(items, {
                filename = filename,
                lnum = tonumber(lnum),
                col = tonumber(col),
                text = message,
                type = type_map[severity] or "E",
            })
        end
    end

    vim.fn.setqflist({}, "r", {
        title = quickfix_title,
        items = items,
    })


    if #items > 0 then
        local current_win = vim.api.nvim_get_current_win()

        vim.cmd("copen")

        if vim.api.nvim_win_is_valid(current_win) then
            vim.api.nvim_set_current_win(current_win)
        end
        vim.notify(
            string.format("Added %d Odin error(s) to quickfix", #items),
            vim.log.levels.INFO
        )
    end
end

---@class AwaitSystemOpts
---@field clear_env? boolean
---@field cwd? string
---@field detach? boolean
---@field env? table<string, string|number>
---@field stdin? string|string[]|true
---@field stdout? boolean|fun(err: string?, data: string?)
---@field stderr? boolean|fun(err: string?, data: string?)
---@field text? boolean
---@field timeout? integer

---@class AwaitSystemCompleted
---@field code integer
---@field signal integer
---@field stdout? string
---@field stderr? string

---@param co thread
---@param ... any
local function resume_or_notify(co, ...)
    local ok, err = coroutine.resume(co, ...)

    if not ok then
        vim.notify(
            debug.traceback(co, tostring(err)),
            vim.log.levels.ERROR
        )
    end
end

---@param fn async fun()
---@return thread
local function async(fn)
    local co = coroutine.create(fn)
    resume_or_notify(co)
    return co
end

---@async
---@param cmd string[]
---@param opts? AwaitSystemOpts
---@return AwaitSystemCompleted
local function await_system(cmd, opts)
    local co, is_main = coroutine.running()

    assert(
        co and not is_main,
        "await_system() must be called inside async()"
    )

    vim.system(cmd, opts or {}, function(result)
        vim.schedule(function()
            resume_or_notify(co, result)
        end)
    end)

    return coroutine.yield()
end

--- @param mode string
--- @return boolean
local function build(mode)
    local time = vim.loop.hrtime()
    local status = await_system({ 'cmd', '/c', 'build.bat', mode }, { text = true })
    if status.code ~= 0 then
        vim.notify("Build failed", vim.log.levels.ERROR)
        vim.schedule(function()
            odin_errors_to_quickfix(status.stderr)
        end)
        return false
    end

    -- clear the quickfix list on successful compile
    vim.schedule(function()
        local qf = vim.fn.getqflist({ title = 1 })
        if qf.title == quickfix_title then
            vim.fn.setqflist({}, "r")
            vim.cmd("cclose")
        end
    end)

    local elapsed = vim.loop.hrtime() - time

    vim.notify("Build " .. mode .. " in " .. elapsed / 1000000 .. " ms")
    return true
end

local function run()
    local status = await_system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "run" })
    return status.code == 0
end

---@return boolean
local function kill()
    local status = await_system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "kill_all" })
    if status.code ~= 0 then
        vim.notify("Failed to kill the program")
        return false
    end
    return true
end

local function full_recompile()
    local ok = false

    ok = kill()
    if not ok then return end

    ok = build("full")
    if not ok then return end

    ok = run()
    if not ok then return end
end

local function game_recompile()
    local ok = false

    ok = build("game")
    if not ok then return end
end

vim.keymap.set('n', '<leader>cf', function() async(full_recompile) end,
    { desc = "[C]ompile [F]ull and re-run in raddbg" })


vim.keymap.set('n', '<leader>cc', function() async(game_recompile) end,
    { desc = "[C]ompile [C]ode only the game part" })
