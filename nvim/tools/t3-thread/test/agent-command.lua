-- Narrow t3.open options regression: no core process or T3 thread is started.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local calls, commands, stops = {}, {}, 0
package.loaded["hcmux.core"] = { get = function() end }
package.loaded["hcmux.term"] = {
  addr_of = function() end,
  open = function(argv, opts)
    calls[#calls + 1] = { argv = argv, opts = opts }
    local buf = vim.api.nvim_create_buf(false, true)
    if opts.where == "float" then
      vim.api.nvim_open_win(
        buf,
        true,
        { relative = "editor", width = 40, height = 10, row = 0, col = 0, border = "rounded" }
      )
    else
      vim.api.nvim_set_current_buf(buf)
    end
    -- Mirror term.lua's synchronous auto-insert and scheduled BufEnter hook.
    vim.cmd.startinsert()
    vim.schedule(function()
      vim.cmd.startinsert()
    end)
    return buf, "mock-new"
  end,
}
local startinsert, stopinsert = vim.cmd.startinsert, vim.cmd.stopinsert
vim.cmd.startinsert = function()
  commands[#commands + 1] = "insert"
end
vim.cmd.stopinsert = function()
  commands[#commands + 1] = "command"
  stops = stops + 1
end
local t3 = require("hcmux.t3")
t3.open("new", { mode = "command", cwd = "/projects/target" })
assert(calls[1].argv[3] == "new" and calls[1].opts.cwd == "/projects/target")
assert(stops == 1, "COMMAND applied synchronously")
vim.wait(20, function()
  return false
end)
assert(stops == 2 and commands[#commands] == "command", "COMMAND wins after term's scheduled auto-insert")
local config = vim.api.nvim_win_get_config(0)
assert(vim.inspect(config.title):find("COMMAND", 1, true), "COMMAND title")
t3.open("existing")
vim.wait(20, function()
  return false
end)
assert(stops == 2 and commands[#commands] == "insert", "default INSERT is unchanged")
vim.cmd.startinsert, vim.cmd.stopinsert = startinsert, stopinsert
print("AGENT new-thread COMMAND options tests passed")
