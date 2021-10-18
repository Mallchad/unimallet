--[[
   GPL3 License
   Copyright (c) 2021 Mallchad
   This source provides the right to be freely used in any form,
   so long as modified variations remain available publically, or open request.
   Modified versions must be marked as such.
   The source comes with no warranty of any kind.
]]--

local aux = {}
local _protected = {}

-- 'DEBUG_IGNORE' only needs to be set to be considered true
debug_ignore = os.getenv("DEBUG_IGNORE") or nil

-- Helper functions

--- Temporary Logging facilities that will error if 'debug_ignore' is false
-- This value is considered true if enviornment variable 'DEBUG_IGNORE'
-- has been set
function TLOG(...)
   assert(debug_ignore, "Debugging is disabled, you should delete this temporary line")
   _protected.print("TLOG:",...)
end

function safe_assert(condition, message)
   message = message or "An undocumented error has occured"
   if condition == false and debug_ignore == nil then
      _protected.error("[safe_assert] "..message)
   elseif condition == false then
      _protected.print("[safe_assert] (supressed): "..message)
   end
end

function safe_error(message)
   message = message or "An undocumented error has occured"
   _protected.assert(debug_ignore, "[safe_error] "..message)
   _protected.print("[safe_error] (supressed): "..message)
end

-- Produce a proxy table that is a read-only version of a table
function const(original_table)
   return setmetatable({}, {
         __index = original_table,
         -- Table updates
         __newindex = function(table, key, value)
            safe_error("Attempt to modify read-only table")
         end,
         __metatable = false
   });
end

-- Sematic alias of 'const'
function lock(original_table)
   return const(original_table)
end

-- Overwrite and deprecreate some standard library functionality
function poision_stdlib(global_table)
   _protected.print     = global_table.print
   _protected.error     = global_table.error
   _protected.assert    = global_table.assert
   _protected.os        = {}
   _protected.os.execute = global_table.os.execute
   global_table.os.execute = function()
      safe_error("'os.execute' has been disabled, please use the 'safe_execute' instead")
   end

   safe_assert(global_table ~= nil, "global_table should not be nil, this is likely a mistake")

   for k_overriden, value in pairs(_protected) do
      if _G[k_overriden] ~= nil and type(value) == "function" then
         _G[k_overriden] =
            function()
               safe_error(k_overriden..
                          " has been disabled, please use the replacement instead")
            end
      end
   end

   _protected = lock(_protected)
end
-- Call now since we care about maintaing it in this file too.
poision_stdlib(_G)

--- Join multiple strings in one command
-- Primarily meant for merging multiple varaiadic string arguments
function string.concat(str, ...)
   local concat_targets = {...}
   local tmp = str
   for _, x_str in pairs(concat_targets) do
      tmp = tmp..x_str
   end
   return tmp
end

--- Join multiple path strings in one command
-- Primarily meant for cleaning up syntax for path construction
function string.construct_path(str, ...)
   local concat_targets = {...}
   local tmp = str
   for _, x_str in pairs(concat_targets) do

      local first_char = x_str:sub(1, 1)
      safe_assert(first_char ~= "/", "Attempted to construct a path with a leading slash, implies root, this is likely a mistake")
      if first_char == "/" then
         tmp = tmp..x_str
      else
         tmp = tmp.."/"..x_str
      end
   end
   return tmp
end

--- Join arguments into one long whitespace seperated shell command
-- The primary purpose is a syntactically cleaner
function build_command(str, ...)
   local concat_targets = {...}
   local tmp = str

   for _, x_str in pairs(concat_targets) do
      tmp = tmp.." "..x_str
   end
   return tmp
end

--- Wrap a string in speech marks `"`
-- This is primarily a helper for Windows path compatibility
function quote(str)
   return ("\""..str.."\"")
end

-- Wrap string in quote marks `'`
-- The name means 'Paraphrasing Quote'
function pquote(str)
   return ("'"..str.."'")
end

--- Wrap a string in square brackets `[]`
-- Can optionally take an alternate string to wrap with
-- Optionally can wrap with different left-right pairs
function wrap(str, wrap_str, wrap_str_right)
   local wrapper_left   = wrap_str     or "["
   local wrapper_right  = wrap_str_right    or wrap_str or "]"
   safe_assert(type(str) == "string", "str must a string")

   return (wrapper_left..  str  ..wrapper_right)
end

--- Write a message to stdout, adhering to 'log_quiet'
function log(...)
   local message_string = string.concat(...)
   if log_quiet == false then
      _protected.print(message_string)
   end
end

--- Write to stdout, making a variable the 'subject' of the message
-- All arguments are automatically passed through 'tostring'.
-- The value argument is automatically quoted.
-- The varaiadic arugments are space seperated
function vallog(value, ...)
   local messages = {...}
   local message_string = ""
   local value_string = pquote(tostring(value))

   if type(value) == "string" then
      value_string = pquote(value)
   end
   for _, x_message in pairs(messages) do
      message_string = message_string..tostring(x_message).." "
   end

   value_string = wrap(value_string, "|")

   if log_quiet == false then
      _protected.print(value_string.." : "..message_string)
   end
end

--- Write a message to stdout, but only when 'log_verbose' is non-nl
-- The name or this function is intentionally shorter than would typically
-- be acceptable.
-- Such debug/programmer oriented functions are important, and something
-- trivial like time to type, or a long name cluttering code should not
-- be a factor in deciding not to them, it should be used often.
function dlog(...)
   if log_verbose and log_quiet == false then
      _protected.print("dlog:", ...)
   end
