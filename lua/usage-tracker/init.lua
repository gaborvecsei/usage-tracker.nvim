local M = {}

-- We'll use this object for storing the data
local usage_data = { last_cleanup = os.time(), data = {} }
-- Use the Neovim config file path
local jsonFilePath = vim.fn.stdpath("config") .. "/usage_data.json"

-- Variable to keep track of the last activity time - needed for inactivity "detection"
local is_inactive = false
local last_activity_time = os.time()

-- Variable to keep track of the current buffer
-- Mostly needed as we cannot use the vim.api.nvim_buf_get_name and vim.api.nvim_get_current_buf functions
-- in the vim event loops (which is needed for the inactivity detection)
local current_bufnr = nil
local current_bufname = nil


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

local function get_buffer_filetype(bufnr)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
    if filetype == "" then
        return ""
    else
        return filetype
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
    local buffer_filetype = get_buffer_filetype(bufnr)

    if not usage_data.data[filepath] then
        usage_data.data[filepath] = {
            git_project_name = git_project_name,
            filetype = buffer_filetype,
            -- Will be populated with entries like this: { entry = os.time(), exit = nil , elapsed_time_sec = 0, keystrokes = 0 }
            visit_log = {}
        }
    end

    -- TODO: should we notify the user if the git project name has changed?
    usage_data.data[filepath].git_project_name = git_project_name

    -- Record an entry event
    usage_data.data[filepath].visit_log[#usage_data.data[filepath].visit_log + 1] = {
        entry = os.time(),
        exit = nil,
        keystrokes = 0,
        elapsed_time_sec = 0
    }

    is_inactive = false
    last_activity_time = os.time()
    current_bufnr = bufnr
    current_bufname = filepath

    -- Save the updated time to the JSON file
    save_timers()
end

