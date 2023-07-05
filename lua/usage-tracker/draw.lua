local M = {}

-- data looks like this: {{name: 2022-02-30, value: 235.67}, ...}
function M.vertical_barchart(data, max_chars, title)
    max_chars = max_chars or 80
    title = title or ""

    local max_value = 0
    local max_name_length = 0

    print(title .. "\n" .. string.rep("-", #title) .. "\n")

    for _, item in ipairs(data) do
        max_value = math.max(max_value, item.value)
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

return M
