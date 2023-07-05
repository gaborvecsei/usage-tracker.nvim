local utils = require("usage-tracker.utils")
local draw = require("usage-tracker.draw")
local agg = require("usage-tracker.agg")

local M = {}

-- We'll use this object for storing the data
---@type table
local usage_data = { last_cleanup = os.time(), data = {} }

-- Use the Neovim config file path
---@type string
local jsonFilePath = vim.fn.stdpath("config") .. "/usage_data.json"

-- Variable to keep track of the last activity time - needed for inactivity "detection"
---@type boolean
local is_inactive = false

---@type number
local last_activity_timestamp = os.time()

-- Variable to keep track of the current buffer
-- Mostly needed as we cannot use the vim.api.nvim_buf_get_name and vim.api.nvim_get_current_buf functions
-- in the vim event loops (which is needed for the inactivity detection)
---@type number
local current_bufnr = nil
---@type string
local current_buffer_filepath = nil


--- Save the timers to the JSON file
local function save_usage_data()
    local encodedTimers = vim.json.encode(usage_data)
    local file = io.open(jsonFilePath, "w")
    if file then
        file:write(encodedTimers)
        file:close()
    end
end

--- Load the timers from the JSON file
local function load_usage_data()
    local file = io.open(jsonFilePath, "r")
    if file then
        local encodedTimers = file:read("*all")
        file:close()
        usage_data = vim.json.decode(encodedTimers)
    end
end

--- Start the timer for the current buffer
-- Happens when we enter to a buffer
function M.start_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if filepath == "" then
        return
    end

    local git_project_name = utils.get_git_project_name()
    local buffer_filetype = utils.get_buffer_filetype(bufnr)

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
    last_activity_timestamp = os.time()
    current_bufnr = bufnr
    current_buffer_filepath = filepath

    utils.verbose_print("Timer started for " ..
        current_buffer_filepath .. " (buffer " .. current_bufnr .. ") at" .. os.date("%c", os.time()))

    -- Save the updated time to the JSON file
    save_usage_data()
end

--- Stop the timer for the current buffer
-- Happens when we leave a buffer
function M.stop_timer()
    local filepath = current_buffer_filepath

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

    utils.verbose_print("Timer stopped for " ..
        current_buffer_filepath .. " (buffer " .. current_bufnr .. ") at" .. os.date("%c", os.time()))

    -- Save the updated time to the JSON file
    save_usage_data()
end

-- Count the keystrokes
function M.activity_on_keystroke(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if is_inactive then
        -- As there is activity we can start the timer again
        M.start_timer(bufnr)
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
    last_activity_timestamp = os.time()
    current_bufnr = bufnr
    current_buffer_filepath = filepath
end

function M.show_usage_by_file()
    -- We would like to show up to date results, so we need to stop the timer in order to save the current result
    -- and start a new one immediately
    M.stop_timer()
    M.start_timer(current_bufnr)

    -- Prepare results
    local result = agg.lifetime_aggregation_of_visit_logs(usage_data)

    local headers = { "Filepath", "Keystrokes", "Time (min)", "Project", "Filetype" }
    local field_names = { "path", "keystrokes", "elapsed_time_in_min", "git_project_name", "filetype" }


    -- Sort the result table based on elapsed_time_sec in descending order
    table.sort(result, function(a, b)
        return a.elapsed_time_in_min > b.elapsed_time_in_min
    end)

    -- Print the table
    draw.print_table_format(headers, result, field_names)
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
    draw.print_table_format(headers, visit_log_table, field_names)
end

function M.show_daily_stats(filetypes, project_name)
    local data = agg.create_daily_usage_aggregation(usage_data, filetypes, project_name)
    if #data == 0 then
        print("No data to show - try to use different filters")
        return
    end

    local barchart_data = {}
    for _, item in ipairs(data) do
        barchart_data[#barchart_data + 1] = {
            name = item.day_str,
            value = item.time_in_min
        }
    end

    local title = "Daily usage in minutes"
    if project_name ~= nil then
        title = title .. " for project " .. project_name
    end
    if filetypes ~= nil then
        title = title .. " for filetypes " .. table.concat(filetypes, ", ")
    end
    draw.vertical_barchart(barchart_data, 80, title)
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

    if (os.time() - last_activity_timestamp) > (vim.g.usagetracker_inactivity_threshold_in_min * 60) then
        -- Stop the timer for the current buffer
        M.stop_timer()
        is_inactive = true
        utils.verbose_print("Inactivity detected for buffer " ..
            current_bufnr .. " at " .. os.date("%Y-%m-%d %H:%M:%S"))
    end
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
    set_default("verbose", 1)

    -- Initialize some of the "global" variables
    last_activity_timestamp = os.time()
    current_bufnr = vim.api.nvim_get_current_buf()
    current_buffer_filepath = vim.api.nvim_buf_get_name(current_bufnr)

    -- Load existing data --

    load_usage_data() -- Load the timers from the JSON file on plugin setup

    -- Autocmd --

    vim.api.nvim_exec([[
          augroup UsageTracker
            autocmd!

            autocmd BufEnter * lua require('usage-tracker').start_timer(vim.api.nvim_get_current_buf())
            autocmd BufLeave,QuitPre * lua require('usage-tracker').stop_timer()

            autocmd TextChanged,TextChangedI * lua require('usage-tracker').activity_on_keystroke(vim.api.nvim_get_current_buf())
            autocmd CursorMoved,CursorMovedI * lua require('usage-tracker').activity_on_keystroke(vim.api.nvim_get_current_buf())
          augroup END
    ]], false)


    -- Commands --

    vim.api.nvim_create_user_command("UsageTrackerShowFiles",
        function()
            M.show_usage_by_file()
        end,
        {})

    vim.api.nvim_create_user_command("UsageTrackerShowVisitLog",
        function(cmd_opts)
            M.show_visit_log(cmd_opts.fargs[1] or nil)
        end,
        { nargs = '?' })

    vim.api.nvim_create_user_command("UsageTrackerShowDailyAggregation",
        function()
            M.show_daily_stats(nil, nil)
        end,
        {})

    vim.api.nvim_create_user_command("UsageTrackerShowDailyAggregationByFiletypes",
        function(cmd_opts)
            local filetypes = cmd_opts.fargs
            if #filetypes == 0 then
                filetypes = nil
            end
            M.show_daily_stats(filetypes, nil)
        end,
        { nargs = '*' })

    vim.api.nvim_create_user_command("UsageTrackerShowDailyAggregationByProject",
        function(cmd_opts)
            M.show_daily_stats(nil, cmd_opts.fargs[1] or nil)
        end,
        { nargs = '?' })


    -- Cleanup --

    -- Clean up the visit log
    local now = os.time()
    if now - usage_data.last_cleanup > (vim.g.usagetracker_cleanup_freq_days * 24 * 60 * 60) then
        for filepath, _ in pairs(usage_data.data) do
            clenup_visit_log(filepath, vim.g.usagetracker_keep_eventlog_days)
        end
        usage_data.last_cleanup = now
        save_usage_data()
    end

    -- Check for inactivity every N seconds
    local timer = vim.loop.new_timer()
    timer:start(0, vim.g.usagetracker_inactivity_check_freq_in_sec * 1000, function()
        handle_inactivity()
    end)
end

M.setup({
    keep_eventlog_days = 14,
    cleanup_freq_days = 7,
    event_wait_period_in_sec = 5,
    inactivity_threshold_in_min = 5,
    inactivity_check_freq_in_sec = 1,
    verbose = 0
})

return M
