#!/usr/bin/env lua
--[[
   GPL3 License
   Copyright (c) 2021 Mallchad
   This source provides the right to be freely used in any form,
   so long as modified variations remain available publically, or open request.
   Modified versions must be marked as such.
   The source comes with no warranty of any kind.
]]--

-- Forward Delcarations
local null
local _protected           = {}
local safe_error           ; null = safe_error
local const                ; null = const
local lock                 ; null = lock
local quote                ; null = quote
local pquote               ; null = pquote
local log                  ; null = log
local vallog               ; null = vallog
local dlog                 ; null = dlog
local dvallog              ; null = dvallog
local TLOG                 ; null = TLOG
local TODO                 ; null = TODO
local unsafe_begin         ; null = unsafe_begin
local safe_assert          ; null = safe_assert;
local safe_execute         ; null = safe_execute
local file_exists          ; null = file_exists
local dir_exists           ; null = dir_exists
local make_directories     ; null = make_directories
local remove_directories   ; null = remove_directories
local copy_file            ; null = copy_file
local configure            ; null = configure
local clean                ; null = clean
local build                ; null = build
local run                  ; null = run
local help                 ; null = help
local parse_arguments      ; null = parse_arguments
local regenerate_variables ; null = regenerate_variables
local main                 ; null = main
null = null

-- Variables
-- This section near the top is supposed to be easily edited, for quick
-- extensibility of documentation and passable variables
local log_verbose = false
local log_quiet = false
-- Record log messages to disk, does nothing yet
local log_record = false

local debug_enabled = false
-- Temporarily ignores some debug facilities that should error out
-- 'DEBUG_IGNORE' only needs to be set to be considered true
local debug_ignore = os.getenv("DEBUG_IGNORE") or nil

-- Enables dangerous operations like remove folders
local UNSAFE = false
-- Similar to the above but explicit, and more targeted for stable features
local dry_run = false
--- The keys describe action arguments which can be executed.
-- Each verb has a help string as its value
local arg_verbs =
   {
      build         = "regenerate the build system and compile the project",
      clean         = "remove local, non-critical untracked files where possible",
      configure     = "setup desirable local-only files and build enviornment",
      run           = "run the an executable from the project",
      help          = "display help string"
   }
--- Unordered arguments
-- The key is the argument name, the value is a help string
local arg_flags =
   {
      clean         = "Run a clean target before building",
      clean_only    = "Run a clean target only, without building",
      verbose       = "Enable verbose message output",
      quiet         = "Silence message output",
      dry_run       = "Don't do anything",
      build_first   = "Run a build before running an executable",
      UNSAFE        = "Disable saftey mechanisms on destructive operations"
   }
--- Unordered arguments that can store a value
-- The key is the argument name, the value is a help string
-- Optionally, the value can be a table, with a list of mutually exclusive,
-- pre-determined values, each with their own help strings
-- Optionally, the first unnamed ([1]) string in the aforementioned table
-- can be a help string associated with the variable
local arg_variables =
   {
      build_type =
         {
            [[A string that is a passed to cmake as PROJECT_BUILD_TYPE, as well as '--config' cmake build option variable]],
            debug       = "Build Type: Type with debugging symbols",
            development = "Build Type: with no special settings or optimizations",
            testing     = "Build Type: with optimizations but also with development tools",
            release     = "Build Type: a project with optimizations on and no development tools"
         }
   }
-- End of argument/documentation options

--- current working directory, relative to the helper script
-- This is the only realistic way of getting some kind of inkling of the
-- project root relative working directy without pulling in external
-- dependencies or scripts
local arg_relative_root = arg[0]
local arg_command = arg[0]
local arg_parsed_verb = arg[1]
local arg_parsed = {}
local arg_verb_passed = false
local arg_help_passed = false

local dirs =
   {
      root = "."
   }
--- All used local-only project directories, relative to project root
-- This is supposed to be temporary directories/files that are ok to delete
-- The 'build' subdirectories have to be specified as relative
-- to the parent 'build' directory, because of the way cmake changes directories.
-- Otherwise absolute directories can be used
local local_dirs =
   {
      build             = "build",
      build_binaries    = "./bin",
      build_artifacts   = "./artifacts",
      build_debug       = "./debug",
   }
