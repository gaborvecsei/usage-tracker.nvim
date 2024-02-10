local utils = require("usage-tracker.utils")

local M = {}

--- Creates a lifetime aggregation of the visit logs for each file present in the usage data
---@param usage_data table
---@return table
function M.lifetime_aggregation_of_visit_logs(usage_data)
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
        table.insert(result, result_item)
    end

    return result
end

--- Creates a daily aggregation of the visit logs
--- Example for the daily aggregation:
--- {{day: 2022-01-02, time_in_sec: 2345, keystrokes: 1234}, {day: 2022-01-03, time_in_sec: 2345, keystrokes: 1234}, ...}
---@param filetypes string[] Filetypes which we would like to include, if empty then we don't filter for any filetypes and everything is included
---@param project_name string Project name which we would like to include, if empty then we don't filter for any project and everything is included
---@return table
function M.create_daily_usage_aggregation(usage_data, filetypes, project_name)
    local result = {}
    for filepath, file_data in pairs(usage_data.data) do
        if
            (filetypes == nil or utils.list_contains(filetypes, file_data.filetype))
            and (project_name == nil or project_name == file_data.git_project_name)
        then
            local visit_log = file_data.visit_log
            for _, row_data in ipairs(visit_log) do
                -- We'll use the entry time as the key for the result table
                local entry_day_date = utils.timestamp_to_date(row_data.entry, true)
                local entry_day_date_str = os.date("%Y-%m-%d", row_data.entry)

                -- local exit_day_date = utils.timestamp_to_date(row_data.exit, true)
                local exit_day_date_str = os.date("%Y-%m-%d", row_data.exit)

                if entry_day_date_str ~= exit_day_date_str then
                    utils.verbose_print(
                        "Entry and exit date are different, we'll use the entry date during the aggregation. Entry: "
                            .. entry_day_date_str
                            .. ", exit: "
                            .. exit_day_date_str
                            .. ", filepath: "
                            .. filepath
                    )
                end

                local time_in_sec = row_data.elapsed_time_sec
                local keystrokes = row_data.keystrokes

                if result[entry_day_date_str] == nil then
                    result[entry_day_date_str] = {
                        time_in_sec = time_in_sec,
                        keystrokes = keystrokes,
                        -- Let's store the day as a date object (as the key is a string)
                        day = entry_day_date,
                    }
                else
                    result[entry_day_date_str].time_in_sec = result[entry_day_date_str].time_in_sec + time_in_sec
                    result[entry_day_date_str].keystrokes = result[entry_day_date_str].keystrokes + keystrokes
                end
            end
        end
    end

    -- It can happen that there are no data points because the user defined a filter which doesn't match any data
    -- In this case we'll return an empty table
    if utils.is_table_empty(result) then
        return {}
    end

    -- Populate the results with the missing days where there was no recorded events

    -- The biggest date is today
    local biggest_timestamp = os.time()
    -- Find the smallest date
    local smallest_timestamp = nil
    for _, day_data in pairs(result) do
        local day_timestamp = utils.date_to_timestamp(day_data.day)
        if smallest_timestamp == nil or day_timestamp < smallest_timestamp then
            smallest_timestamp = day_timestamp
        end
    end

    -- Populate the missing days
    local current_day_timestamp = smallest_timestamp
    while current_day_timestamp <= biggest_timestamp do
        local current_day_date = utils.timestamp_to_date(current_day_timestamp, true)
        local current_day_date_str = os.date("%Y-%m-%d", current_day_timestamp)

        if result[current_day_date_str] == nil then
            result[current_day_date_str] = {
                time_in_sec = 0,
                keystrokes = 0,
                day = current_day_date,
            }
        end

        current_day_timestamp = utils.increment_timestamp_by_days(current_day_timestamp, 1)
    end

    -- Flatten the table and then order it based on the date
    local result_table = {}
    for day_date_str, data in pairs(result) do
        table.insert(result_table, {
            day_str = day_date_str,
            day_timestamp = utils.date_to_timestamp(data.day),
            time_in_sec = data.time_in_sec,
            time_in_min = math.floor(data.time_in_sec / 60 * 100) / 100,
            keystrokes = data.keystrokes,
        })
    end

    table.sort(result_table, function(a, b)
        return a.day_timestamp < b.day_timestamp
    end)

    return result_table
end

--- Aggregate data by filetype in a certain date range
-- Example result: {{filetype: "lua", keystrokes: 1234, time_in_sec: 1234},
--                  {filetype: "python", keystrokes: 1234, time_in_sec: 1234},
--                  ...}
---@param usage_data table
---@param key string The basis of the aggregation. Can be "filetype" or "project" or "filepath"
---@param start_date_timestamp number
---@param end_date_timestamp number
---@return table
function M.aggregate(usage_data, key, start_date_timestamp, end_date_timestamp)
    local result = {}
    for filepath, file_data in pairs(usage_data.data) do
        local visit_log = file_data.visit_log
        for _, row_data in ipairs(visit_log) do
            if row_data.entry >= start_date_timestamp and row_data.entry <= end_date_timestamp then
                local agg_field_value = nil
                if key == "filetype" then
                    agg_field_value = file_data.filetype
                elseif key == "project" then
                    agg_field_value = file_data.git_project_name
                elseif key == "filepath" then
                    agg_field_value = filepath
                else
                    error("Unknown key: " .. key)
                    return {}
                end

                if agg_field_value == "" then
                    agg_field_value = "Unknown"
                end

                local time_in_sec = row_data.elapsed_time_sec
                local keystrokes = row_data.keystrokes

                if result[agg_field_value] == nil then
                    result[agg_field_value] = {
                        time_in_sec = time_in_sec,
                        keystrokes = keystrokes,
                    }
                else
                    result[agg_field_value].time_in_sec = result[agg_field_value].time_in_sec + time_in_sec
                    result[agg_field_value].keystrokes = result[agg_field_value].keystrokes + keystrokes
                end
            end
        end
    end

    -- Flatten the table and then order it based on the elapsed_time_sec
    local result_table = {}
    for agg_field_value, data in pairs(result) do
        table.insert(result_table, {
            name = agg_field_value,
            time_in_sec = data.time_in_sec,
            keystrokes = data.keystrokes,
        })
    end

    return result_table
end

return M
