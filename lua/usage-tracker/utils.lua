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