end
function dvallog(value, ...)
   local messages = {...}
   local message_string = ""
   local value_string = tostring(value)

   if type(value) == "string" then
      value_string = pquote(value)
   end
   for _, x_message in pairs(messages) do
      message_string = message_string..tostring(x_message).." "
   end

   value_string = wrap(value_string)

   if log_verbose and log_quiet == false then
      if #value_string <= 80 then
         _protected.print("[ dlog ]", value_string.." : "..message_string)
      else
         -- Reverse the order if the value is huge for readability
         _protected.print("[ dlog ]", message_string.." : "..value_string)
      end
   end
end

--- An reminder function that will error is 'debug_ignore' is false
-- This is just a helper function for writing code
--
-- WARNING: This should not *ever* ever used to prevent execution, that is *not*
-- the purpose, its not a pre-processor macro, everything before it will evaluate.
function TODO(...)
   local messages = {...}
   local message_string = ""

   for _, x_message in pairs(messages) do
      message_string = message_string..tostring(x_message).." "
   end
   safe_error("[TODO] "..message_string)
end

--- Specifies an unsafe operation is about to occur
-- This is mostly just a tagging mechanism for displaying/logging
function unsafe_begin(operation_description)
   safe_assert(operation_description, "\n unsafe operations must be well documetned")

   if UNSAFE == false then
      _protected.print("Operation marked as UNSAFE.           "..
                       "--UNSAFE not set, proceed with caution when using \n"..
                       "[Description]: "..
                       operation_description)
   elseif dry_run then
      _protected.print("UNSAFE: --dry-run specified, inhibiting dangerous actions.")
   end
end

--- Mark the beginning of a particular section of code
function section(name)
   log("["..name.." Begin]")
end

function end_seciton(name)
   log("[End "..name.."]")
end

--- Run a console command and log command if verbose
-- Will not run any commands if 'dry_run' is true
function safe_execute(command)
   safe_assert(type(command) == "string", "'command' must be type string")
   if dry_run ~= true then
      dvallog(command, "executing command")
      return _protected.os.execute(command)
   else
      vallog(command, "command would have been executed")
      return nil
   end
end

--- Run a console command that is protected by default from execution
-- The UNSAFE global variable is required to be set prior to running this command.
-- It also mandates that what is happening and why its dangeorus should be documented
-- as 'operation_description'
function unsafe_execute(command, operation_description)
   unsafe_begin("")

   safe_assert(type(operation_description) == "string",
               "unsafe commands must be well documented")
   safe_assert(type(command) == "string",
               "'command' must be type string")

   if dry_run ~= true and UNSAFE then
      dvallog(command, "executing command")
      return _protected.os.execute(command)
   else
      vallog(command, "UNSAFE command would have been executed")
      return nil
   end
end

--- Check if a file or directory exists in this path
function file_exists(file)
   local success, err, code = os.rename(file, file)
   if not success then
      if code == 13 then
         -- Permission denied, but it exists
         return true
      end
   end
   return success, err, code
end

--- Check if a directory exists in this path
function dir_exists(path)
   -- "/" works on both Unix and Windows
   return file_exists(path.."/")
end

--- Create all directories listed recursively
-- Can accept a table as an argument
function make_directories(...)
   local new_directories = {...}
   if type(new_directories[1]) == "table" then
      new_directories = new_directories[1]
   end

   local verbose_output = log_verbose and not log_quiet
   verbose_output = true
   for _, new_dir in pairs(new_directories) do
      if dir_exists(new_dir)then
         log(new_dir.." : directory already exists")
      else
         -- Quote path for Windows compatibility
         safe_execute("cmake -E make_directory "..quote(new_dir))
         if verbose_output then
            log(new_dir.." : created directory")
         end
      end

   end
end

--- Recursively remove everything in the directory
function remove_directories(...)
   -- the "-E" switch provides cross-platform tools provided by CMake
   local doomed_directories = {...}
   local remove_failiure = 1
   local _
   local quoted_dir = quote("")
   local all_sucess = true
   local command = ""

   safe_assert(#doomed_directories, "No argument provided")
   unsafe_begin("Removing directories and deleting their contents")
   if type(doomed_directories[1]) == "table" then
      doomed_directories = doomed_directories[1]
   end

   for _, x_directory in pairs(doomed_directories) do
      quoted_dir = quote(x_directory)
      command = "cmake -E rm -r "..quoted_dir
      dvallog(command, "Command will be executed")

      if UNSAFE == false or dry_run then
         vallog(x_directory, " Directory would be removed")
      else
         if dir_exists(x_directory) then
            _, _, remove_failiure = safe_execute("cmake -E rm -r "..quote(quoted_dir))
            log(quoted_dir)
         end
         if remove_failiure == 1 then
            log(quoted_dir.." : Failed remove directory")
            all_sucess = false
         else
            log(quoted_dir.." : Removed directory")
         end
      end
   end
   return all_sucess
end

function copy_file(source, destination)
   local command = ("cmake -E copy "..quote(source).." "..quote(destination))
   dvallog(command, "Command will be executed")
   safe_execute(command)
   log(source, destination)
end

--- Find the last occurance of substring and return the 2 indicies of the position
function string.find_last(str, substr, search_from)
   search_from = search_from or 1
   local match_start, match_end = nil, nil
   local tmp_start, tmp_end = nil, nil
   repeat
      tmp_start, tmp_end = string.find(str, substr, search_from)
      if tmp_end ~= nil then
         search_from = tmp_end+1
         match_start = tmp_start
         match_end = tmp_end
      end
   until tmp_start == nil
   return match_start, match_end
end

--- Does a shallow copy of the contents of the table, optonally to a target
-- Will return the new table
function table.copy(old, target)
   local new = target or {}
   for key, x_old_value in pairs(old) do
      new[key] = x_old_value
   end
   return setmetatable(new, getmetatable(old))
end

-- End of Helper functions
