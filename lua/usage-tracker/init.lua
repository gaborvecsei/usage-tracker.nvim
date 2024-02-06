local agg = require("usage-tracker.agg")
local curl = require("plenary.curl")
local draw = require("usage-tracker.draw")
local utils = require("usage-tracker.utils")

-- Configuration to be used here and in the other files
local M = {}
M.config = require("usage-tracker.config").config

-- Global variables

-- We'll use this object for storing the data
---@type table
local usage_data = { last_cleanup = os.time(), data = {} }

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
    local file = io.open(M.config.json_file, "w")
    if file then
        file:write(encodedTimers)
        file:close()
    end
end

--- Load the timers from the JSON file
local function load_usage_data()
    local file = io.open(M.config.json_file, "r")
    if file then
        local encodedTimers = file:read("*all")
        file:close()
        usage_data = vim.json.decode(encodedTimers) or {}
    end
end

---@param filepath string
---@param entry_timestamp number
---@param exit_timestamp number
---@param keystrokes number
---@param filetype string
---@param git_project_name string
---@param git_branch string
local function send_data_to_restapi(
    filepath,
    entry_timestamp,
    exit_timestamp,
    keystrokes,
    filetype,
    git_project_name,
    git_branch
)
    if not M.config.telemetry_endpoint or M.config.telemetry_endpoint == "" then
        return
    end
    local json = {
        entry = entry_timestamp,
        exit = exit_timestamp,
        keystrokes = keystrokes,
        filepath = filepath,
        filetype = filetype,
        projectname = git_project_name,
        git_branch = git_branch,
    }

    local res = curl.post(M.config.telemetry_endpoint .. "/visit", {
        timeout = 1000,
        body = vim.json.encode(json),
        headers = {
            content_type = "application/json",
        },
    })
    if res.status ~= 200 then
        print("Error sending data to the restapi via the endpoint " .. M.config.telemetry_endpoint .. "/visit")
    end
    utils.verbose_print("Data sent to the restapi via the telemetry endpoint for file " .. filepath)
end

---@diagnostic disable-next-line: unused-function, unused-local
local function remove_data_from_telemetry_db(filepath, entry_timestamp, exit_timestamp) end

