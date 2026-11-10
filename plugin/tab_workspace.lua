-- 命令入口：不自动 setup，配置由用户显式调用 require("tab_workspace").setup()
vim.api.nvim_create_user_command("TabWorkspace", function(args)
	local sub = args.fargs[1]
	local ws = require("tab_workspace")
	if sub == "picker" or sub == nil then
		ws.picker()
	elseif sub == "new" then
		ws.new_workspace(args.fargs[2])
	elseif sub == "close" then
		ws.close_workspace()
	elseif sub == "rename" then
		ws.rename_workspace()
	elseif sub == "edit" then
		ws.edit_local_settings()
	elseif sub == "reload" then
		ws.reload_local_settings()
	elseif sub == "attach" then
		ws.attach_root(args.fargs[2])
	elseif sub == "detach" then
		ws.detach_root(args.fargs[2])
	elseif sub == "tree" then
		vim.cmd("Neotree workspace toggle")
	else
		vim.notify("TabWorkspace: unknown subcommand: " .. tostring(sub), vim.log.levels.ERROR)
	end
end, {
	nargs = "*",
	desc = "Tab workspace: picker/new/close/rename/edit/reload/attach/detach/tree",
	complete = function()
		return { "picker", "new", "close", "rename", "edit", "reload", "attach", "detach", "tree" }
	end,
})
