describe("Config module", function()
    local usage

    it("The module can be required", function()
        local your_plugin_path = "/home/konrad/nvimplugins/usage-tracker.nvim"
        package.path = package.path .. ";" .. your_plugin_path .. "/lua/?.lua"
        package.path = package.path .. ";" .. your_plugin_path .. "/lua/?/init.lua"
        -- print("########################:" .. (package.searchpath("usage-tracker", package.path) or "nothing found"))
        usage = require("usage-tracker")
        -- local status, plugin = pcall(require, "usage-tracker")
        -- assert.True(status, "The plugin should be successfully required.")
        assert.truthy(usage, "The plugin should be successfully required.")
    end)

    before_each(function()
        package.loaded["usage-tracker"] = nil
        package.loaded["usage-tracker.config"] = nil
        usage = nil
        usage = require("usage-tracker")
    end)

    it("config table is the same as in the config submodule", function()
        assert.equal(usage.config, require("usage-tracker.config").config)
    end)

    it("setup config works when only one element given", function()
        usage.setup({ verbose = 1 })
        assert.equal(1, usage.config.verbose, "given parameter is set")
        assert.equal(7, usage.config.cleanup_freq_days, "other parameters are on default values")
    end)

    it("Default config", function()
        assert.truthy(usage, "requirements are kept between tests")
        local test_config = {
            keep_eventlog_days = 4,
            cleanup_freq_days = 7,
            event_wait_period_in_sec = 5,
            inactivity_threshold_in_min = 2,
            inactivity_check_freq_in_sec = 1,
            verbose = 0,
            telemetry_endpoint = "",
            json_file = vim.fn.stdpath("config") .. "/usage_data.json",
        }
        assert.are.same(test_config, usage.config, "configuration is as expected")
    end)
end)
