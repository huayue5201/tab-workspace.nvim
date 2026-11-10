-- 解耦冒烟测试：不装 neo-tree / resession / overseer / dap 也能 setup 并工作。
vim.opt.rtp:prepend(vim.fn.getcwd())

local ws = require("tab_workspace")
local before_exrc = vim.o.exrc
ws.setup({ hide_in_bar = function() return true end })

local function check(cond, msg)
	if not cond then
		error("FAIL: " .. msg, 0)
	end
end

check(package.loaded["tab_workspace.integrations.neo_tree"] == nil, "核心不加载 neo-tree 集成")
check(package.loaded["neo-tree"] == nil, "核心不 require neo-tree")
check(package.loaded["resession"] == nil, "核心不 require resession")
check(package.loaded["overseer"] == nil, "核心不 require overseer")
check(package.loaded["dap"] == nil, "核心不 require nvim-dap")
check(vim.o.exrc == before_exrc, "默认不接管 exrc")
check(require("tab_workspace.listed").is_bar_hidden(0) == true, "hide_in_bar 回调生效")
check(type(ws.root()) == "string" and ws.root() ~= "", "root() 可用")
check(type(ws.workspace_name()) == "string" and ws.workspace_name() ~= "", "workspace_name() 可用")
check(type(ws.visible_buffers()) == "table", "visible_buffers() 可用")
print("ok: 无第三方依赖时 setup / 公共 API 正常")
