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
                local entry_date = os.date("%Y-%m-%d", row_data.entry)
                local exit_date = os.date("%Y-%m-%d", row_data.exit)
                if entry_date ~= exit_date then
                    utils.verbose_print(
                        "Entry and exit date are different, we'll use the entry date during the aggregation")
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

    return result_table
end

return M
