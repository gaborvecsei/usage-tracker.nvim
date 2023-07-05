local M = {}

function M.verbose_print(message)
    if vim.g.usagetracker_verbose > 0 then
        print("[usage-tracker.nvim]: " .. message)
    end
end

function M.list_contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

function M.timestamp_to_date(timestamp, keep_day_only)
    local d = os.date("*t", timestamp)
    if keep_day_only then
        d.hour = 0
        d.min = 0
        d.sec = 0
    end
    return d
end

function M.date_to_timestamp(date)
    return os.time(date)
end

function M.increment_timestamp_by_days(timestamp, days)
    local increased_date = os.date("*t", timestamp)
    increased_date.day = increased_date.day + days
    local increased_timestamp = os.time(increased_date)
    return increased_timestamp
end

-- local a = os.time()
-- print(a, type(a))
-- local b = M.timestamp_to_date(a, true)
-- print(vim.inspect(b), type(b))
-- local c = os.date("%Y-%m-%d", a)
-- print(c, type(c))
--
-- local d = M.increment_date_by_days(a, 30)
-- print(vim.inspect(d), type(d))

-- Increase the day by 30 days
-- local increased_date = os.date("*t", a)
-- increased_date.day = increased_date.day + 30
-- local increased_timestamp = os.time(increased_date)
-- local e = M.timestamp_to_date(increased_timestamp, false)
-- print(vim.inspect(e), type(e))


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

function M.get_buffer_filetype(bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    if filetype == "" then
        return ""
    else
        return filetype
    end
end

return M
