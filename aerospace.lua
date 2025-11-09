local M = {}

local function ef(s, ...)
  hs.execute(string.format(s, ...))
end

M.reload_config = function()
  ef('aerospace reload-config')
end

function M:init()

end

return M