--- Stop the timer for the current buffer
-- Happens when we leave a buffer
function M.stop_timer()
    local filepath = current_bufname

    if usage_data.data[filepath] then
        -- Record an exit event for the last entry event (as there cannot be an exit without an entry)
        -- and calculate the elapsed time
        -- Save entry and exit event only if the elapsed time between them is more than N seconds
        local visit_log = usage_data.data[filepath].visit_log
        if (#visit_log > 0) and ((os.time() - visit_log[#visit_log].entry) > vim.g.usagetracker_event_wait_period_in_sec) then
            local last_entry = visit_log[#visit_log]
            last_entry.exit = os.time()
            last_entry.elapsed_time_sec = last_entry.exit - last_entry.entry
        else
            -- Remove the last entry event
            visit_log[#visit_log] = nil
        end
    end

    -- Save the updated time to the JSON file
    save_timers()
end

-- Count the keystrokes
function M.increase_keystroke_count(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if is_inactive then
        -- As there is activity we can start the timer again
        M.start_timer(bufnr)
        is_inactive = false
    end

    if filepath == "" then
        return
    end

    if usage_data.data[filepath] then
        local visit_log = usage_data.data[filepath].visit_log
        if #visit_log > 0 then
            visit_log[#visit_log].keystrokes = visit_log[#visit_log].keystrokes + 1
        end
    end

    -- Update the last activity time
    last_activity_time = os.time()
    current_bufnr = bufnr
    current_bufname = filepath
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


local function lifetime_aggregation_of_visit_logs()
    local result = {}

    for filepath, data in pairs(usage_data.data) do
        local total_keystrokes = 0
        local total_elapsed_time_sec = 0

        for _, visit_log in ipairs(data.visit_log) do
            total_keystrokes = total_keystrokes + visit_log.keystrokes
            total_elapsed_time_sec = total_elapsed_time_sec + visit_log.elapsed_time_sec
        end

        local total_elapsed_time_min = math.floor(total_elapsed_time_sec / 60 * 100) / 100
        local total_elapsed_time_hour = math.floor(total_elapsed_time_min / 60 * 100) / 100

        local result_item = {
            name = vim.fn.fnamemodify(filepath, ":t"),
            path = filepath,
            git_project_name = data.git_project_name,
            filetype = data.filetype,
            keystrokes = total_keystrokes,
            elapsed_time_in_sec = total_elapsed_time_sec,
            elapsed_time_in_min = total_elapsed_time_min,
            elapsed_time_in_hour = total_elapsed_time_hour,
        }
        result[#result + 1] = result_item
    end

    return result
end



function M.show_usage_by_file()
    -- We would like to show up to date results, so we need to stop the timer in order to save the current result
    -- and start a new one immediately
    M.stop_timer()
    M.start_timer(current_bufnr)

    -- Prepare results
    local result = lifetime_aggregation_of_visit_logs()

    local headers = { "Filepath", "Keystrokes", "Time (min)", "Project" }
    local field_names = { "path", "keystrokes", "elapsed_time_in_min", "git_project_name" }


    -- Sort the result table based on elapsed_time_sec in descending order
    table.sort(result, function(a, b)
        return a.elapsed_time_in_min > b.elapsed_time_in_min
    end)

    -- Print the table
    print_table_format(headers, result, field_names)
end

function M.show_visit_log(filepath)
    if filepath == nil then
        filepath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    end

    if not usage_data.data[filepath] then
        print("No visit log for this file (filepath: " .. filepath .. ")")
        return
    end

    local visit_log = usage_data.data[filepath].visit_log

    local headers = { "Enter", "Exit", "Time (min)", "Keystrokes" }
    local field_names = { "enter", "exit", "elapsed_time_in_min", "keystrokes" }

    local function ts_to_date(ts)
        return os.date("%Y-%m-%d %H:%M:%S", ts)
    end

    -- Convert the visit log to a table
    local visit_log_table = {}
    for i, row in ipairs(visit_log) do
        if i < #visit_log then
            local enter = ts_to_date(row.entry)
            local exit = ts_to_date(row.exit)
            local elapsed_time_in_min = math.floor((row.exit - row.entry) / 60 * 100) / 100
            visit_log_table[#visit_log_table + 1] = {
                enter = enter,
                exit = exit,
                elapsed_time_in_min = elapsed_time_in_min,
                keystrokes = row.keystrokes
            }
        end
    end
    -- Add the last entry manually as there is no end to it. Only if we are at this file currently
    if vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()) == filepath then
        visit_log_table[#visit_log_table + 1] = {
            enter = ts_to_date(visit_log[#visit_log].entry),
            exit = "Present",
            elapsed_time_in_min = "",
            keystrokes = visit_log[#visit_log].keystrokes
        }
    end

    -- Sort the visit log based on enter time in descending order
    table.sort(visit_log_table, function(a, b)
        return a.enter > b.enter
    end)

    -- Print the table
    print_table_format(headers, visit_log_table, field_names)
end

-- Clean up the visit log by removing older than 2 week entries (where the entry is older than 2 weeks)
local function clenup_visit_log(filepath, days)
    local visit_log = usage_data.data[filepath].visit_log
    local now = os.time()
    local time_threshold_in_sec = days * 24 * 60 * 60
    local i = 1
    while i <= #visit_log do
        local row = visit_log[i]
        if (now - row.entry) > time_threshold_in_sec then
            table.remove(visit_log, i)
        else
            i = i + 1
        end
    end
end

local function handle_inactivity()
    if is_inactive then
        -- if it's already inactive then do nothing
        return
    end

    if (os.time() - last_activity_time) > (vim.g.usagetracker_inactivity_threshold_in_min * 60) then
        -- Stop the timer for the current buffer
        M.stop_timer()
        is_inactive = true
        print("usage-tracker.nvim: Inactivity detected for buffer " .. current_bufnr)
    end
end

-- data looks like this: {{name: 2022-02-30, value: 235.67}, ...}
local function draw_vertical_barchart(data)
    local max_value = 0
    for _, item in ipairs(data) do
        if item.value > max_value then
            max_value = item.value
        end
    end

    local max_value_length = string.len(tostring(max_value))
    local max_name_length = 0
    for _, item in ipairs(data) do
        if string.len(item.name) > max_name_length then
            max_name_length = string.len(item.name)
        end
    end

    local function draw_bar(value, max_value)
        local bar_length = math.floor((value / max_value) * 100)
        local bar = ""
        for i = 1, bar_length do
            bar = bar .. "#"
        end
        return bar
    end

    local function draw_value(value, max_value)
        local value_length = string.len(tostring(value))
        local value_string = ""
        for i = 1, max_value_length - value_length do
            value_string = value_string .. " "
        end
        value_string = value_string .. value
        return value_string
    end

    local function draw_name(name, max_name_length)
        local name_length = string.len(name)
        local name_string = name
        for i = 1, max_name_length - name_length do
            name_string = name_string .. " "
        end
        return name_string
    end

    local function draw_line(name, value, max_value)
        local bar = draw_bar(value, max_value)
        local value_string = draw_value(value, max_value)
        local name_string = draw_name(name, max_name_length)
        return name_string .. " | " .. bar .. " | " .. value_string
    end

    for _, item in ipairs(data) do
        print(draw_line(item.name, item.value, max_value))
    end
end

--- This function should return the daily aggregates of the usage data
--- Example for the daily aggregation:
--- {{day: 2022-01-02, time_in_sec: 2345, keystrokes: 1234}, {day: 2022-01-03, time_in_sec: 2345, keystrokes: 1234}, ...}
-- @param freq Frequency of the aggregation, possible values: H (hourly), D (daily)
---@param filetype Filetype which we would like to include, if empty then we don't filter for any filetype and everything is included
---@param project_name Project name which we would like to include, if empty then we don't filter for any project and everything is included
function M.create_time_based_usage_aggregation(filetype, project_name)
    local result = {}
    for filepath, file_data in pairs(usage_data.data) do
        if (filetype == nil or filetype == file_data.filetype) and (project_name == nil or project_name == file_data.git_project_name) then
            local visit_log = file_data.visit_log
            for _, row_data in ipairs(visit_log) do
                -- We'll use the entry time as the key for the result table
                local entry_date = os.date("%Y-%m-%d", row_data.entry)
                local exit_date = os.date("%Y-%m-%d", row_data.exit)
                if entry_date ~= exit_date then
                    print(
                        "usage-tracker.nvim: Entry and exit date are different, we'll use the entry date during the aggregation")
                end

                local time_in_sec = row_data.elapsed_time_sec
                local keystrokes = row_data.keystrokes

                if result[entry_date] == nil then
                    result[entry_date] = {
                        time_in_sec = time_in_sec,
                        keystrokes = keystrokes
                    }
                else
                    result[entry_date].time_in_sec = result[entry_date].time_in_sec + time_in_sec
                    result[entry_date].keystrokes = result[entry_date].keystrokes + keystrokes
                end
            end
        end
    end

    -- Flatten the table and then order it based on the date
    local result_table = {}
    for day_date, data in pairs(result) do
        result_table[#result_table + 1] = {
            day = day_date,
            time_in_sec = data.time_in_sec,
            time_in_min = math.floor(data.time_in_sec / 60 * 100) / 100,
            keystrokes = data.keystrokes
        }
    end

    table.sort(result_table, function(a, b)
        return a.day < b.day
    end)

    local headers = { "Day", "Time in min", "Keystrokes" }
    local field_names = { "day", "time_in_min", "keystrokes" }
    print_table_format(headers, result_table, field_names)

    -- draw barchart
    local barchart_data = {}
    for _, item in ipairs(result_table) do
        barchart_data[#barchart_data + 1] = {
            name = item.day,
            value = item.time_in_min
        }
    end
    draw_vertical_barchart(barchart_data)

end

function M.setup(opts)
    -- Plugin parameters --

    local function set_default(opt, default)
        local prefix = "usagetracker_"
        if vim.g[prefix .. opt] ~= nil then
            return
        elseif opts[opt] ~= nil then
            vim.g[prefix .. opt] = opts[opt]
        else
            vim.g[prefix .. opt] = default
        end
    end

    set_default("keep_eventlog_days", 14)
    set_default("cleanup_freq_days", 7)
    set_default("event_wait_period_in_sec", 5)
    set_default("inactivity_threshold_in_min", 5)
    set_default("inactivity_check_freq_in_sec", 1)

    -- Initialize some of the variables
    last_activity_time = os.time()
    current_bufnr = vim.api.nvim_get_current_buf()
    current_bufname = vim.api.nvim_buf_get_name(current_bufnr)

    -- Autocmd --

    vim.api.nvim_exec([[
          augroup UsageTracker
            autocmd!

            autocmd BufEnter * lua require('usage-tracker').start_timer(vim.api.nvim_get_current_buf())
            autocmd BufLeave,QuitPre * lua require('usage-tracker').stop_timer()

            autocmd TextChanged,TextChangedI * lua require('usage-tracker').increase_keystroke_count(vim.api.nvim_get_current_buf())
            autocmd CursorMoved,CursorMovedI * lua require('usage-tracker').increase_keystroke_count(vim.api.nvim_get_current_buf())
          augroup END
    ]], false)


    -- Commands --

    vim.api.nvim_command(
        "command! UsageTrackerShowFiles lua require('usage-tracker').show_usage_by_file()")
    vim.api.nvim_command(
        "command! -nargs=? UsageTrackerShowVisitLog lua require('usage-tracker').show_visit_log(<f-args>)")
    -- command to check the dayly aggregation create_time_based_usage_aggregation
    -- both parameters should be optional
    vim.api.nvim_command(
        "command! -nargs=? UsageTrackerShowDailyAggregation lua require('usage-tracker').create_time_based_usage_aggregation(<f-args>)")

    -- Load existing data --

    load_timers() -- Load the timers from the JSON file on plugin setup

    -- Cleanup --

    -- Clean up the visit log
    local now = os.time()
    if now - usage_data.last_cleanup > (vim.g.usagetracker_cleanup_freq_days * 24 * 60 * 60) then
        for filepath, _ in pairs(usage_data.data) do
            clenup_visit_log(filepath, vim.g.usagetracker_keep_eventlog_days)
        end
        usage_data.last_cleanup = now
        save_timers()
    end

    -- Check for inactivity every N seconds
    local timer = vim.loop.new_timer()
    timer:start(0, vim.g.usagetracker_inactivity_check_freq_in_sec * 1000, function()
        handle_inactivity()
    end)
end

M.setup({})

return M
