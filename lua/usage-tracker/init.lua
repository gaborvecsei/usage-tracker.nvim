local M = {}

-- We'll use this object for storing the data
local usage_data = {}
-- Use the Neovim config file path
local jsonFilePath = vim.fn.stdpath("config") .. "/usage_data.json"


--- Save the timers to the JSON file
local function save_timers()
    local encodedTimers = vim.json.encode(usage_data)
    local file = io.open(jsonFilePath, "w")
    if file then
        file:write(encodedTimers)
        file:close()
    end
end

--- Load the timers from the JSON file
local function load_timers()
    local file = io.open(jsonFilePath, "r")
    if file then
        local encodedTimers = file:read("*all")
        file:close()
        usage_data = vim.json.decode(encodedTimers)
    end
end


--- Get the current git project name
-- If the file is not in a git project, return an empty string
local function get_git_project_name()
    local result = vim.fn.systemlist('git rev-parse --show-toplevel 2>/dev/null')
    if vim.v.shell_error == 0 and result[1] ~= '' then
        local folder_path = vim.trim(result[1])
        return vim.fn.fnamemodify(folder_path, ":t")
    else
        return ''
    end
end


--- Start the timer for the current buffer
-- Happens when we enter to a buffer
function M.start_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if filepath == "" then
        return
    end

    local git_project_name = get_git_project_name()

    if not usage_data[filepath] then
        usage_data[filepath] = {
            git_project_name = git_project_name,
            start_time = os.time(),
            elapsed_time_sec = 0,
            keystrokes = 0,
            -- Will be populated with entries like this: { entry = os.time(), exit = nil }
            visit_log = {}
        }
    end

    usage_data[filepath].start_time = os.time()
    -- TODO: should we notify the user if the git project name has changed?
    usage_data[filepath].git_project_name = git_project_name

    -- Record an entry event
    usage_data[filepath].visit_log[#usage_data[filepath].visit_log + 1] = { entry = os.time(), exit = nil }

    -- Save the updated time to the JSON file
    save_timers()
end

--- Stop the timer for the current buffer
-- Happens when we leave a buffer
function M.stop_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if usage_data[filepath] then
        -- Calculate the time spen with the file
        local elapsed_time_sec = os.time() - usage_data[filepath].start_time
        usage_data[filepath].elapsed_time_sec = usage_data[filepath].elapsed_time_sec + elapsed_time_sec

        -- Record an exit event for the last entry event (as there cannot be an exit without an entry)
        -- Save entry and exit event only if the elapsed time between them is more than 2 seconds
        if #usage_data[filepath].visit_log > 0 and os.time() - usage_data[filepath].visit_log[#usage_data[filepath].visit_log].entry > 2 then
            usage_data[filepath].visit_log[#usage_data[filepath].visit_log].exit = os.time()
        else
            -- Otherwise, remove the last entry event
            usage_data[filepath].visit_log[#usage_data[filepath].visit_log] = nil
        end
    end

    -- Save the updated time to the JSON file
    save_timers()
end

-- Count the keystrokes
function M.increase_keystroke_count(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if filepath == "" then
        return
    end

    if usage_data[filepath] then
        usage_data[filepath].keystrokes = (usage_data[filepath].keystrokes or 0) + 1
    end
end

--- Prints the results in a table format to the messages
-- headers and field names should be in the same order while data is a list where each item is a
-- dictionary with the keys being the field names
-- Example: {{filename = "init.lua", keystrokes = 100, elapsed_time_sec = 10}, {filename = "plugin.lua", keystrokes = 50, elapsed_time_sec = 5}
local function print_table_format(headers, data, field_names)
    -- Calculate the maximum length needed for each column
    local maxLens = {}
    for i, header in ipairs(headers) do
        local field_name = field_names[i]
        maxLens[field_name] = #header
    end
    for _, rowData in ipairs(data) do
        for _, field_name in ipairs(field_names) do
            maxLens[field_name] = math.max(maxLens[field_name], #tostring(rowData[field_name]))
        end
    end

    -- Print the table header
    local headerFormat = ""
    local separator = ""
    for _, field_name in ipairs(field_names) do
        headerFormat = headerFormat .. "%-" .. maxLens[field_name] .. "s  "
        separator = separator .. string.rep("-", maxLens[field_name]) .. "  "
    end

    print(string.format(headerFormat, unpack(headers)))
    print(separator)

    for _, rowData in ipairs(data) do
        local rowFormat = ""
        for _, field_name in ipairs(field_names) do
            rowFormat = rowFormat .. "%-" .. maxLens[field_name] .. "s  "
        end
        local rowValues = {}
        for i, field_name in ipairs(field_names) do
            rowValues[i] = rowData[field_name]
        end
        print(string.format(rowFormat, unpack(rowValues)))
    end
end



function M.show_results(aggregate_by_git_project)
    -- We would like to show up to date results, so we need to stop the timer in order to save the current result
    -- and start a new one immediately
    local current_bufnr = vim.api.nvim_get_current_buf()
    M.stop_timer(current_bufnr)
    M.start_timer(current_bufnr)

    -- Prepare results
    local result = {}
    for filepath, timer in pairs(usage_data) do
        result[#result + 1] = {
            filepath = filepath or '',
            keystrokes = timer.keystrokes or 0,
            elapsed_time_min = math.floor(timer.elapsed_time_sec / 60 * 100) / 100,
            git_project_name = timer.git_project_name or ''
        }
    end

    if not aggregate_by_git_project then
        local headers = { "Filepath", "Keystrokes", "Time (min)", "Project" }
        local field_names = { "filepath", "keystrokes", "elapsed_time_min", "git_project_name" }


        -- Sort the result table based on elapsed_time_sec in descending order
        table.sort(result, function(a, b)
            return a.elapsed_time_min > b.elapsed_time_min
        end)

        -- Print the table
        print_table_format(headers, result, field_names)
    else
        local headers = { "Project", "Keystrokes", "Time (min)" }
        local field_names = { "git_project_name", "keystrokes", "elapsed_time_min" }

        -- Aggregate the results by git project name
        local aggregated_result = {}
        for _, row in ipairs(result) do
            local git_project_name = row.git_project_name
            if not aggregated_result[git_project_name] then
                aggregated_result[git_project_name] = {
                    keystrokes = 0,
                    elapsed_time_min = 0
                }
            end
            aggregated_result[git_project_name].keystrokes = aggregated_result[git_project_name].keystrokes +
                row.keystrokes
            aggregated_result[git_project_name].elapsed_time_min = aggregated_result[git_project_name].elapsed_time_min +
                row.elapsed_time_min
        end

        -- Convert the aggregated result to a table
        local aggregated_result_table = {}
        for git_project_name, row in pairs(aggregated_result) do
            aggregated_result_table[#aggregated_result_table + 1] = {
                git_project_name = git_project_name,
                keystrokes = row.keystrokes,
                elapsed_time_min = row.elapsed_time_min
            }
        end

        -- Sort the result table based on elapsed_time_sec in descending order
        table.sort(aggregated_result_table, function(a, b)
            return a.elapsed_time_min > b.elapsed_time_min
        end)

        -- Print the table
        print_table_format(headers, aggregated_result_table, field_names)
    end
end

function M.show_visit_log(filepath)
    local visit_log = usage_data[filepath].visit_log
    local headers = { "Enter", "Exit", "Time (min)" }
    local field_names = { "enter", "exit", "elapsed_time_min" }

    local function ts_to_date(ts)
        return os.date("%Y-%m-%d %H:%M:%S", ts)
    end

    -- Convert the visit log to a table
    local visit_log_table = {}
    for i, row in ipairs(visit_log) do
        if i < #visit_log then
            local enter = ts_to_date(row.entry)
            local exit = ts_to_date(row.exit)
            local elapsed_time_min = math.floor((row.exit - row.entry) / 60 * 100) / 100
            visit_log_table[#visit_log_table + 1] = {
                enter = enter,
                exit = exit,
                elapsed_time_min = elapsed_time_min
            }
        end
    end
    visit_log_table[#visit_log_table + 1] = {
        enter = ts_to_date(visit_log[#visit_log].entry),
        exit = "Present",
        elapsed_time_min = ""
    }

    -- Sort the visit log based on enter time in descending order
    table.sort(visit_log_table, function(a, b)
        return a.enter > b.enter
    end)


    -- Print the table
    print_table_format(headers, visit_log_table, field_names)
end

function M.setup()
    -- Autocmd --

    vim.api.nvim_exec([[
          augroup UsageTracker
            autocmd!

            autocmd BufEnter * lua require('usage-tracker').start_timer(vim.api.nvim_get_current_buf())
            autocmd BufLeave,QuitPre * lua require('usage-tracker').stop_timer(vim.api.nvim_get_current_buf())

            autocmd TextChanged,TextChangedI * lua require('usage-tracker').increase_keystroke_count(vim.api.nvim_get_current_buf())
            autocmd CursorMoved,TextChangedI * lua require('usage-tracker').increase_keystroke_count(vim.api.nvim_get_current_buf())
          augroup END
    ]], false)


    -- Commands --

    vim.api.nvim_command(
        "command! UsageTrackerShowFiles lua require('usage-tracker').show_results(false)")
    vim.api.nvim_command(
        "command! UsageTrackerShowProjects lua require('usage-tracker').show_results(true)")
    vim.api.nvim_command(
        "command! UsageTrackerShowVisitLog lua require('usage-tracker').show_visit_log(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))")


    load_timers() -- Load the timers from the JSON file on plugin setup
end

M.setup()

return M
