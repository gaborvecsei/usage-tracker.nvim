local curl = require('plenary.curl')

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

-- Send data to the restapi
local function send_data_to_restapi(filepath, entry_timestamp, exit_timestamp, keystrokes, filetype, git_project_name)
    local json = {
        entry = entry_timestamp,
        exit = exit_timestamp,
        keystrokes = keystrokes,
        filepath = filepath,
        filetype = filetype,
        projectname = git_project_name,
    }

    local telemetry_endpoint = vim.g.usagetracker_telemetry_endpoint
    if telemetry_endpoint and telemetry_endpoint ~= "" then
        local res = curl.post(telemetry_endpoint .. "/visit", {
            timeout = 1000,
            body = vim.json.encode(json),
            headers = {
                content_type = "application/json",
            },
        })
        if res.status ~= 200 then
            print("Error sending data to the restapi via the endpoint " .. telemetry_endpoint .. "/visit")
        end
        utils.verbose_print("Data sent to the restapi via the telemetry endpoint for file " .. filepath)
    end
end

--- Start the timer for the current buffer
-- Happens when we enter to a buffer
function M.start_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    if filepath == "" then
        utils.verbose_print("Filename is '' so we are not logging this buffer")
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
--- Happens when we leave a buffer
---@param use_last_activity boolean: if true, then the last activity timestamp will be used as the exit timestamp not the current time (os.time())
---Used when inactivity was detected, as we don't want to log the inactive time
---@return nil
function M.stop_timer(use_last_activity)
    use_last_activity = use_last_activity or false

    local filepath = current_buffer_filepath

    local current_time
    if use_last_activity then
        current_time = last_activity_timestamp
    else
        current_time = os.time()
    end

    if usage_data.data[filepath] then
        -- Record an exit event for the last entry event (as there cannot be an exit without an entry)
        -- and calculate the elapsed time
        -- Save entry and exit event only if the elapsed time between them is more than N seconds
        local visit_log = usage_data.data[filepath].visit_log
        if (#visit_log > 0) and ((current_time - visit_log[#visit_log].entry) > vim.g.usagetracker_event_wait_period_in_sec) then
            local last_entry = visit_log[#visit_log]
            last_entry.exit = current_time
            last_entry.elapsed_time_sec = last_entry.exit - last_entry.entry

            -- Send data to the restapi
            send_data_to_restapi(filepath,
                last_entry.entry,
                last_entry.exit,
                last_entry.keystrokes,
                usage_data.data[filepath].filetype,
                usage_data.data[filepath].git_project_name)
        else
            -- Remove the last entry event
            visit_log[#visit_log] = nil
        end
    end

    utils.verbose_print("Timer stopped for " ..
        current_buffer_filepath .. " (buffer " .. current_bufnr .. ") at" .. os.date("%c", current_time))

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

function M.show_lifetime_usage_by_file()
    -- We would like to show up to date results, so we need to stop the timer in order to save the current result
    -- and start a new one immediately
    utils.verbose_print("Stopping from lifetime usage aggregation")
    M.stop_timer(false)
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
        if i <= #visit_log then
            local enter = ts_to_date(row.entry)
            local exit = nil
            local elapsed_time_in_min = nil
            if row.exit == nil then
                exit = "Present"
                elapsed_time_in_min = math.floor((os.time() - row.entry) / 60 * 100) / 100
            else
                exit = ts_to_date(row.exit)
                elapsed_time_in_min = math.floor((row.exit - row.entry) / 60 * 100) / 100
            end
            visit_log_table[#visit_log_table + 1] = {
                enter = enter,
                exit = exit,
                elapsed_time_in_min = elapsed_time_in_min,
                keystrokes = row.keystrokes
            }
        end
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
    draw.vertical_barchart(barchart_data, 60, title, false, 42)
end

function M.show_aggregation(key, start_date_str, end_date_str)
    local valid_keys = {
        filetype = true,
        project = true,
        filepath = true
    }

    if not key then
        print("Please specify an aggregation key: filetype, project, or filepath")
        return
    end

    if not valid_keys[key] then
        print("Invalid aggregation key: " .. key .. ". Valid keys are: filetype, project, filepath")
        return
    end

    local today = os.date("%Y-%m-%d")
    local start_date_str = start_date_str or today
    local start_date_timestamp = utils.convert_string_to_date(start_date_str)

    local tomorrow = os.date("%Y-%m-%d", utils.increment_timestamp_by_days(os.time(), 1))
    local end_date_str = end_date_str or tomorrow
    local end_date_timestamp = utils.convert_string_to_date(end_date_str)

    local data = agg.aggregate(usage_data, key, start_date_timestamp, end_date_timestamp)

    if not data or next(data) == nil then
        print("No data to show - try using different filters")
        return
    end

    local barchart_data = {}
    for _, item in ipairs(data) do
        local value = math.floor(item.time_in_sec / 60 * 100) / 100
        barchart_data[#barchart_data + 1] = {
            name = item.name,
            value = value
        }
    end

    local title = "Total usage in minutes from " .. start_date_str .. " 00:00 to " .. end_date_str .. " 00:00"
    draw.vertical_barchart(barchart_data, 60, title, true, 42)
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
        utils.verbose_print("Stopping due to inactivity")
        M.stop_timer(true)
        is_inactive = true
        print("Inactivity detected for buffer " ..
            current_bufnr .. " at " .. os.date("%Y-%m-%d %H:%M:%S") .. ", last active at " .. last_activity_timestamp)
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
    set_default("inactivity_threshold_in_min", 2)
    set_default("inactivity_check_freq_in_sec", 1)
    set_default("verbose", 0)
    set_default("telemetry_endpoint", "")

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
            autocmd BufLeave,QuitPre * lua require('usage-tracker').stop_timer(false)

            autocmd TextChanged,TextChangedI * lua require('usage-tracker').activity_on_keystroke(vim.api.nvim_get_current_buf())
            autocmd CursorMoved,CursorMovedI * lua require('usage-tracker').activity_on_keystroke(vim.api.nvim_get_current_buf())
          augroup END
    ]], false)


    -- Commands --

    vim.api.nvim_create_user_command("UsageTrackerShowFilesLifetime",
        function()
            M.show_lifetime_usage_by_file()
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

    vim.api.nvim_create_user_command("UsageTrackerShowAgg",
        function(cmd_opts)
            M.show_aggregation(cmd_opts.fargs[1], cmd_opts.fargs[2] or nil, cmd_opts.fargs[3] or nil)
        end,
        { nargs = '*' })


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
    timer:start(0,
        vim.g.usagetracker_inactivity_check_freq_in_sec * 1000,
        vim.schedule_wrap(function()
            handle_inactivity()
        end)
    )

    -- Telemetry check --
    -- Tell the user that the service is not running if there is a set endpoint
    if vim.g.usagetracker_telemetry_endpoint and vim.g.usagetracker_telemetry_endpoint ~= "" then
        local success, res = pcall(function()
            return curl.get(vim.g.usagetracker_telemetry_endpoint .. "/status", {
                timeout = 1000 })
        end)
        if not success or res.status ~= 200 then
            print("UsageTracker: Telemetry service is enabled but not running: " ..
                vim.g.usagetracker_telemetry_endpoint .. "/status")
            print("UsageTracker: Turning off telemetry service...")
            vim.g.usagetracker_telemetry_endpoint = nil
        end
    end
end

return M