local help_string =
   {
      main = [[
usage: run.lua <verb> <args>

This is a helper tool to aid with working with the project.

Verbs:
]],
verbs_documentation = "",
build = [[

The types valid for this project are:
debug - Build with debugging symbols
development - Build with no special settings or optimizations
testing - Build with optimizations but also with development tools
release - Build a project with optimizations on and no development tools

      ]],
      clean = [[Builds the project

type 'build.lua clean' to clean the files
before building (currently does nothing) ]]
   }
-- '-B' is build directory
local build_configure_command = "cmake -B build"
local build_binary_command = "cmake --build "..local_dirs.build
local build_clean_command = "cmake --build "..local_dirs.build.." --target clean"
local build_primary_executable_name = "executable"
local build_primary_executable_path = local_dirs.build_binaries.."/"..build_primary_executable_name
local cmake_variables =
   {
      CMAKE_BUILD_TYPE              = nil,
      UNIMALLET_MINIMUM_CXX_STANDARD   = 17,
      UNIMALLET_BUILD_DIR              = local_dirs.build,
      UNIMALLET_BINARY_DIR             = local_dirs.build_binaries,
      UNIMALLET_LIBRARY_DIR            = local_dirs.build_libraries,
      UNIMALLET_ARTIFACT_DIR           = local_dirs.build_artifacts,
      UNIMALLET_DEBUG_DIR              = local_dirs.build_debug,
      UNIMALLET_ENABLE_DEBUG           = true,
      UNIMALLET_USE_CCACHE             = true,
      UNIMALLET_USE_CLANG              = true,
      UNIMALLET_TEST_VAR               = "Hello, I'm an irrational value!"
   }

local help_elastic_padding = 20
local help_option_padding = 5
local help_option_elastic_padding = 20

-- Helper functions

--- Temporary Logging facilities that will error if 'debug_ignore' is false
-- This value is considered true if enviornment variable 'DEBUG_IGNORE'
-- has been set
local function TLOG(...)
   assert(debug_ignore, "Debugging is disabled, you should delete this temporary line")
   _protected.print("TLOG:",...)
end

local function safe_assert(condition, message)
   message = message or "An undocumented assert has failed"
   if condition == false and debug_ignore == nil then
      _protected.error("[safe_assert] "..message)
   elseif condition == false then
      _protected.print("[safe_assert] (supressed): "..message)
   end
end
local function safe_error(message)
   message = message or "An undocumented error has occured"
   _protected.assert(debug_ignore, "[ safe_error ] "..message)
   _protected.print("[safe_error] (supressed): "..message)
end

-- Produce a proxy table that is a read-only version of a table
local function const(original_table)
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
local function lock(original_table)
   return const(original_table)
end

-- Overwrite some standard functionality
_protected.print = print
_protected.error = error
_protected.assert = assert

for k_overriden, _ in pairs(_protected) do
   _G[k_overriden] = function()
      safe_error(k_overriden.." has been disabled, please use the replacement functions instead")
   end
end
_protected = lock(_protected)

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
--- Wrap a string in speech marks
-- This is primarily a helper for Windows path compatibility
local function quote(str)
   return ("\""..str.."\"")
end
-- Wrap string in quote marks
-- The name means 'Paraphrasing Quote'
local function pquote(str)
   return ("'"..str.."'")
end
--- Write a message to stdout, adhering to 'log_quiet'
local function log(...)
   local message_string = string.concat(...)
   if log_quiet == false then
      _protected.print(message_string)
   end
end
--- Write to stdout, making a variable the 'subject' of the message
-- All arguments are automatically passed through 'tostring'.
-- The value argument is automatically quoted.
-- The varaiadic arugments are space seperated
local function vallog(value, ...)
   local messages = {...}
   local message_string = ""
   local value_string = pquote(tostring(value))
   for _, x_message in pairs(messages) do
      message_string = message_string..tostring(x_message).." "
   end
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
local function dlog(...)
   if log_verbose and log_quiet == false then
      _protected.print("dlog:", ...)
   end
end
local function dvallog(value, ...)
   local messages = {...}
   local message_string = ""
   local value_string = tostring(value)

   if type(value) == "string" then
      value_string = pquote(value)
   end
   for _, x_message in pairs(messages) do
      message_string = message_string..tostring(x_message).." "
   end

   if log_verbose and log_quiet == false then
      if #value_string >= 80 then
         _protected.print("[ dlog ]", message_string.." : "..value_string)
      else
         _protected.print("[ dlog ]", value_string.." : "..message_string)
      end
   end
