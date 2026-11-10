local M = {}

function M.check()
	local health = vim.health or require("health")
	health.start("tab_workspace")
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim >= 0.10 required")
	end
	local ok = pcall(require, "tab_workspace")
	health[ok and "ok" or "error"](ok and "core module loads" or "core module failed to load")
	local integrations = {
		{ "neo-tree (optional multi-root source)", "neo-tree" },
		{ "resession (optional sessions)", "resession" },
		{ "overseer (optional .nvim.lua w.task)", "overseer" },
		{ "nvim-dap (optional .nvim.lua w.launch)", "dap" },
	}
	for _, it in ipairs(integrations) do
		local found = pcall(require, it[2])
		health.info(string.format("%s: %s", it[1], found and "found" or "not installed (optional)"))
	end
	health.info("workspaces (tabs): " .. #vim.api.nvim_list_tabpages())
end

return M
