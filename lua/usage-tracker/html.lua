local M = {}

-- TODO: Test results against the neovim interface

--- Get the path of the current script
---@return string path
local function get_script_path()
    local str = debug.getinfo(2, "S").source:sub(2)
    local win = package.config:sub(1, 1) == "\\"
    local path_sep = "/"
    if win then
        str = str:gsub("/", "\\")
        path_sep = "\\"
    end
    return str:match("(.*" .. path_sep .. ")")
end

--- Read the contents of text file to a lua string
---@param file_path string path of file to be read
local function read_file(file_path)
    local file = io.open(file_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        return content
    else
        return nil, "Could not read file"
    end
end

--- (Over-)write a string to a text file
---@param file_path string file path
---@param content string string to be written to the file
local function write_file(file_path, content)
    local file = io.open(file_path, "w")
    if file then
        file:write(content)
        file:close()
    else
        error("Could not write to file" .. file_path)
    end
end

--- Append a string to a text file
---@param file_path string file path
---@param content string string to be written to the file
local function append_file(file_path, content)
    local file = io.open(file_path, "a")
    if file then
        file:write(content)
        file:close()
    else
        error("Could not append to file" .. file_path)
    end
end

--- open a browser with a specific webpage
---@param file_path string file or url to be opened with the browser
local function open_browser(file_path)
    local open_command
    if vim.fn.has("mac") == 1 then
        open_command = "open"
    elseif vim.fn.has("unix") == 1 then
        open_command = "xdg-open"
    else
        -- TODO: Windows support is not tested
        open_command = "start" -- For Windows
    end
    vim.fn.jobstart({ open_command, file_path }, { detach = true })
end

--- Copy contents from one text file to the other
---@param source string source path
---@param target string target path
local function copy_file(source, target)
    local bundle, bundle_err = read_file(source)
    if not bundle then
        error("Error reading js bundle file: " .. bundle_err)
    end
    write_file(target, bundle)
end

--- Create a html file which contains the data and links to javascript code for visualization
function M.create_html_stats()
    local json_file_path = require("usage-tracker.config").config.json_file
    local html_template_path = get_script_path() .. "../../html/analyze.html"

    local json_data, json_err = read_file(json_file_path)
    if not json_data then
        error("Error reading JSON file: " .. json_err)
    end
    copy_file(get_script_path() .. "../../html/analyze.js", vim.fn.stdpath("cache") .. "/analyze.js")

    local html_template, html_err = read_file(html_template_path)
    if not html_template then
        error("Error reading HTML template file: " .. html_err)
    end

    local html_content = html_template:gsub("{{ json_data_here }}", json_data)
    -- html_content = html_content:gsub("{{ analyzejs }}", js_functions)

    local output_file_path = vim.fn.stdpath("cache") .. "/usage-tracker.html"
    write_file(output_file_path, html_content)
    open_browser(output_file_path)
end

return M