--- Start the timer for the current buffer
-- Happens when we enter to a buffer
function M.start_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)

    -- Update the globals
    is_inactive = false
    last_activity_timestamp = os.time()
    current_bufnr = bufnr
    current_buffer_filepath = filepath

    -- Do not log an "empty" buffer
    -- if filepath == "" then
    --     utils.verbose_print("Filename is '' so we are not logging this buffer")
    --     return
    -- end

    local git_project_name = utils.get_git_project_name()
    local git_branch = utils.get_git_branch()
    local buffer_filetype = utils.get_buffer_filetype(bufnr)

    if not usage_data.data[filepath] then
        usage_data.data[filepath] = {
            git_project_name = git_project_name,
            git_branch = git_branch,
            filetype = buffer_filetype,
            -- Will be populated with entries like this:
            -- { entry = os.time(),
            --   exit = nil ,
            --   elapsed_time_sec = 0,
            --   keystrokes = 0 }
            visit_log = {},
        }
    end

    -- TODO: should we notify the user if the git project name has changed?
    usage_data.data[filepath].git_project_name = git_project_name
    usage_data.data[filepath].git_branch = git_branch

    -- Record an entry event
    table.insert(usage_data.data[filepath].visit_log, {
        entry = os.time(),
        exit = nil,
        keystrokes = 0,
        elapsed_time_sec = 0,
    })

    utils.verbose_print(
        "Timer started for "
            .. current_buffer_filepath
            .. " (buffer "
            .. current_bufnr
            .. ") at "
            .. os.date("%c", os.time())
    )

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
        if (#visit_log > 0) and ((current_time - visit_log[#visit_log].entry) > M.config.event_wait_period_in_sec) then
            local last_entry = visit_log[#visit_log]
            last_entry.exit = current_time
            last_entry.elapsed_time_sec = last_entry.exit - last_entry.entry

            -- Send data to the restapi
            send_data_to_restapi(
                filepath,
                last_entry.entry,
                last_entry.exit,
                last_entry.keystrokes,
                usage_data.data[filepath].filetype,
                usage_data.data[filepath].git_project_name,
                usage_data.data[filepath].git_branch
            )
        else
            utils.verbose_print(
                "Not saving the last entry event for "
                    .. filepath
                    .. " as the elapsed time is less than "
                    .. M.config.event_wait_period_in_sec
                    .. " seconds"
            )
            -- Remove the last entry event
            visit_log[#visit_log] = nil
        end
    end

    utils.verbose_print(
        "Timer stopped for "
            .. current_buffer_filepath
            .. " (buffer "
            .. current_bufnr
            .. ") at "
            .. os.date("%c", current_time)
    )

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

    -- if filepath == "" then
    --     return
    -- end

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

---@param filepath string|nil
function M.show_visit_log(filepath)
    if filepath == nil then
        filepath = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    end

    -- This table will contain the data which we'll visualize
    local visit_log_table = {}
    -- Table attributes
    local headers = { "Filepath", "Enter", "Exit", "Time (min)", "Keystrokes" }
    local field_names = { "filepath", "enter", "exit", "elapsed_time_in_min", "keystrokes" }

    local function ts_to_date(ts)
        return os.date("%Y-%m-%d %H:%M:%S", ts)
    end

    if not usage_data.data[filepath] then
        print(
            "No visit log for this file (filepath: "
                .. filepath
                .. "). Instead showing all the visit logs from all the files."
        )
        -- Instead show all the visit logs from all the files

        for f, file_visit_logs in pairs(usage_data.data) do
            for _, visit in ipairs(file_visit_logs.visit_log) do
                local enter = ts_to_date(visit.entry)
                local exit
                local elapsed_time_in_min
                if visit.exit == nil then
                    exit = "Present"
                    elapsed_time_in_min = math.floor((os.time() - visit.entry) / 60 * 100) / 100
                else
                    exit = ts_to_date(visit.exit)
                    elapsed_time_in_min = math.floor((visit.exit - visit.entry) / 60 * 100) / 100
                end
                table.insert(visit_log_table, {
                    filepath = f,
                    enter = enter,
                    exit = exit,
                    elapsed_time_in_min = elapsed_time_in_min,
                    keystrokes = visit.keystrokes,
                })
            end
        end
    else
        local visit_log = usage_data.data[filepath].visit_log

        -- Convert the visit log to a table
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
                table.insert(visit_log_table, {
                    filepath = filepath,
                    enter = enter,
                    exit = exit,
                    elapsed_time_in_min = elapsed_time_in_min,
                    keystrokes = row.keystrokes,
                })
            end
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
        table.insert(barchart_data, {
            name = item.day_str,
            value = item.time_in_min,
        })
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

function M.show_aggregation(key, _start_date_str, _end_date_str)
    local valid_keys = {
        filetype = true,
        project = true,
        filepath = true,
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
    local start_date_str = _start_date_str or today
    local start_date_timestamp = utils.convert_string_to_date(start_date_str)

    local tomorrow = os.date("%Y-%m-%d", utils.increment_timestamp_by_days(os.time(), 1))
    local end_date_str = _end_date_str or tomorrow
    local end_date_timestamp = utils.convert_string_to_date(end_date_str)
    if not start_date_timestamp or not end_date_timestamp then
        return
    end
    local data = agg.aggregate(usage_data, key, start_date_timestamp, end_date_timestamp)

    if not data or next(data) == nil then
        print("No data to show - try using different filters")
        return
    end

    local barchart_data = {}
    for _, item in ipairs(data) do
        local value = math.floor(item.time_in_sec / 60 * 100) / 100
        table.insert(barchart_data, {
            name = item.name,
            value = value,
        })
    end

    local title = "Total usage in minutes from " .. start_date_str .. " 00:00 to " .. end_date_str .. " 00:00"
    draw.vertical_barchart(barchart_data, 60, title, true, 42)
end

--- Remove and item from the visit log based on the filepath, entry timestamp, and exit timestamp
---@param filepath string
---@param entry_timestamp number
---@param exit_timestamp number
function M.remove_entry_from_visit_log(filepath, entry_timestamp, exit_timestamp)
    -- This function can only run with an empty buffer where the filename is empty ('')
    if current_buffer_filepath ~= "" then
        print("Please run this function with an empty buffer")
        return
    end

    if not filepath or not entry_timestamp or not exit_timestamp then
        print("Please provide a filepath, entry timestamp, and exit timestamp. Something is missing here.")
        return
    end

    if type(entry_timestamp) ~= "number" then
        return
    end
    if type(exit_timestamp) ~= "number" then
        return
    end

    local removed_item = false

    if usage_data.data[filepath] then
        local visit_log = usage_data.data[filepath].visit_log
        for i, row in ipairs(visit_log) do
            print(row.entry, row.exit)
            if row.entry == entry_timestamp and row.exit == exit_timestamp then
                table.remove(visit_log, i)
                -- Update the visit_log in the usage_data table
                usage_data.data[filepath].visit_log = visit_log
                removed_item = true
                print(
                    "Removed entry from visit log for "
                        .. filepath
                        .. " with entry timestamp "
                        .. entry_timestamp
                        .. " and exit timestamp "
                        .. exit_timestamp
                )
                break
            end
        end
    else
        print("No data found for filepath: " .. filepath)
        return
    end

    if removed_item then
        save_usage_data()
    else
        print(
            "No entry found for filepath: "
                .. filepath
                .. " with entry timestamp "
                .. entry_timestamp
                .. " and exit timestamp "
                .. exit_timestamp
        )
    end
end

--- Sometimes the visit log can have bad entries where the logged time is just too much
-- This function removes them from the log based on a usage threshold
---@param logged_minute_threshold number The threshold in minutes for the logged time
function M.cleanup_log_from_bad_entries(logged_minute_threshold)
    if not logged_minute_threshold then
        print("Please provide a logged minute threshold")
        return
    end

    print("Removing entries from the local visit log...")

    local time_threshold_in_sec = logged_minute_threshold * 60
    local removed_items = 0
    for filepath, data in pairs(usage_data.data) do
        local visit_log = data.visit_log
        local i = 1
        while i <= #visit_log do
            local row = visit_log[i]
            -- if exit timestamp is not set then let's set it for now (this can happen when a timer is not stopped)
            if not row.exit then
                row.exit = os.time()
                print(
                    "Exit timestamp was not set for "
                        .. filepath
                        .. " with entry timestamp "
                        .. row.entry
                        .. " - setting it to "
                        .. row.exit
                )
            end
            local elapsed_time_in_sec = row.exit - row.entry
            if elapsed_time_in_sec > time_threshold_in_sec then
                table.remove(visit_log, i)
                removed_items = removed_items + 1
                print(
                    "Removed entry from visit log for "
                        .. filepath
                        .. " with entry timestamp "
                        .. row.entry
                        .. " and exit timestamp "
                        .. row.exit
                )
            else
                i = i + 1
            end
        end
        data.visit_log = visit_log
    end
    print("Removed " .. removed_items .. " items from the local visit log")

    local telemetry_endpoint = M.config.telemetry_endpoint
    if telemetry_endpoint and telemetry_endpoint ~= "" then
        print("Removing entries from the Telemetry DB...")
        local url = telemetry_endpoint .. "/cleanup?threshold_in_min=" .. logged_minute_threshold
        local response = curl.delete(url, { accept = "application/json", timeout = 1000 })
        if response.status == 200 then
            local data = vim.json.decode(response.body)
            if data and data.entries then
                for _, entry in ipairs(data.entries) do
                    print(
                        "Removed entry from telemetry DB for "
                            .. entry.filepath
                            .. " with entry timestamp "
                            .. entry.entry
                            .. " and exit timestamp "
                            .. entry.exit
                    )
                end
                print("Removed " .. #data.entries .. " items from the telemetry DB")
            else
                print("There is no data in the DB that could be removed based on the threshold")
            end
        else
            print("Failed to remove items from the telemetry DB")
        end
    end

    save_usage_data()
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

    if (os.time() - last_activity_timestamp) > (M.config.inactivity_threshold_in_min * 60) then
        -- Stop the timer for the current buffer
        utils.verbose_print("Stopping due to inactivity")
        M.stop_timer(true)
        is_inactive = true
        print(
            "Inactivity detected for buffer "
                .. current_bufnr
                .. " at "
                .. os.date("%Y-%m-%d %H:%M:%S")
                .. ", last active at "
                .. last_activity_timestamp
        )
    end
end

function M.setup(opts)
    require("usage-tracker.config").setup_config(opts)

    -- Initialize some of the "global" variables
    last_activity_timestamp = os.time()
    current_bufnr = vim.api.nvim_get_current_buf()
    current_buffer_filepath = vim.api.nvim_buf_get_name(current_bufnr)

    -- Load existing data --

    load_usage_data() -- Load the timers from the JSON file on plugin setup

    -- Autocmd --

    local augroup_id = vim.api.nvim_create_augroup("UsageTracker", { clear = true })

    vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup_id,
        pattern = "*",
        callback = function()
            require("usage-tracker").start_timer(vim.api.nvim_get_current_buf())
        end,
    })

    vim.api.nvim_create_autocmd({ "BufLeave", "QuitPre" }, {
        group = augroup_id,
        pattern = "*",
        callback = function()
            require("usage-tracker").stop_timer(false)
        end,
    })

    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI" }, {
        group = augroup_id,
        pattern = "*",
        callback = function()
            require("usage-tracker").activity_on_keystroke(vim.api.nvim_get_current_buf())
        end,
    })

    -- Commands --

    vim.api.nvim_create_user_command("UsageTrackerShowFilesLifetime", function()
        M.show_lifetime_usage_by_file()
    end, {})

    vim.api.nvim_create_user_command("UsageTrackerShowVisitLog", function(cmd_opts)
        M.show_visit_log(cmd_opts.fargs[1] or nil)
    end, { nargs = "?" })

    vim.api.nvim_create_user_command("UsageTrackerShowDailyAggregation", function()
        M.show_daily_stats(nil, nil)
    end, {})

    vim.api.nvim_create_user_command("UsageTrackerShowDailyAggregationByFiletypes", function(cmd_opts)
        local filetypes = cmd_opts.fargs
        if #filetypes == 0 then
            filetypes = nil
        end
        M.show_daily_stats(filetypes, nil)
    end, { nargs = "*" })

    vim.api.nvim_create_user_command("UsageTrackerShowDailyAggregationByProject", function(cmd_opts)
        M.show_daily_stats(nil, cmd_opts.fargs[1] or nil)
    end, { nargs = "?" })

    vim.api.nvim_create_user_command("UsageTrackerShowAgg", function(cmd_opts)
        M.show_aggregation(cmd_opts.fargs[1], cmd_opts.fargs[2] or nil, cmd_opts.fargs[3] or nil)
    end, {
        nargs = "*",
        complete = function(_, _)
            return { "filetype", "project", "filepath" }
        end,
    })
    vim.api.nvim_create_user_command("UsageTrackerRemoveEntry", function(cmd_opts)
        M.remove_entry_from_visit_log(cmd_opts.fargs[1], cmd_opts.fargs[2], cmd_opts.fargs[3])
    end, { nargs = "*" })
    vim.api.nvim_create_user_command("UsageTrackerCleanup", function(cmd_opts)
        M.cleanup_log_from_bad_entries(cmd_opts.fargs[1])
    end, { nargs = "?" })

    -- Cleanup --

    -- Clean up the visit log
    local now = os.time()
    if now - usage_data.last_cleanup > (M.config.cleanup_freq_days * 24 * 60 * 60) then
        for filepath, _ in pairs(usage_data.data) do
            clenup_visit_log(filepath, M.config.keep_eventlog_days)
        end
        usage_data.last_cleanup = now
        save_usage_data()
    end

    -- Check for inactivity every N seconds
    local timer = vim.loop.new_timer()
    timer:start(
        0,
        M.config.inactivity_check_freq_in_sec * 1000,
        vim.schedule_wrap(function()
            handle_inactivity()
        end)
    )

    -- Telemetry check --
    -- Tell the user that the service is not running if there is a set endpoint
    if M.config.telemetry_endpoint and M.config.telemetry_endpoint ~= "" then
        local success, res = pcall(function()
            return curl.get(M.config.telemetry_endpoint .. "/status", {
                timeout = 1000,
            })
        end)
        if not success or res.status ~= 200 then
            print(
                "UsageTracker: Telemetry service is enabled but not running: "
                    .. M.config.telemetry_endpoint
                    .. "/status"
            )
            print("UsageTracker: Turning off telemetry service...")
            M.config.telemetry_endpoint = nil
        end
    end
end

return M
