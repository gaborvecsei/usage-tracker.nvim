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

--- Start the timer for the current buffer
-- Happens when we enter to a buffer
function M.start_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if not usage_data[filepath] then
        usage_data[filepath] = {
            start_time = os.time(),
            elapsed_time_sec = 0
        }
    else
        usage_data[filepath].start_time = os.time()
    end
end

--- Stop the timer for the current buffer
-- Happens when we leave a buffer
function M.stop_timer(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if usage_data[filepath] then
        local elapsed_time_sec = os.time() - usage_data[filepath].start_time
        usage_data[filepath].elapsed_time_sec = usage_data[filepath].elapsed_time_sec + elapsed_time_sec
    end
    -- Save the updated time to the JSON file
    save_timers()
end

function M.show_results()
    -- We would like to show up to date results, so we need to stop the timer in order to save the current result
    -- and start a new one immediately
    local current_bufnr = vim.api.nvim_get_current_buf()
    M.stop_timer(current_bufnr)
    M.start_timer(current_bufnr)

    -- Prepare results
    local result = {}
    for filepath, timer in pairs(usage_data) do
        result[#result + 1] = {
            filepath = filepath,
            keystrokes = timer.keystrokes,
            elapsed_time_min = timer.elapsed_time_sec / 60
        }
    end

    -- Sort the result table based on elapsed_time_sec in descending order
    table.sort(result, function(a, b)
        return a.elapsed_time_min > b.elapsed_time_min
    end)


    local keystrokes_header = "Keystrokes"
    local elapsed_time_header = "Time (min)"

    -- Calculate the maximum lengths of filepath, keystrokes, and elapsed_time_sec
    local maxFilePathLen = 0
    local maxKeystrokesLen = #keystrokes_header
    local maxElapsedTimeLen = #elapsed_time_header

    for _, data in ipairs(result) do
        maxFilePathLen = math.max(maxFilePathLen, #data.filepath)
        maxKeystrokesLen = math.max(maxKeystrokesLen, #tostring(data.keystrokes or "Nan"))
        maxElapsedTimeLen = math.max(maxElapsedTimeLen, #tostring(data.elapsed_time_min or "NaN"))
    end

    -- Print the table header
    print(string.format("%-" .. maxFilePathLen .. "s  %-" .. maxKeystrokesLen .. "s  %-" .. maxElapsedTimeLen .. "s",
        "Filepath", keystrokes_header, elapsed_time_header))
    print(string.rep("-", maxFilePathLen + maxKeystrokesLen + maxElapsedTimeLen + 4))

    -- Print the sorted results
    for _, data in ipairs(result) do
        print(string.format("%-" .. maxFilePathLen .. "s  %-" .. maxKeystrokesLen .. "d  %-" .. maxElapsedTimeLen .. "d",
            data.filepath,
            data.keystrokes or "Nan",
            data.elapsed_time_min or "NaN"))
    end
end

-- Count the keystorekes
function M.increase_keystroke_count(bufnr)
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if usage_data[filepath] then
        usage_data[filepath].keystrokes = (usage_data[filepath].keystrokes or 0) + 1
    end
end

function M.setup()
    vim.api.nvim_command("autocmd BufEnter * lua require('usage-tracker').start_timer(vim.api.nvim_get_current_buf())")
    vim.api.nvim_command(
        "autocmd BufLeave,QuitPre * lua require('usage-tracker').stop_timer(vim.api.nvim_get_current_buf())")
    vim.api.nvim_command("command! ShowUsage lua require('usage-tracker').show_results()")

    -- Increase keystoreke count when cursor is moving
    vim.api.nvim_command(
        "autocmd TextChanged,TextChangedI * lua require('usage-tracker').increase_keystroke_count(vim.api.nvim_get_current_buf())")
    vim.api.nvim_command(
        "autocmd CursorMoved,TextChangedI * lua require('usage-tracker').increase_keystroke_count(vim.api.nvim_get_current_buf())")


    load_timers() -- Load the timers from the JSON file on plugin setup
end

M.setup()

return M
