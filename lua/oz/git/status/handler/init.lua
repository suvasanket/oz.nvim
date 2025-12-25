local modules = {
    "oz.git.status.handler.commit",
    "oz.git.status.handler.branch",
    "oz.git.status.handler.remote",
    "oz.git.status.handler.push_pull",
    "oz.git.status.handler.pick",
    "oz.git.status.handler.diff",
    "oz.git.status.handler.file",
    "oz.git.status.handler.other",
    "oz.git.status.handler.merge_rebase",
    "oz.git.status.handler.quick_action",
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
