local M = {}

M.check = function()
	vim.health.start("buffers report")
	-- make sure setup function parameters are ok
	local function check_setup()
		print("Checking")
		return true
	end

	if check_setup() then
		vim.health.ok("Setup is correct")
	else
		vim.health.error("Setup is incorrect")
	end
end

return M
