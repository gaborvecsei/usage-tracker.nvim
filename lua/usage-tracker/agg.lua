local utils = require("usage-tracker.utils")

local M = {}


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
        result[#result + 1] = result_item
    end

    return result
end

--- This function which aggregates usage data day by day
--- Example for the daily aggregation:
--- {{day: 2022-01-02, time_in_sec: 2345, keystrokes: 1234}, {day: 2022-01-03, time_in_sec: 2345, keystrokes: 1234}, ...}
---@param filetypes table Filetypes which we would like to include, if empty then we don't filter for any filetypes and everything is included
---@param project_name string Project name which we would like to include, if empty then we don't filter for any project and everything is included
function M.create_daily_usage_aggregation(usage_data, filetypes, project_name)
    local result = {}
    for _, file_data in pairs(usage_data.data) do
        if (filetypes == nil or utils.list_contains(filetypes, file_data.filetype)) and (project_name == nil or project_name == file_data.git_project_name) then
            local visit_log = file_data.visit_log
            for _, row_data in ipairs(visit_log) do
                -- We'll use the entry time as the key for the result table
                local entry_day_date = utils.timestamp_to_date(row_data.entry, true)
                local entry_day_date_str = os.date("%Y-%m-%d", row_data.entry)

                local exit_day_date = utils.timestamp_to_date(row_data.exit, true)
                local exit_day_date_str = os.date("%Y-%m-%d", row_data.exit)

                if entry_day_date_str ~= exit_day_date_str then
                    utils.verbose_print(
                        "Entry and exit date are different, we'll use the entry date during the aggregation")
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
        result_table[#result_table + 1] = {
            day_str = day_date_str,
            day_timestamp = utils.date_to_timestamp(data.day),
            time_in_sec = data.time_in_sec,
            time_in_min = math.floor(data.time_in_sec / 60 * 100) / 100,
            keystrokes = data.keystrokes
        }
    end

    table.sort(result_table, function(a, b)
        return a.day_timestamp < b.day_timestamp
    end)

    return result_table
end

return M
