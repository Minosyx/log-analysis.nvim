-- Neovim plugin for log analysis.

local M = {}

-- Default configuration
---@class Config
---@field filters_file string Path to the filters JSON file
---@field max_filters number Maximum number of filters allowed
M.config = {
	filters_file = vim.fn.stdpath("config") .. "/log_analysis_filters.json",
	max_filters = 20,
}

---@class Filter
---@field regex string The regex pattern for the filter
---@field color string The color for highlighting
---@field isHighlighted boolean Whether to highlight matching lines
---@field isShown boolean Whether to show the filter

-- Table to store filters
---@type Filter[]
M.filters = {}

-- Load filters from JSON file
local function load_filters()
	local file = io.open(M.config.filters_file, "r")
	if file then
		local content = file:read("*a")
		file:close()
		local ok, data = pcall(vim.json.decode, content)
		if ok then
			M.filters = data
			vim.notify("Loaded " .. #M.filters .. " filters.")
		else
			M.filters = {}
			vim.notify("Failed to parse filters file. Starting with empty filters.", vim.log.levels.WARN)
		end
	else
		M.filters = {}
	end
end

-- Save filters to JSON file
local function save_filters()
	local file = io.open(M.config.filters_file, "w")
	if file then
		file:write(vim.json.encode(M.filters))
		file:close()
		vim.notify("Saved " .. #M.filters .. " filters.")
	else
		vim.notify("Failed to save filters.", vim.log.levels.ERROR)
	end
end

-- Create custom highlight groups for filters
local function setup_highlight_groups()
	for i, filter in ipairs(M.filters) do
		local hl_name = "LogFilter" .. i
		vim.api.nvim_set_hl(0, hl_name, { bg = filter.color })
	end
end

-- Clear custom highlight groups
local function clear_highlight_groups()
	for i = 1, #M.filters do
		local hl_name = "LogFilter" .. i
		vim.api.nvim_set_hl(0, hl_name, {})
	end
end

-- Apply filters to the current buffer
local function apply_highlights()
	-- Clear existing highlights
	if M.match_ids then
		for _, id in ipairs(M.match_ids) do
			pcall(vim.fn.matchdelete, id)
		end
	end
	M.match_ids = {}

	local win = vim.api.nvim_get_current_win()
	for i, filter in ipairs(M.filters) do
		if filter.isHighlighted then
			local hl_name = "LogFilter" .. i
			local pattern = "^.*" .. filter.regex .. ".*$"
			local id = vim.fn.matchadd(hl_name, pattern, 10, -1, { window = win })
			table.insert(M.match_ids, id)
		end
	end
end

-- Toggle focus mode: create a new buffer with filtered lines
local function toggle_focus_mode()
	local buf = vim.api.nvim_get_cuttern_buf()
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local filtered_lines = {}

	for _, line in ipairs(lines) do
		local keep = false
		for _, filter in ipairs(M.filters) do
			if filter.isShown and string.match(line, filter.regex) then
				keep = true
				break
			end
		end
		if keep then
			table.insert(filtered_lines, line)
		end
	end

	if #filtered_lines > 0 then
		local new_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, filtered_lines)
		vim.api.nvim_set_option_value("modifiable", false, { buf = new_buf })
		vim.api.nvim_buf_set_name(new_buf, "LogFocusMode")
		vim.api.nvim_set_current_buf(new_buf)
	else
		vim.notify("No lines match the current filters.", vim.log.levels.INFO)
	end
end

-- Add a new filter
function M.add_filter(regex, color)
	if #M.filters >= M.config.max_filters then
		vim.notify("Maximum number of filters reached.", vim.log.levels.WARN)
		return
	end
	table.insert(M.filters, {
		regex = regex,
		color = color or string.format("#%06x", math.random(0, 0xFFFFFF)),
		isHighlighted = true,
		isShown = true,
	})
	vim.notify("Added new filter: " .. regex)
	setup_highlight_groups()
	apply_highlights()
end

-- Edit a filter by index
function M.edit_filter(index, regex, color)
	if not M.filters[index] then
		vim.notify("Filter not found.", vim.log.levels.WARN)
		return
	end
	M.filters[index].regex = regex
	M.filters[index].color = color or M.filters[index].color
	vim.notify("Edited filter: " .. regex)
	setup_highlight_groups()
	apply_highlights()
end

-- Remove a filter by index
function M.remove_filter(index)
	if not M.filters[index] then
		vim.notify("Filter not found.", vim.log.levels.WARN)
		return
	end
	table.remove(M.filters, index)
	vim.notify("Removed filter at index: " .. index)
	clear_highlight_groups()
	setup_highlight_groups()
	apply_highlights()
end

-- Toggle highlight for a filter by index
function M.toggle_highlight(index)
	if not M.filters[index] then
		vim.notify("Filter not found.", vim.log.levels.WARN)
		return
	end
	M.filters[index].isHighlighted = not M.filters[index].isHighlighted
	apply_highlights()
end

-- Toggle show for a filter by index
function M.toggle_show(index)
	if not M.filters[index] then
		vim.notify("Filter not found.", vim.log.levels.WARN)
		return
	end
	M.filters[index].isShown = not M.filters[index].isShown
end

-- Export filters to JSON file
function M.export_filters()
	save_filters()
end

-- Import filters from JSON file
function M.import_filters()
	load_filters()
	clear_highlight_groups()
	setup_highlight_groups()
	apply_highlights()
end

-- Setup function to initialize the plugin
function M.setup(opts)
	M.config = vim.tbl_extend("force", M.config, opts or {})

	-- Commands
	vim.api.nvim_create_user_command("LogAddFilter", function(args)
		local regex = args.args:match("^(%S+)")
		local color = args.args:match("%s+(#%x+)$")
		M.add_filter(regex, color)
	end, { nargs = "+" })

	vim.api.nvim_create_user_command("LogRemoveFilter", function(args)
		local index = tonumber(args.args)
		M.remove_filter(index)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("LogToggleHighlight", function(args)
		local index = tonumber(args.args)
		M.toggle_highlight(index)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("LogToggleShow", function(args)
		local index = tonumber(args.args)
		M.toggle_show(index)
	end, { nargs = 1 })

	vim.api.nvim_create_user_command("LogEditFilter", function(args)
		local index, regex, color = args.args:match("^(%d+)%s+(%S+)%s*(#%x+)?$")
		index = tonumber(index)
		M.edit_filter(index, regex, color)
	end, { nargs = "+" })

	vim.api.nvim_create_user_command("LogExportFilters", function()
		M.export_filters()
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("LogImportFilters", function()
		M.import_filters()
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("LogFocusMode", function()
		toggle_focus_mode()
	end, { nargs = 0 })

	-- Autocmd to apply highlights on buffer enter
	vim.api.nvim_create_autocmd("BufEnter", {
		pattern = "*",
		callback = apply_highlights(),
	})

	-- Cleanup on exit
	vim.api.nvim_create_autocmd("VimLeave", {
		callback = clear_highlight_groups(),
	})
end

return M