end

--- An reminder function that will error is 'debug_ignore' is false
-- This is just a helper function for writing code
local function TODO(...)
   local messages = {...}
   local message_string = ""

   for _, x_message in pairs(messages) do
      message_string = message_string..tostring(x_message).." "
   end
   safe_error(debug_ignore == nil, "[TODO] "..message_string)
end
--- Specifies an unsafe operation is about to occur
-- This is mostly just for displaying/logging
local function unsafe_begin(operation_description)
   safe_assert(operation_description, "description argument not supplied")
   if UNSAFE == false then
      _protected.print("Operation marked as UNSAFE. Description: \n"
                       ..operation_description.."\n")
      _protected.print("--UNSAFE not set, proceed with caution when using")
   elseif dry_run then
      _protected.print("UNSAFE: --dry-run specified, inhibiting dangerous actions.")
   end
end
--- Run a console command and log command if verbose
-- Will not run any commands if 'dry_run' is true
local function safe_execute(command)
   safe_assert(type(command) == "string", "'command' must be type string")
   if dry_run ~= true then
      dvallog(command, "executing command")
      return os.execute(command)
   else
      vallog(command, "command would have been executed")
      return nil
   end
end
--- Check if a file or directory exists in this path
local function file_exists(file)
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
local function dir_exists(path)
   -- "/" works on both Unix and Windows
   return file_exists(path.."/")
end
--- Create all directories listed recursively
-- Can accept a table as an argument
local function make_directories(...)
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
local function remove_directories(...)
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
local function copy_file(source, destination)
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
function table:copy(old, target)
   local new = target or {}
   for key, x_old_value in pairs(old) do
      new[key] = x_old_value
   end
   return setmetatable(new, getmetatable(old))
end

-- End of Helper functions
-- Operational Functions

-- Do any post-build setup required
local function configure()
   -- Create any neccecary directories
   log("[Configuring Build]")
   make_directories(local_dirs)

   -- Generate helpful or neccecary local files
   safe_execute("cmake -S "..dirs.root.." -B "..local_dirs.build.. " -DCMAKE_EXPORT_COMPILE_COMMANDS=1")
   copy_file(local_dirs.build.."/compile_commands.json", dirs.root.."/compile_commands.json")
   log("")                  -- Just command line padding
end
local function clean()
   log("[Clean Start]")
   remove_directories(local_dirs)
   log("[Clean Done] \n")
end
local function build()
   cmake_variables.UNIMALLET_BUILD_TYPE = arg_parsed.build_type or "development"
   local build_type = cmake_variables.UNIMALLET_BUILD_TYPE
   vallog(build_type, "Build Type")
   local cmake_variables_string = ""

   -- Build Arguments
   for x_var_name, x_var_value in pairs(cmake_variables) do
      if type(x_var_value) == "string" then
         -- String values should be quoted
         cmake_variables_string = cmake_variables_string..
            "-D"..x_var_name.."="..quote(tostring(x_var_value)).." "
      else
         cmake_variables_string = cmake_variables_string..
            "-D"..x_var_name.."="..tostring(x_var_value).." "
      end
   end
   cmake_variables_string = cmake_variables_string.."-DCMAKE_BUILD_TYPE="..build_type

   local build_setup_string = build_configure_command.." "..cmake_variables_string
   local build_binary_string = build_binary_command.." --config="..build_type

   log("[Pre-Build]")
   if arg_parsed.clean or arg_parsed.clean_only then
      log("Cleaning build area")
      safe_execute(build_clean_command)
   end
   if arg_parsed.clean_only ~= true then
      log("[Build Start]")

      safe_execute(build_setup_string)
      safe_execute(build_binary_string)

      log("[Finishing Up]")
      log("[Done]")
      log("")                  -- Just command line padding
   end
end
--- Run the built binary
-- Optionally can build running
local function run()
   local build_first = arg_parsed.build_first or false
   local executable_string = build_primary_executable_path

   -- Append any extra arguments
   for _, x_arg in ipairs(arg_parsed) do
      executable_string = executable_string.." "..x_arg
   end
   if build_first then
      build()
   end
   safe_execute(executable_string)
   log("")                  -- Just command line padding
