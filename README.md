# Usage-Tracker.nvim

> The plugin is in ⚠️aactive development, and you can expect breaking changes in the future.

Simple lua plugin with which you can track how much time do you spend on the individual files, projects.

## Install

Use your favourite package installer, there are no parameters at the moment. For example:

```lua
Plug 'gaborvecsei/usage-tracker.nvim'
```

### Configuration

```lua
require('usage-tracker').setup({
    keep_eventlog_days = 14,
    cleanup_freq_days = 7,
    event_wait_period_in_sec = 5,
    inactivity_threshold_in_min = 5,
    inactivity_check_freq_in_sec = 5,
    verbose = 0,
    telemetry_endpoint = "" -- you'll need to start the restapi for this feature
})
```

| Variable                       | Description                                                                       | Type | Default |
| ------------------------------ | --------------------------------------------------------------------------------- | ---- | ------- |
| `keep_eventlog_days`           | How much days of data should we keep in the event log after a cleanup             | int  | 14      |
| `cleanup_freq_days`            | Frequency of the cleanup job for the event logs                                   | int  | 7       |
| `event_wait_period_in_sec`     | Event logs are only recorded if this much seconds are elapsed while in the buffer | int  | 5       |
| `inactivity_threshold_in_min`  | If the cursor is not moving for this much time, the timer will be stopped         | int  | 5       |
| `inactivity_check_freq_in_sec` | How frequently check for inactivity                                               | int  | 1       |
| `verbose`                      | Debug messages are printed if it's `>0`                                           | int  | 1       |
| `telemetry_endpoint`           | If defined data will be stored in a sqlite db via the restapi                     | str  | ""      |

(The variables are in the global space with the prefix `usagetracker_`)

## Usage

A timer starts when you enter a buffer and stops when you leave the buffer (or quit nvim).
Both normal and insert mode is counted.

There is inactivity detection, which means that if you don't have any keys pressed down (normal, insert mode) then
the timer is stopped automatically. Please see the configuration to set your personal preference.

### Commands

- `UsageTrackerShowAgg <aggregation_type> [start_date] [end_date]`
  - `aggregation_type` can be `filepath`, `project`, `filetype`
  - `start_date` and `end_date` is in format `YYYY-MM-DD`, range for the aggregation
- `UsageTrackerShowFilesLifetime`
- `UsageTrackerShowVisitLog [filepath]`
- `UsageTrackerShowDailyAggregation`
- `UsageTrackerShowDailyAggregationByFiletypes [filetypes]`
  - E.g.: `:UsageTrackerShowDailyAggregationByFiletypes lua markdown jsx`
- `UsageTrackerShowDailyAggregationByProject [project_name]`

### Telemetry (separately storing data in a DB)

Usage data saved locally (in the json file) is cleaned up after the set days,
but if you'd like to keep it longer in a separate SqliteDB, then this is why this feature exists.

You can use it for custom analysis, just make sure the endpoint is live.

#### How to enable it

```console
$ git clone https://github.com/gaborvecsei/usage-tracker.nvim.git
$ cd usage-tracker.nvim/telemetry_api
$ docker-compose up -d
```

If you'd like to use a different volume mount then change it in the `docker-compose.yml` file

Then you should define the `telemetry_endpoint="http://<HOST>:<PORT>"` (if you did not changed a thing the endpoint is `http://localhost:8000`)
parameter in the `setup({..., telemetry_endpoint="http://<HOST>:<PORT>"})`.

#### Examples

Use **`:UsageTrackerShowAgg filetype 2023-07-07 2023-07-08`**

```
Total usage in minutes from 2023-07-07 00:00 to 2023-07-08 00:00
----------------------------------------------------------------
python          | ############################################################ | 155.33
lua             | ##################################################### | 138.9
html            | ####### | 20.35
markdown        | ###### | 16.01
vim             | # | 4.01
javascriptreact |  | 0.15
```

You can view the file-specific stats with **`:UsageTrackerShowFilesLifetime`**.

```
Filepath                                             Keystrokes  Time (min)  Project
---------------------------------------------------  ----------  ----------  ------------------
/work/usage-tracker.nvim/lua/usage-tracker/init.lua  9876        69.61       usage-tracker.nvim
/work/usage-tracker.nvim/README.md                   3146        12.35       usage-tracker.nvim
/.config/nvim/init.vim                               200         1.56
```

You can view the file-specific event (entry, exit) with **`:UsageTrackerShowVisitLog [filepath]`**.
Call the function when you are at the file you are interested in without any arguments or you can provide the filename as an argument.
An event pair is only saved when more time elapsed than `event_wait_period_in_sec` seconds between the entry and the exit.
Here is an example output:

```
Enter                Exit                 Time (min)
-------------------  -------------------  ----------
2023-06-27 13:47:27  Present
2023-06-27 13:47:13  2023-06-27 13:47:17  0.06
2023-06-27 13:44:48  2023-06-27 13:47:05  2.28
```

Use **:UsageTrackerShowDailyAggregationByFiletypes lua python markdown** to get daily usage stats

```
Daily usage in minutes
----------------------
2023-07-03 | ######################################## | 166.05
2023-07-04 | ###################### | 94.16
2023-07-05 | ################################################################################ | 333.1
```

The data is stored in a json file called `usage_data.json` in the neovim config folder (`vim.fn.stdpath("config") .. "/usage_data.json"`)

## TODO

- [x] Stop timer on inactivity (e.g.: cursor was not moved for X minutes, let's not count inactivity)
- [x] Aggregate by git project
- [ ] UI for view the results (e.g.: popup)
- [ ] Introduce filter for the buffers, where to trigger the timer (e.g.: we don't care about file explorer buffers)
