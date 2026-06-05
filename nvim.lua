vim.keymap.set('n', '<leader>c', function()
    vim.notify("Building...")
    vim.fn.system({ 'odin', 'build', '.', '--debug' })
    vim.notify("Finished build")

    vim.notify("Killing...")
    vim.fn.system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "kill_all" })
    vim.notify("Finished Killing")


    vim.notify("Running...")
    vim.fn.system({ "D:/soft/raddbg/raddbg.exe", "--ipc", "run" })
    vim.notify("Ran")
end, { desc = "Compile and run thru the raddbg debugger" })
