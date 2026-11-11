-- cwd 自愈：cwd 指向一个已经不存在的目录时，Neovim 不会报错，只会静默降级。
--
-- 两种坏状态，症状完全不同：
--   * 进程 cwd 失效（从已删除的目录启动 nvim）：uv.cwd() == nil、getcwd() == ""。
--     任何在 setup 阶段读 cwd 的插件当场炸——lazydev/obsidian 是
--     assert(uv.cwd())，neogit 是 cwd:gsub()，procman 把 nil 传给 fs_scandir，
--     codecompanion 在 vim.fs.abspath 里 assert，fff 把空 cwd 误判成"扫描 /"。
--     看起来像一批互不相关的插件同时坏了，根因只有一个。
--   * tab 的 :tcd 目录事后被删：切过去时 chdir 失败，进程 cwd 静默留在上一个
--     tab 的目录（不报错、不为空），于是新开的文件/终端/LSP 全部落到错的根。
--
-- 判定必须分开做：进程 cwd 用 uv.cwd()，tab cwd 用 getcwd(-1, tabnr)。
-- 后者才是 :tcd 存下来的值，也是切 tab 失败后唯一能看出"这个 tab 死了"的地方。
local M = {}

local GROUP = "TabWorkspaceCwd"

---@type table<integer, string> tabpage -> 最近一次有效的 cwd
M.last_good = {}

---@type table<integer, true> 已就每个 tab 提示过一次
local notified = {}

--- 目录可用？
---@param dir any
---@return boolean
function M.valid(dir)
	return type(dir) == "string" and dir ~= "" and vim.fn.isdirectory(dir) == 1
end

--- tab 的 :tcd 值（同时返回原始值，便于提示"原来是哪个目录没了"）
---@param tabpage? integer
---@return boolean ok, string? dir
function M.tab_ok(tabpage)
	tabpage = tabpage or vim.api.nvim_get_current_tabpage()
	local nr = vim.api.nvim_tabpage_get_number(tabpage)
	local got, dir = pcall(vim.fn.getcwd, -1, nr)
	return got and M.valid(dir), dir
end

--- 进程 cwd 可用？
---@return boolean
function M.process_ok()
	if vim.uv.cwd() == nil then
		return false
	end
	local got, dir = pcall(vim.fn.getcwd)
	return got and M.valid(dir)
end

--- tab 里显示的第一个真实文件所在目录（有文件时它比 $HOME 更接近"用户想在哪"）
---@param tabpage integer
---@return string? dir
local function tab_file_dir(tabpage)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].buftype == "" then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" then
				local dir = vim.fn.fnamemodify(name, ":p:h")
				if M.valid(dir) then
					return dir
				end
			end
		end
	end
	return nil
end

--- 候选目录：最近一次有效 cwd → tab 里文件的目录 → $HOME → 配置目录 → nvim 可执行文件目录
---@param tabpage integer
---@return string dir
local function pick_dir(tabpage)
	-- 不能用带 nil 的表配 ipairs：nil 会截断遍历，后面能用的候选永远试不到
	local candidates = {}
	local function add(dir)
		if dir ~= nil and dir ~= "" then
			candidates[#candidates + 1] = dir
		end
	end
	add(M.last_good[tabpage])
	add(tab_file_dir(tabpage))
	add(vim.env.HOME)
	add(vim.fn.stdpath("config"))
	add(vim.fs.dirname(vim.v.progpath))
	for _, dir in ipairs(candidates) do
		if M.valid(dir) then
			return dir
		end
	end
	return "/"
end

--- 把当前 tab 的 cwd 拉回一个有效目录（只对当前 tab 生效：:tcd 是 tab 作用域的）
---@param tabpage integer
---@param dir string
---@param msg string
local function repair(tabpage, dir, msg)
	if not pcall(vim.cmd.tcd, { args = { dir } }) then
		return false
	end
	M.last_good[tabpage] = dir
	if not notified[tabpage] then
		notified[tabpage] = true
		vim.notify(msg, vim.log.levels.WARN)
	end
	return true
end

--- 校验并修复当前 tab 的 cwd。可安全重复调用。
---@return boolean healthy 修复后是否处于可用状态
function M.ensure()
	local tabpage = vim.api.nvim_get_current_tabpage()
	local tab_ok, tab_dir = M.tab_ok(tabpage)
	local proc_ok = M.process_ok()

	if tab_ok and proc_ok then
		M.last_good[tabpage] = tab_dir
		notified[tabpage] = nil
		return true
	end

	local dir = pick_dir(tabpage)
	local msg
	if not proc_ok then
		msg = string.format(
			"tab-workspace: current directory no longer exists, switched to %s",
			dir
		)
	else
		msg = string.format(
			"tab-workspace: workspace root %s no longer exists, switched to %s",
			tostring(tab_dir),
			dir
		)
	end
	return repair(tabpage, dir, msg) and M.process_ok()
end

--- 挂上监护（TabEnter 时查一次；DirChanged 时记住有效值）。setup() 会调用。
---@param opts? { enabled?: boolean }
function M.setup(opts)
	opts = opts or {}
	if opts.enabled == false then
		return
	end
	-- 先自愈一次：启动时的坏 cwd 必须在这里被拉回来，
	-- 否则后面每个依赖 cwd 的插件 setup 都会炸。
	M.ensure()

	local group = vim.api.nvim_create_augroup(GROUP, { clear = true })

	-- 切 tab 时查：进程 cwd 这时可能静默停在上一个 tab，只有 getcwd(-1, nr) 能看出问题
	vim.api.nvim_create_autocmd("TabEnter", {
		group = group,
		callback = function()
			M.ensure()
		end,
	})

	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			local tabpage = vim.api.nvim_get_current_tabpage()
			local ok, dir = M.tab_ok(tabpage)
			if ok then
				M.last_good[tabpage] = dir
				notified[tabpage] = nil
			end
		end,
	})
end

return M
