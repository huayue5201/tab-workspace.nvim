-- 用户视角的行为测试：工作区（tab）列表与切换。
--
--   nvim --headless -u NONE -l tests/tab_workspace_tabs.lua
--
-- 覆盖：
--   * tab_items() 默认按最近使用排序（当前在前），字段完整
--   * tab_items({ order = "number" }) 按 tab 序号
--   * goto_tab() 接受 tabpage handle / tab 序号 / tab_items() 条目，越界返回 false
--   * picker() 走注入的 select，选中条目即切过去
--   * alternate() 在最近两个 tab 之间来回，MRU 顺序不会被自己踩乱
--
-- 退出码：有失败 1，全通过 0。

vim.opt.rtp:prepend(vim.fn.getcwd())

local ws = require("tab_workspace")
local fails = {}

local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local function eq(got, want, msg)
	check(vim.deep_equal(got, want), ("%s (got %s, want %s)"):format(msg, vim.inspect(got), vim.inspect(want)))
end

local base = vim.fn.fnamemodify(vim.fn.tempname(), ":p"):gsub("/+$", "")
local dirs = {}
for _, name in ipairs({ "proj_a", "proj_b", "proj_c" }) do
	dirs[name] = base .. "/" .. name
	vim.fn.mkdir(dirs[name], "p")
end

ws.setup({ guard_cwd = false })

local function new_tab(dir)
	vim.cmd("tabnew")
	vim.cmd("tcd " .. vim.fn.fnameescape(dir))
	return vim.api.nvim_get_current_tabpage()
end

-- tab1 用 proj_a，再新开 b、c：离开顺序 a、b，当前 c
vim.cmd("tcd " .. vim.fn.fnameescape(dirs.proj_a))
local tab_a = vim.api.nvim_get_current_tabpage()
local tab_b = new_tab(dirs.proj_b)
local tab_c = new_tab(dirs.proj_c)

-- ---- tab_items(): 最近使用排序 ----
local items = ws.tab_items()
eq(vim.tbl_map(function(it)
	return it.tab
end, items), { tab_c, tab_b, tab_a }, "默认按最近使用排序，当前 tab 在前")
eq({ items[1].current, items[2].current, items[3].current }, { true, false, false }, "current 字段")
eq({ items[1].number, items[2].number, items[3].number }, { 3, 2, 1 }, "number 是 tab 序号")
eq(
	vim.tbl_map(function(it)
		return it.name
	end, items),
	{ "proj_c", "proj_b", "proj_a" },
	"name 是根目录末段"
)
for _, it in ipairs(items) do
	check(type(it.dir) == "string" and it.dir ~= "", "dir 非空")
	check(it.buffers >= 1, "buffers 统计该 tab 的 buffer 数")
end

eq(
	vim.tbl_map(function(it)
		return it.number
	end, ws.tab_items({ order = "number" })),
	{ 1, 2, 3 },
	"order = number 按序号排"
)

-- ---- goto_tab(): 三种入参 ----
check(ws.goto_tab(1) == true and vim.api.nvim_get_current_tabpage() == tab_a, "goto_tab(1) 按序号")
check(ws.goto_tab(tab_b) == true and vim.api.nvim_get_current_tabpage() == tab_b, "goto_tab(handle)")
local item_a
for _, it in ipairs(ws.tab_items()) do
	if it.tab == tab_a then
		item_a = it
	end
end
check(ws.goto_tab(item_a) == true and vim.api.nvim_get_current_tabpage() == tab_a, "goto_tab(item)")
check(ws.goto_tab(99) == false, "goto_tab 越界返回 false")
check(ws.goto_tab({}) == false, "goto_tab 非 tab 条目返回 false")

-- ---- alternate(): 最近两个来回，MRU 不被踩乱 ----
vim.api.nvim_set_current_tabpage(tab_c)
ws.alternate()
check(vim.api.nvim_get_current_tabpage() == tab_a, "alternate 去最近用过的 tab")
ws.alternate()
check(vim.api.nvim_get_current_tabpage() == tab_c, "alternate 再切回，不来回抖动")

-- ---- picker(): 注入 select ----
local seen, formatted, prompt
ws.picker({
	select = function(list, opts, on_choice)
		seen = list
		prompt = opts.prompt
		formatted = vim.tbl_map(opts.format_item, list)
		for _, it in ipairs(list) do
			if it.kind == "tab" and it.tab == tab_b then
				on_choice(it)
				return
			end
		end
		on_choice(nil)
	end,
})
check(prompt == "Workspace", "picker 用注入的 select")
check(vim.api.nvim_get_current_tabpage() == tab_b, "picker 选中 tab 即切过去")
check(#seen == 4 and seen[#seen].kind == "new", "列表 = 3 个工作区 + 打开新目录")
check(formatted[1]:find("proj_c", 1, true) ~= nil, "format_item 带工作区名")
check(formatted[#formatted] == "+ Open directory…", "末项是打开新目录")

-- 取消选择不应改变当前 tab
ws.picker({
	select = function(_, _, on_choice)
		on_choice(nil)
	end,
})
check(vim.api.nvim_get_current_tabpage() == tab_b, "取消选择保持当前 tab")

for _, name in ipairs({ "proj_a", "proj_b", "proj_c" }) do
	vim.fn.delete(dirs[name], "rf")
end
vim.fn.delete(base, "rf")

if #fails > 0 then
	io.stderr:write(table.concat(fails, "\n") .. "\n")
	os.exit(1)
end
print("ok: 工作区列表 / 切换 / MRU 顺序正常")
