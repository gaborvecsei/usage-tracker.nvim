local M = {}

---@param message string
function M.verbose_print(message)
    local verbose = require("usage-tracker.config").config.verbose
    if verbose and verbose > 0 then
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
---@return osdate|string
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
    ---@diagnostic disable-next-line:  param-type-mismatch
    return os.time(date)
end

--- Return a timestamp which was increased by N days
---@param timestamp number
---@param days integer
---@return number
function M.increment_timestamp_by_days(timestamp, days)
    local increased_date = os.date("*t", timestamp)
    increased_date.day = increased_date.day + days
    ---@diagnostic disable-next-line:  param-type-mismatch
    local increased_timestamp = os.time(increased_date)
    return increased_timestamp
end

---@return string
function M.get_git_project_name()
    local result = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")
    -- If the file is not in a git project, return an empty string
    if vim.v.shell_error == 0 and result ~= nil and result[1] ~= "" then
        local folder_path = vim.trim(result[1])
        return tostring(vim.fn.fnamemodify(folder_path, ":t"))
    else
        return ""
    end
end

---@return string
function M.get_git_branch()
    local result = vim.fn.systemlist("git branch --show-current 2>/dev/null")
    if vim.v.shell_error == 0 and result ~= nil and result[1] ~= "" then
        local folder_path = vim.trim(result[1])
        return tostring(vim.fn.fnamemodify(folder_path, ":t"))
    else
        return ""
    end
end

---@param bufnr integer
---@return string
function M.get_buffer_filetype(bufnr)
    local filetype = vim.api.nvim_get_option_value("ft", { buf = bufnr })
    if filetype == "" then
        return ""
    else
        return filetype
    end
end

--- Parse a date string like this 2022-06-12 to a timestamp
---@param str string The date string
---@return number|nil The timestamp
function M.convert_string_to_date(str)
    local year, month, day = str:match("(%d+)-(%d+)-(%d+)")

    -- Convert the string components to numbers
    year = tonumber(year)
    month = tonumber(month)
    day = tonumber(day)

    -- Check if the date components are valid
    if not year or not month or not day then
        print("Invalid date format. This is the acepted format: YYYY-MM-DD, like 2022-06-12")
        return nil
    end

    local parsed_date_timestamp = os.time({ year = year, month = month, day = day, hour = 0, min = 0, sec = 0 })

    -- Check if the date is valid using os.time
    if not parsed_date_timestamp then
        print("Invalid date was provided")
        return nil
    end

    return parsed_date_timestamp
end

return M
