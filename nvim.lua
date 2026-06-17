vim.notify("Loaded nvim.lua")

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
        title = "Odin compiler errors",
        items = items,
    })

    if #items > 0 then
        vim.cmd("copen")
        vim.notify(
            string.format("Added %d Odin error(s) to quickfix", #items),
            vim.log.levels.INFO
        )
    else
        vim.notify("No Odin errors found", vim.log.levels.WARN)
    end
end

vim.keymap.set('n', '<leader>c', function()
    vim.system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "kill_all" }, nil, function()
        local time = vim.loop.hrtime()
        vim.system({ 'cmd', '/c', 'build.bat' }, { text = true }, function(obj)
            if obj.code ~= 0 then
                vim.notify("Build failed", vim.log.levels.ERROR)
                vim.schedule(function()
                    odin_errors_to_quickfix(obj.stderr)
                end)
                return
            end
            local elapsed = vim.loop.hrtime() - time

            vim.notify("Build in " .. elapsed / 1000000 .. " ms")

            vim.system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "run" })
        end)
    end)
end, { desc = "Compile and run thru the raddbg debugger" })
