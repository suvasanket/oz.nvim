local modules = {
    "oz.git.log.handler.cherry_pick",
    "oz.git.log.handler.commit",
    "oz.git.log.handler.diff",
    "oz.git.log.handler.rebase",
    "oz.git.log.handler.reset",
    "oz.git.log.handler.revert",
    "oz.git.log.handler.quick_action",
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
