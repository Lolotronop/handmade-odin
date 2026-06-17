vim.notify("Loaded nvim.lua")

vim.keymap.set('n', '<leader>c', function()
    vim.system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "kill_all" }, nil, function()
        vim.notify("Killed")

        local time = vim.loop.hrtime()
        vim.system({ 'cmd', '/c', 'build.bat' }, nil, function()
            local elapsed = vim.loop.hrtime() - time
            vim.notify("Build in " .. elapsed / 1000000 .. " ms")

            vim.system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "run" }, nil, function()
                vim.notify("Running")
            end)
        end)
    end)
end, { desc = "Compile and run thru the raddbg debugger" })
