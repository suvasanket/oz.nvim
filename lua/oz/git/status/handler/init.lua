local modules = {
	"oz.git.status.handler.commit",
	"oz.git.status.handler.branch",
	"oz.git.status.handler.remote",
	"oz.git.status.handler.push",
	"oz.git.status.handler.pull",
    "oz.git.status.handler.fetch",
	"oz.git.status.handler.pick",
	"oz.git.status.handler.diff",
	"oz.git.status.handler.file",
	"oz.git.status.handler.stash",
	"oz.git.status.handler.reset",
	"oz.git.status.handler.navigate",
	"oz.git.status.handler.merge",
	"oz.git.status.handler.rebase",
	"oz.git.status.handler.quick_action",
	"oz.git.status.handler.worktree",
}

local handlers = {}
for _, name in ipairs(modules) do
	local ok, mod = pcall(require, name)
	if ok and mod then
		local key = name:match("[^%.]+$")
		handlers[key] = mod
	end
end

return handlers
