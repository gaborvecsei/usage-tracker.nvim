local M = {}

---@param message string
function M.verbose_print(message)
    if vim.g.usagetracker_verbose > 0 then
        print("[usage-tracker.nvim]: " .. message)
    end
end

--- Check if a list contains a value
---@param list any[] A simple flat list like {1, 2, 3}
---@param value any The value to check
---@return boolean
function M.list_contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

--- Check if a table is empty as #table does not work with hash tables
---@param table table
---@return boolean
function M.is_table_empty(table)
    return next(table) == nil
end

--- Return a date object from a timestamp
---@param timestamp number
---@param keep_day_only boolean If true, the hour, minute and second will be set to 0
---@return osdate
function M.timestamp_to_date(timestamp, keep_day_only)
    local d = os.date("*t", timestamp)
    if keep_day_only then
        d.hour = 0
        d.min = 0
        d.sec = 0
    end
    return d
end

--- Convert a date object to a timestamp
---@param date osdate
---@return number Timestamp
function M.date_to_timestamp(date)
    return os.time(date)
end

--- Return a timestamp which was increased by N days
---@param timestamp number
---@param days integer
---@return number
function M.increment_timestamp_by_days(timestamp, days)
    local increased_date = os.date("*t", timestamp)
    increased_date.day = increased_date.day + days
    local increased_timestamp = os.time(increased_date)
    return increased_timestamp
end

--- Get the current git project name
-- If the file is not in a git project, return an empty string
function M.get_git_project_name()
    local result = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')
    if vim.v.shell_error == 0 and result[1] ~= '' then
        local folder_path = vim.trim(result[1])
        return vim.fn.fnamemodify(folder_path, ":t")
    else
        return ''
    end
end

--- Get the git project name
---@param bufnr integer
function M.get_buffer_filetype(bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    if filetype == "" then
        return ""
    else
        return filetype
    end
end

return M
