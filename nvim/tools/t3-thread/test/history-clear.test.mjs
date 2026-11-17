// L2: the exact production clear, through a real PTY into a Neovim terminal.
// No Lua source/config edits, GUI, hc or external service.
import test from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { CLEAR_HISTORY } from "../history-output.mjs";

test("H1-06a: clear drops old scrollback from a real Neovim terminal buffer", async () => {
  const peer = `process.stdout.write(Array.from({length:80},(_,i)=>'OLD_HISTORY_'+i+'\\r\\n').join('')+'BEFORE_READY\\r\\n');process.stdin.resume();process.stdin.once('data',()=>process.stdout.write(${JSON.stringify(CLEAR_HISTORY)}+'NEW_HISTORY\\r\\nAFTER_READY\\r\\n'));`;
  const lua = `
    vim.o.columns=100; vim.o.lines=24
    local buf=vim.api.nvim_get_current_buf()
    local job=vim.fn.jobstart({${JSON.stringify(process.execPath)},'-e',${JSON.stringify(peer)}},{term=true})
    local function text() return table.concat(vim.api.nvim_buf_get_lines(buf,0,-1,false),'\\n') end
    assert(vim.wait(3000,function() return text():find('BEFORE_READY',1,true) end,10),'initial terminal output missing')
    assert(vim.api.nvim_buf_line_count(buf)>60,'precondition: real scrollback exists')
    assert(text():find('OLD_HISTORY_0',1,true),'oldest history exists before clear')
    vim.fn.chansend(job,'reflow\\n')
    assert(vim.wait(3000,function() return text():find('AFTER_READY',1,true) end,10),'reflow output missing')
    assert(vim.wait(500,function() return not text():find('OLD_HISTORY_',1,true) end,10),'old scrollback survived clear: '..text())
    local _,count=text():gsub('NEW_HISTORY','')
    assert(count==1,'new history must occur once')
    print('H1_CLEAR_NVIM_OK')
    vim.fn.chanclose(job,'stdin')
  `;
  const child = spawn("nvim", ["--headless", "-u", "NONE", "-i", "NONE", "-n", "-c",
    `lua local ok,e=pcall(function() ${lua} end); if not ok then io.stderr:write(tostring(e)); vim.cmd('cquit 1') end`, "-c", "qa!"], {stdio: ["ignore", "pipe", "pipe"]});
  let output = "";
  child.stdout.on("data", d => output += d);
  child.stderr.on("data", d => output += d);
  const code = await new Promise(resolve => child.on("exit", resolve));
  assert.equal(code, 0, output);
  assert.match(output, /H1_CLEAR_NVIM_OK/);
});