end
-- Display the help text
local function help()
   local generated_help_string = help_string.main
   local tmp_arg_name = ""

   -- Everything is padded to tab stops '\n'
   -- Verbs
   for k_name, x_help_string in pairs (arg_verbs) do
      local elastic_padding = help_elastic_padding - #k_name
      local elastic_padding_string = string.rep(" ", elastic_padding)
      local padding_string = string.rep(" ", help_elastic_padding)
      local tmp_help_string = ""
      tmp_arg_name = string.gsub(k_name, "_", "-") -- use more CLI friendly hyphen
      -- Align subsequent newlines
      tmp_help_string =
         string.gsub(x_help_string, "\n", "\n"..padding_string)

      generated_help_string =
         generated_help_string..
         tmp_arg_name..elastic_padding_string..
         tmp_help_string.."\n"
   end
   generated_help_string = generated_help_string..
      "\n"..
      "Arguments:".."\n"

   -- Flags
   for k_name, x_help_string in pairs (arg_flags) do
      local alignment_padding = help_elastic_padding - #k_name
      local alignment_padding_string = string.rep(" ", alignment_padding)
      tmp_arg_name = string.gsub(k_name, "_", "-")
      tmp_arg_name = "--"..tmp_arg_name

      generated_help_string =
         generated_help_string..
         tmp_arg_name..alignment_padding_string..
         x_help_string.."\n"
   end

   -- Variables
   for k_name, x_help_string in pairs (arg_variables) do
      local elastic_padding = help_elastic_padding - #k_name
      local elastic_padding_string = string.rep(" ", elastic_padding)
      local option_padding_string = string.rep(" ", help_option_padding)
      local alignment_padding_string = string.rep(" ", help_elastic_padding)
      local option_elastic_padding = 0
      local option_elastic_padding_string = 0
      local option_help_string = (x_help_string[1] or "<undocumented>")

      tmp_arg_name = string.gsub(k_name, "_", "-") -- use more
      tmp_arg_name = "--"..tmp_arg_name
      -- Align subsequent newlines
      option_help_string = string.gsub(option_help_string,
                                       "\n",
                                       "\n  "..alignment_padding_string)

      generated_help_string =
         generated_help_string..
         tmp_arg_name..elastic_padding_string..
         option_help_string.."\n"..
         option_padding_string..
         "Expected Options: \n"
      for k_option, x_option_help_string in pairs(arg_variables[k_name]) do
         if type(k_option) == "string" then
            option_elastic_padding = help_option_elastic_padding - #k_option
            option_elastic_padding_string = string.rep(" ", option_elastic_padding)

            generated_help_string =
               generated_help_string..
               option_padding_string..
               k_option..
               option_elastic_padding_string..
               x_option_help_string.."\n"
         end
      end
   end

   log(generated_help_string)
   log("")                  -- Just command line padding
end
--- Parses the arguments
local function parse_arguments()
   local parsing_failiure = false
   -- Command non-argument '0'
   local _, path_end = string.find_last(arg_relative_root, "/")
   if path_end == nil then
      _, path_end = string.find_last(arg_relative_root, "\\")
   end
   if path_end ~= nil then
      arg_command = string.sub(arg_relative_root, path_end+1)
      -- Strip trailing slash with 'path_end-1'
      arg_relative_root = string.sub(arg_relative_root, 1, path_end-1)
   elseif path_end == nil then
      arg_relative_root = ""
   end

   -- Verb Arguments
   if arg_parsed_verb ~= nil then
      arg_verb_passed = true
   end
   if arg_parsed_verb == "--help" or
      arg_parsed_verb == "-h" or
      arg_parsed_verb == "help" then
      arg_help_passed = true
   end

   -- Flag and Variable Arguments
   local i_arg = 2
   while i_arg <= #arg do
      local unformatted_xarg = arg[i_arg]
      local x_arg_value = arg[i_arg+1]
      local x_arg = ""

      -- strip leading 2 hyphens then normalize to lua friendly keynames (_)
      if #unformatted_xarg > 2 then
         x_arg = string.sub(unformatted_xarg, 3)
      end
      x_arg = x_arg:gsub("-", "_") -- use more

      if x_arg == "help" or unformatted_xarg == "-h" or unformatted_xarg == "help" then
         arg_help_passed = true
         arg_parsed[x_arg] = true
      elseif arg_flags[x_arg] ~= nil then
         arg_parsed[x_arg] = true
      elseif arg_variables[x_arg] ~= nil then
         if arg_variables[x_arg][x_arg_value] then
            dvallog(x_arg_value, "using valid value for argument", unformatted_xarg)
         else
            vallog(x_arg_value, "using undocumented value for argument",
                   pquote(tostring(unformatted_xarg)))

         end
         arg_parsed[x_arg] = x_arg_value
         i_arg = i_arg+1
      else
         log(pquote(unformatted_xarg).." is not a recognised argument")
         parsing_failiure = true
      end
      i_arg = i_arg+1
   end

   if parsing_failiure then
      log([[

Command was not executed.
Type --help to get a list of valid arguments]])
   end
   log("")                  -- Just command line padding
   return parsing_failiure
