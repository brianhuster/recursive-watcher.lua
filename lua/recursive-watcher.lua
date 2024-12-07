---@brief Non-native file system watcher.
---
---This is made because |luv| doesn't support recursive directory watching in other OSes than Windows and OSX
---
---This module has only been tested on Linux. For Windows and OSX, it is recommended to use |uv_fs_event_t| with flag { recursive = true }
---
---To use this module, do:
---```lua
---local M = require('recursive-watcher')
---```

local M = {}

local uv = vim and (vim.uv or vim.loop) or require('luv')

---@class Watcher
---@field directory string
---@field watcher uv_fs_event_t
---@field children Watcher[]
---To call this class, do:
---```lua
---Watcher = require('recursive-watcher').Watcher
---```
local Watcher = {}
Watcher.__index = Watcher

--- List all first level subdirectories of a directory.
--- @param dir string
--- @return table<string>
local function get_subdirs(dir)
	local subdirs = {}
	local fd = uv.fs_scandir(dir)
	if not fd then
		return subdirs
	end
	while true do
		local name, t = uv.fs_scandir_next(fd)
		if not name then
			break
		end
		if t == "directory" then
			table.insert(subdirs, dir .. "/" .. name)
		end
	end
	return subdirs
end

---Create a new Watcher for a directory.
---@param directory string
---@return Watcher
function Watcher:new(directory)
	local o = {}
	setmetatable(o, self)
	o.__index = o
	o.directory = directory
	o.watcher = uv.new_fs_event()
	o.children = {}

	return o
end

---Start watching a directory and its subdirectories.
---@param callback function(filename: string, events: { change: boolean, rename: boolean })
function Watcher:start(callback)
	for _, subdir in ipairs(get_subdirs(self.directory)) do
		if subdir ~= ".git" then
			local fswatcher = Watcher:new(subdir)
			table.insert(self.children, fswatcher)
			fswatcher:start(callback)
		end
	end
	self.watcher:start(self.directory, { recursive = false }, function(err, filename, events)
		if err then
			print("Error: ", err)
			return
		end

		if events.rename then
			--- Check if the directory still exists
			if not uv.fs_stat(self.directory) or uv.fs_stat(self.directory).type ~= "directory" then
				self.watcher:close()
				self = nil
				return
			end

			--- Check if a directory is created
			local path = filename and filename ~= ".git" and vim.fs.joinpath(self.directory, filename)
			local filestat = path and uv.fs_stat(path)
			if filestat and filestat.type == "directory" then
				local fswatcher = Watcher:new(path)
				table.insert(self.children, fswatcher)
				fswatcher:start(callback)
			end
		end
		callback(filename, events)
	end)
end

---Close the watcher and all its children.
function Watcher:close()
	self.watcher:close()
	for _, child in ipairs(self.children) do
		child:close()
	end
end

M.Watcher = Watcher
return M
