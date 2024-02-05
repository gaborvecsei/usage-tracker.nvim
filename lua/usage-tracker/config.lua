local M = {}

---@class Config
---@field keep_eventlog_days? integer
---@field cleanup_freq_days integer
---@field event_wait_period_in_sec integer
---@field inactivity_threshold_in_min integer
---@field inactivity_check_freq_in_sec integer
---@field verbose integer
---@field telemetry_endpoint string

---@type Config
M.config = {
    keep_eventlog_days = 4,
    cleanup_freq_days = 7,
    event_wait_period_in_sec = 5,
    inactivity_threshold_in_min = 2,
    inactivity_check_freq_in_sec = 1,
    verbose = 0,
    telemetry_endpoint = "",
}

function M.setup_config(opts)
    for opt, _ in pairs(M.config) do
        if opts[opt] ~= nil then
            M.config[opt] = opts[opt]
        end
    end
end

return M
