-- Thin local adapter. Policy, transport, paths and synchronization live in the CLI.
local M = {}

local function valid(value)
  return type(value) == "string" and #value > 0 and #value <= 64 and value:match("^[A-Za-z0-9][A-Za-z0-9_.-]*$") ~= nil
end

local function notice(message)
  vim.notify("EnviRemote: " .. message, vim.log.levels.WARN)
end

function M.open(host)
  if not valid(host) then
    notice("invalid host identifier")
    return
  end
  -- Ordinary hcmux session restoration reattaches this client, never replays SSH.
  return require("hcmux.term").open({ "envi-remote", host }, {
    where = "vsplit",
    title = "Remote: " .. host,
    labels = { ["envi.remote.profile"] = "minimal" },
  })
end

function M.pick()
  local ok = pcall(vim.system, { "envi-remote", "hosts" }, { text = true, timeout = 5000 }, function(result)
    vim.schedule(function()
      if result.code ~= 0 or type(result.stdout) ~= "string" or #result.stdout > 65536 then
        notice("cannot read approved hosts; check private CLI policy")
        return
      end
      local hosts, seen = {}, {}
      for host in result.stdout:gmatch("[^\n]+") do
        if not valid(host) or seen[host] then
          notice("invalid approved-host response")
          return
        end
        seen[host] = true
        hosts[#hosts + 1] = host
      end
      if #hosts == 0 then
        notice("no approved hosts")
        return
      end
      vim.ui.select(hosts, { prompt = "Approved remote environment" }, function(host)
        if host then
          M.open(host)
        end
      end)
    end)
  end)
  if not ok then
    notice("envi-remote unavailable on local PATH")
  end
end

function M.setup()
  vim.api.nvim_create_user_command("EnviRemote", function()
    M.pick()
  end, { desc = "Pick an approved remote environment", force = true })
end

return M
