# Usage-Tracker.nvim

Simple lua plugin with which you can track how much time do you spend on the individual files

## Install

Use your favourite package installer, there are no parameters at the moment. For example:

```
Plug 'gaborvecsei/usage-tracker.nvim'
```

## Usage

A timer starts when you enter a buffer and stops when you leave the buffer (or quit nvim).
Both normal and insert mode is counted.

- Commands
  - `UsageTrackerShowFiles`
  - `UsageTrackerShowProjects`

You can view the file-specific stats with `:UsageTrackerShowFiles`. Here is an example output:

```
Filepath                                             Keystrokes  Time (min)  Project
---------------------------------------------------  ----------  ----------  ------------------
/work/usage-tracker.nvim/lua/usage-tracker/init.lua  9876        69.61       usage-tracker.nvim
/work/usage-tracker.nvim/README.md                   3146        12.35       usage-tracker.nvim
/.config/nvim/init.vim                               200         1.56
/work/usage-tracker.nvim/lua/usage-tracker/asd       33          0.28        usage-tracker.nvim
```

You can view the project-specific stats with `:UsageTrackerShowProjects`. Here is an example output:

```
Project             Keystrokes  Time (min)
------------------  ----------  ----------
usage-tracker.nvim  16983       81.23
                    200         1.56
```

The data is stored in a json file called `usage_data.json` in the neovim config folder (`vim.fn.stdpath("config") .. "/usage_data.json"`)

## TODO

- [ ] Stop timer on inactivity (e.g.: cursor was not moved for X minutes, let's not count inactivity)
- [x] Aggregate by git project
- [ ] UI for view the results (e.g.: popup)
- [ ] Introduce filter for the buffers, where to trigger the timer (e.g.: we don't care about file explorer buffers)