end
--- Regenerate all values based on passed arguments and changed variables
-- This should only be run once, running it more that once will result in
-- duplicate substrings in strings
local function regenerate_variables()
   -- Table aliases
   local averb = arg_verbs
   local apos = arg_flags
   local aval = arg_variables
   local dir = dirs
   local ldir = local_dirs
   local hstr = help_string
   local cvar = cmake_variables

   -- Everything set here should assume it might be run multiple times
   -- Additionally, this function not for setting default values, that's just confusing
   -- It should also be assumed that the user might have manually set a variable
   -- through this build tool
   log_verbose = arg_parsed.verbose or false
   log_quiet = arg_parsed.quiet or false

   UNSAFE = arg_parsed.UNSAFE or false
   dry_run = arg_parsed.dry_run

   dir.root                = arg_relative_root
   ldir.build              = dir.root.."/build"
   -- Build dirs have to be relative to root or absolute, for CMake
   ldir.build_binaries     = "bin"
   ldir.build_artifacts    = "artifacts"
   ldir.build_libraries    = "lib"
   ldir.build_debug        = "debug"
   build_configure_command =
      "cmake -S "..quote(dir.root).." -B "..quote(ldir.build)
   build_binary_command = "cmake --build "..quote(ldir.build)
   build_clean_command = "cmake --build "..quote(ldir.build).. " --target clean"
   build_primary_executable_name = "executable"
   build_primary_executable_path = string.construct_path(ldir.build,
                                                         ldir.build_binaries,
                                                         build_primary_executable_name)
   cvar.UNIMALLET_BUILD_TYPE      = cvar.UNIMALLET_BUILD_TYPE
   cvar.UNIMALLET_BUILD_DIR       = ldir.build
   cvar.UNIMALLET_BINARY_DIR      = ldir.build_binaries
   cvar.UNIMALLET_LIBRARY_DIR     = ldir.build_libraries
   cvar.UNIMALLET_ARTIFACT_DIR    = ldir.build_artifacts
   cvar.UNIMALLET_DEBUG_DIR       = local_dirs.build_debug
   cvar.UNIMALLET_ENABLE_DEBUG    = cvar.UNIMALLET_ENABLE_DEBUG
   cvar.UNIMALLET_ENABLE_DEBUG    = cvar.UNIMALLET_ENABLE_DEBUG
   cvar.UNIMALLET_LOG_QUIET       = log_quiet
   cvar.UNIMALLET_LOG_VERBOSE     = log_verbose
   cvar.UNIMALLET_USE_CCACHE      = cvar.UNIMALLET_USE_CCACHE
   cvar.UNIMALLET_USE_CLANG       = cvar.UNIMALLET_USE_CLANG
   cvar.UNIMALLET_TEST_VAR        = cvar.UNIMALLET_TEST_VAR

   help_elastic_padding             = 20
   help_option_padding              = 5
   help_option_elastic_padding      = 20

end
-- Program Start
local function main()
   local parsing_failure = parse_arguments()
   local regeneration_failiure = regenerate_variables()
   if parsing_failure or regeneration_failiure then return end

   -- Determine and run action to run
   if arg_help_passed then
      help()
   elseif arg_verb_passed == false then
      log("No command or verb supplied, type 'run.lua --help' for commands")
      return 1
   elseif arg_parsed_verb == "build" then
      build()
   elseif arg_parsed_verb == "run" then
      run()
   elseif arg_parsed_verb == "configure" then
      configure()
   elseif arg_parsed_verb == "clean" then
      clean()
   else
      log("Unrecognized verb argument "..pquote(arg_parsed_verb)..
          ", type --help for commands")
   end

end
main()
