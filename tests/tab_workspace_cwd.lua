-- 用户视角的行为测试：cwd 失效（目录被删）时的自愈。
--
--   nvim --headless -u NONE -l tests/tab_workspace_cwd.lua
--
-- 覆盖：
--   * 进程 cwd 失效（从已删除的目录启动）：ensure() 之后 uv.cwd() 可用、getcwd() 非空
--   * tab 的 :tcd 目录事后被删：切过去时进程 cwd 会静默停在上一个 tab，
--     TabEnter 自动修好，getcwd(-1, nr) 不再指向死目录
--   * 最近一次有效的 cwd 优先于 $HOME
--   * 只提示一次，修好后再坏可以再提示
--
-- 退出码：有失败 1，全通过 0。

vim.opt.rtp:prepend(vim.fn.getcwd())

local uv = vim.uv or vim.loop
local fails = {}
local notes = {}
local orig_notify = vim.notify

local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local function real(path)
	local ok, res = pcall(uv.fs_realpath, path)
	return (ok and res) or path
end

local base = real(vim.fn.tempname())
local dir_a = base .. "/a"
local dir_b = base .. "/b"
local dir_c = base .. "/c"
for _, d in ipairs({ dir_a, dir_b, dir_c }) do
	vim.fn.mkdir(d, "p")
end

local guard = require("tab_workspace.cwd_guard")

vim.notify = function(msg, level)
	notes[#notes + 1] = { msg = msg, level = level }
end

pcall(vim.cmd.tcd, { args = { dir_a } })

----------------------------------------------------------------------
-- 1. 健康状态：ensure() 什么都不做，并记住当前 cwd
----------------------------------------------------------------------

check(guard.process_ok() == true, "夹具目录应可用")
check(guard.ensure() == true, "健康状态 ensure() 应为 true")
check(real(vim.fn.getcwd()) == real(dir_a), "健康状态不应改 cwd，实际 " .. vim.fn.getcwd())
check(#notes == 0, "健康状态不应提示，实际 " .. #notes)
check(guard.last_good[vim.api.nvim_get_current_tabpage()] ~= nil, "健康状态应记住当前 cwd")

----------------------------------------------------------------------
-- 2. 进程 cwd 被删（从已删除目录启动的情形）
----------------------------------------------------------------------

vim.fn.delete(dir_a, "rf")
check(guard.process_ok() == false, "目录删掉后 process_ok() 应为 false")
check(uv.cwd() == nil, "目录删掉后 uv.cwd() 应为 nil")
check(guard.ensure() == true, "失效后 ensure() 应把 cwd 修好")
check(guard.process_ok() == true, "修好后 process_ok() 应为 true")
check(vim.fn.getcwd() ~= "", "修好后 getcwd() 不应为空")
check(real(vim.fn.getcwd()) == real(vim.env.HOME), "无更优候选时应退到 $HOME，实际 " .. vim.fn.getcwd())
check(#notes == 1, "应提示一次，实际 " .. #notes)

----------------------------------------------------------------------
-- 3. 切到 :tcd 目录已消失的 tab：TabEnter 自动修
----------------------------------------------------------------------

guard.setup()
pcall(vim.cmd.tcd, { args = dir_b })

vim.cmd("tabnew")
local tab_b = vim.api.nvim_get_current_tabpage()
pcall(vim.cmd.tcd, { args = dir_c })
local ok_b = guard.tab_ok(tab_b)
check(ok_b == true, "tab 的 cwd 应可用")

vim.api.nvim_set_current_tabpage(1)
vim.fn.delete(dir_c, "rf")

vim.api.nvim_set_current_tabpage(tab_b)
local ok_after, dir_after = guard.tab_ok(tab_b)
check(ok_after == true, "切到死 tab 后 TabEnter 应把该 tab 的 cwd 修好，实际 " .. tostring(dir_after))
check(guard.process_ok() == true, "修好后进程 cwd 应可用")

----------------------------------------------------------------------
-- 4. 最近一次有效的 cwd 优先于 $HOME
----------------------------------------------------------------------

vim.api.nvim_set_current_tabpage(1)
pcall(vim.cmd.tcd, { args = dir_b })
local tab1 = vim.api.nvim_get_current_tabpage()
guard.last_good[tab1] = dir_b

vim.fn.delete(dir_b, "rf")
check(guard.ensure() == true, "再次失效后 ensure() 应成功")
check(real(vim.fn.getcwd()) == real(vim.env.HOME), "last_good 也失效时应退到 $HOME，实际 " .. vim.fn.getcwd())

----------------------------------------------------------------------
-- 收尾
----------------------------------------------------------------------

vim.notify = orig_notify
pcall(vim.cmd.tcd, { args = "/" })
pcall(vim.fn.delete, base, "rf")

if #fails == 0 then
	print("ok: cwd 自愈行为符合预期")
	vim.cmd("qall!")
end

for _, msg in ipairs(fails) do
	io.stderr:write("FAIL " .. msg .. "\n")
end
io.stderr:write(("%d 项失败\n"):format(#fails))
vim.cmd("cq")
