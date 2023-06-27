# Usage-Tracker.nvim

> The plugin is [WIP], and you can expect breaking changes in the future.

> All contributions are welcome!

Simple lua plugin with which you can track how much time do you spend on the individual files, projects.
The tool also records entry and exit entries for the files, so later we can visualize this actiivty.

## Install

Use your favourite package installer, there are no parameters at the moment. For example:

```
Plug 'gaborvecsei/usage-tracker.nvim'
```

And then

```
-- default parameters
require('usage-tracker').setup()

-- or if you would like to modify the parameters:
require('usage-tracker').setup({...})
```

## Usage

A timer starts when you enter a buffer and stops when you leave the buffer (or quit nvim).
Both normal and insert mode is counted.

### Parameters

| Variable                                | Description                                                                       | Type | Default |
|-----------------------------------------|-----------------------------------------------------------------------------------|------|---------|
| `usagetracker_keep_eventlog_days`       | How much days of data should we keep in the event log after a cleanup             | int  | 14      |
| `usagetracker_cleanup_freq_days`        | Frequency of the cleanup job for the event logs                                   | int  | 7       |
| `usagetracker_event_wait_period_in_sec` | Event logs are only recorded if this much seconds are elapsed while in the buffer | int  | 5       |

### Commands

- `UsageTrackerShowFiles`
- `UsageTrackerShowProjects`
- `UsageTrackerShowVisitLog`

#### Examples

You can view the file-specific stats with **`:UsageTrackerShowFiles`**. Here is an example output:

```
Filepath                                             Keystrokes  Time (min)  Project
---------------------------------------------------  ----------  ----------  ------------------
/work/usage-tracker.nvim/lua/usage-tracker/init.lua  9876        69.61       usage-tracker.nvim
/work/usage-tracker.nvim/README.md                   3146        12.35       usage-tracker.nvim
/.config/nvim/init.vim                               200         1.56
/work/usage-tracker.nvim/lua/usage-tracker/asd       33          0.28        usage-tracker.nvim
```

You can view the project-specific stats with **`:UsageTrackerShowProjects`**. Here is an example output:

```
Project             Keystrokes  Time (min)
------------------  ----------  ----------
usage-tracker.nvim  16983       81.23
                    200         1.56
```

You can view the file-specific event (entry, exit) with **`:UsageTrackerShowVisitLog`**.
Call the function when you are at the file you are interested in.
An event pair is only saved when more time elapsed than 2 seconds between the entry and the exit.
Here is an example output:

```
Enter                Exit                 Time (min)
-------------------  -------------------  ----------
2023-06-27 13:47:27  Present                        
2023-06-27 13:47:13  2023-06-27 13:47:17  0.06      
2023-06-27 13:44:48  2023-06-27 13:47:05  2.28      
```

The data is stored in a json file called `usage_data.json` in the neovim config folder (`vim.fn.stdpath("config") .. "/usage_data.json"`)

## TODO

- [ ] Stop timer on inactivity (e.g.: cursor was not moved for X minutes, let's not count inactivity)
- [x] Aggregate by git project
- [ ] UI for view the results (e.g.: popup)
- [ ] Introduce filter for the buffers, where to trigger the timer (e.g.: we don't care about file explorer buffers)
