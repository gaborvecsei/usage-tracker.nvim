local M = {}

--- Draws (on the message bar) a vertical barchart for the aggregated daily data
-- data looks like this: {{name: 2022-02-30, value: 235.67}, ...}
---@param data table The data should have a name and a value field
---@param max_chars integer The maximum number of characters to use for the bar
---@param title string The title of the chart
---@param sort boolean Whether to sort the data by value
---@param mnl integer The maximum number of characters to use for the name (y axis)
function M.vertical_barchart(data, max_chars, title, sort, mnl)
    max_chars = max_chars or 60
    title = title or ""
    sort = sort or false
    mnl = mnl or 30

    if sort then
        table.sort(data, function(a, b)
            return a.value > b.value
        end)
    end

    local max_value = 0
    local max_name_length = 0

    print(title .. "\n" .. string.rep("-", #title) .. "\n")

    for _, item in ipairs(data) do
        max_value = math.max(max_value, item.value)
        if #item.name > mnl then
            item.name = "..." .. string.sub(item.name, -1 * (mnl - 3))
        end
        max_name_length = math.max(max_name_length, #item.name)
    end

    for _, item in ipairs(data) do
        local bar_length = math.floor((item.value / max_value) * max_chars)
        local bar = string.rep("#", bar_length)
        local value_string = string.format("%-" .. max_chars .. "s", tostring(item.value))
        local name_string = string.format("%-" .. max_name_length .. "s", item.name)
        local line = name_string .. " | " .. bar .. " | " .. value_string
        print(line)
    end
end

--- Prints the results in a table format to the messages
-- headers and field names should be in the same order while data is a list where each item is a
-- dictionary with the keys being the field names
-- Example: {{filename = "init.lua", keystrokes = 100, elapsed_time_sec = 10}, {filename = "plugin.lua", keystrokes = 50, elapsed_time_sec = 5}
---@param headers string[]
---@param data table
---@param field_names string[]
function M.print_table_format(headers, data, field_names)
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
        local l = maxLens[field_name]
        if l > 99 then
            -- string.format only works up to 99 characters
            l = 99
        end
        headerFormat = headerFormat .. "%-" .. l .. "s  "
        separator = separator .. string.rep("-", l) .. "  "
    end

    print(string.format(headerFormat, unpack(headers)))
    print(separator)

    for _, rowData in ipairs(data) do
        local rowFormat = ""
        for _, field_name in ipairs(field_names) do
            local l = maxLens[field_name]
            if l > 99 then
                -- string.format only works up to 99 characters
                l = 99
            end
            rowFormat = rowFormat .. "%-" .. l .. "s  "
        end
        local rowValues = {}
        for i, field_name in ipairs(field_names) do
            rowValues[i] = rowData[field_name]
        end
        print(string.format(rowFormat, unpack(rowValues)))
    end
end

return M
