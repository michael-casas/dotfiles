-- A real :confirm qall path, with no hc process and no document writes.
vim.opt.rtp:prepend(vim.fn.getcwd() .. "/nvim")
local writes = 0
package.loaded["hcmux.core"] = {
  doc_set = function()
    writes = writes + 1
    error("must not replace saved editor layout")
  end,
}
local session = require("hcmux.session")
vim.t.hcmux_session_skip = true
session.name = "unit-t3-only"
session.state = "attached"
session.last_text = "previous editor layout"
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    assert(writes == 0 and session.last_text == "previous editor layout")
    assert(session.released, "Detach reaches quit without a serialized layout")
    print("T3-only Detach test passed; saved editor layout untouched")
  end,
})
session.detach()
error("Detach should have quit")
