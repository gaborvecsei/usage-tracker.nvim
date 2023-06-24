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

You can view the stats with `:ShowUsage`. Here is an example output:

```
Filepath                                        Keystrokes  Time (min)
----------------------------------------------------------------------
/usage-tracker.nvim/README.md                   2224        8
/usage-tracker.nvim/lua/usage-tracker/init.lua  591         5
/usage-tracker.nvim/lua/usage-tracker/asd       33          0
```

The data is stored in a json file called `.../usage_data.json` (`vim.fn.stdpath("config") .. "/usage_data.json"`)

## TODO

- [ ] Summary view (e.g.: folder, repo, filetype)
- [ ] UI for view the results (e.g.: popup)
- [ ] Stop timer on inactivity (e.g.: cursor was not moved for X minutes, let's not count inactivity)
- [ ] Introduce filter for the buffers, where to trigger the timer (e.g.: we don't care about file explorer buffers)
