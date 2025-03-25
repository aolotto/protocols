local membuddy = {}

-- Utility to get memory usage in bytes
local function get_memory()
    return collectgarbage("count") * 1024
end

-- Measure memory usage of a variable
local function measure_object_memory(obj)
    -- Clean up before we start
    collectgarbage("collect")
    collectgarbage("collect")

    -- Measure initial memory state
    local before = get_memory()

    -- Create a copy that will consume memory
    local copy
    if type(obj) == "string" then
        copy = string.sub(obj, 1)  -- Force a new string allocation
    elseif type(obj) == "number" or type(obj) == "boolean" then
        copy = obj  -- Value types
    elseif type(obj) == "table" then
        copy = {}   -- Empty table
    else
        copy = obj  -- Other types
    end

    -- Immediately measure the memory impact WITHOUT garbage collecting
    local after = get_memory()

    -- Force the variable to be used to prevent optimization
    -- This dummy operation ensures the copy exists in memory
    -- but doesn't significantly affect our measurement
    local dummy = copy or 0

    -- The GC should collect the copy after the function returns, but in case it
    -- doesn't do so immediately, we manually remove it here.
    copy = nil
    if dummy then
        dummy = nil
    end
    collectgarbage("collect")
    collectgarbage("collect")
    
    -- Calculate the difference
    return math.max(0, after - before)
    
    -- After we return, 'copy' goes out of scope and will be eligible for GC
end

-- Build a table of memory usage for each path
local function build_memory_table(obj, path, max_depth, current_depth, visited, result, circular, total_sizes)
    visited = visited or {}
    result = result or {}
    circular = circular or {}
    total_sizes = total_sizes or {}  -- Track total sizes including children
    path = path or ""
    current_depth = current_depth or 0

    -- Check for circular references
    if visited[obj] then
        circular[path] = visited[obj]
        -- Estimate reference overhead (~ 8-16 bytes) instead of zero
        local reference_overhead = measure_object_memory({})  -- Table pointer overhead
        result[path] = reference_overhead
        return reference_overhead
    end

    -- Register current object in visited map with its path
    visited[obj] = path

    -- For non-table objects, measure directly
    if type(obj) ~= "table" then
        result[path] = measure_object_memory(obj)
        return result[path]
    end

    -- For tables, we need to decide based on depth
    if max_depth ~= nil and current_depth >= max_depth then
        -- We've reached max depth - measure the subtree efficiently
        local subtree_size = 0
        local subtree_visited = {}

        -- Local function to traverse and measure the subtree without full cloning
        local function measure_subtree(o)
            if subtree_visited[o] then return 0 end
            subtree_visited[o] = true
            if type(o) ~= "table" then
                return measure_object_memory(o)
            end
            -- Measure table overhead
            local size = measure_object_memory({})
            -- Sum memory for all keys and values
            for k, v in pairs(o) do
                if type(k) == "table" then
                    size = size + measure_subtree(k)
                else
                    size = size + measure_object_memory(k)
                end
                size = size + measure_subtree(v)
            end
            return size
        end

        -- Perform the measurement and record the result
        subtree_size = measure_subtree(obj)
        result[path .. (path ~= "" and "/..." or "...")] = subtree_size
        return subtree_size
    end

    -- First measure the empty table itself (table overhead)
    local empty_table = {}
    local table_overhead = measure_object_memory(empty_table)
    
    -- Initialize total size for this table
    local this_table_total_size = table_overhead
    
    -- Then measure each key-value pair
    for k, v in pairs(obj) do
        local key_str = tostring(k)
        local new_path = path ~= "" and (path .. "/" .. key_str) or key_str
        
        -- Recurse for each value
        local child_size = build_memory_table(
            v, new_path, max_depth,
            current_depth + 1, visited, result, circular, total_sizes
        )
        
        -- Add child size to this table's total
        this_table_total_size = this_table_total_size + child_size
    end
    
    -- Record both the table overhead for this specific path
    result[path] = table_overhead
    
    -- Also track the total size including children
    total_sizes[path] = this_table_total_size
    
    return this_table_total_size
end

-- Format the results for better readability
local function postprocess_results(memory_table, cycles, total_sizes)
    local sizes = {}
    local total_size = 0

    for path, size in pairs(memory_table) do
        sizes[path] = size
        total_size = total_size + size
    end

    return {
        totalSize = total_size,
        sizes = sizes,
        totalSizes = total_sizes or {}, -- Include total sizes with children
        cycles = cycles,
        type = "membuddy-results"
    }
end

-- Main function to profile memory usage
function membuddy.profile(options)
    options = options or {}
    local target = options.target or _G
    local find_cycles = options.cycles or true
    
    -- Handle infinity values for max_depth
    local max_depth = options.max_depth
    if max_depth == nil then
        max_depth = 3  -- Default
    elseif max_depth == math.huge or 
           (type(max_depth) == "string" and 
           (string.lower(max_depth) == "infinity" or 
            string.lower(max_depth) == "inf")) then
        max_depth = nil  -- nil represents no depth limit in our traversal code
    end
    
    local memory_table = {}
    local circular = {}
    local total_sizes = {}
    
    -- Only track circular references if find_cycles is not explicitly false
    local cycles_to_track = (find_cycles ~= false) and circular or {}
    
    local total = build_memory_table(target, "", max_depth, 0, {}, memory_table, cycles_to_track, total_sizes)
    
    -- Format human readable sizes
    local formatted = {}
    for path, size in pairs(memory_table) do
        -- Skip empty path which represents the root
        if path ~= "" then
            formatted[path] = size
        end
    end
    
    return postprocess_results(formatted, cycles_to_track, total_sizes)
end

-- Format number of bytes to human readable string
function membuddy.format_size(bytes, use_colors)
    local units = {"bytes", "KB", "MB", "GB"}
    local size = bytes
    local unit_index = 1
    
    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end
    
    local num_part
    if unit_index == 1 then
        num_part = string.format("%.0f", size)
    else
        num_part = string.format("%.2f", size)
    end
    
    -- Apply colors if requested
    if use_colors then
        local C = _G.Colors or {
            reset = "", green = "", red = "", gray = "", blue = ""
        }
        
        if unit_index == 1 then
            -- Bytes number in green, units in gray
            return C.green .. num_part .. C.reset .. C.gray .. " " .. units[unit_index] .. C.reset
        else
            -- KB or larger number in red, units in gray
            return C.red .. num_part .. C.reset .. C.gray .. " " .. units[unit_index] .. C.reset
        end
    end
    
    -- Without colors
    return num_part .. " " .. units[unit_index]
end

local function count_entries(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Pretty print the results with color
function membuddy.print(optionsOrResults)
    local options = optionsOrResults or {}
    local results
    -- If the user has already provided us with a results table, we use that.
    -- Else, we profile the given `target` (or _G by default) and return format
    -- the results on the console.
    if options.type and options.type == "membuddy-results" then
        results = optionsOrResults
        options = {
            min_size = options.min_size or 1,
            top = options.top or false,
            cycles = options.cycles or true
        }
    else
        results = membuddy.profile(options)
    end
    local min_size = options.min_size or 1  -- Default: filter anything below 1 byte
    local top = options.top
    if top == nil then top = 20 end  -- Default: show top 20 results
    
    -- Check if Colors table exists in the environment
    local C = _G.Colors or {
        reset = "", green = "", red = "", gray = "", blue = ""
    }
    
    if options.no_header ~= true then
        print(C.blue .. "   ===================== " ..
                C.red .. "MEM" .. C.green .. "BUDDY" .. C.gray ..
                C.blue .. " =====================" .. C.reset)
    end

    local total_results = count_entries(results.sizes) + count_entries(results.cycles)
    print(C.gray .. "\nAnalyzed a total of " .. C.green .. total_results .. C.gray ..
          " references." .. C.reset)
    print(C.gray .. "Total memory utilized" .. C.gray .. ": " .. 
          membuddy.format_size(results.totalSize, true) .. ".\n")
    
    print(C.gray .. "Memory usage by reference name:" .. C.reset)
    -- Sort and filter paths by size
    local paths = {}
    for path, size in pairs(results.sizes) do
        if size >= min_size then
            -- Use total size if available for better sorting
            local display_size = size
            if results.totalSizes[path] then
                display_size = results.totalSizes[path]
            end
            table.insert(paths, {path = path, size = display_size})
        end
    end
    table.sort(paths, function(a, b) return a.size > b.size end)
    
    -- Handle top results limiting
    local paths_filtered = false
    local display_count = #paths
    local hidden_paths = 0
    local hidden_total = 0
    
    if top ~= false and type(top) == "number" and top < #paths then
        display_count = top
        paths_filtered = true
        
        -- Calculate hidden items info
        hidden_paths = #paths - top
        for i = top + 1, #paths do
            hidden_total = hidden_total + paths[i].size
        end
    end
    
    -- Print each displayed path with colorized ellipsis
    for i = 1, display_count do
        local item = paths[i]
        -- Check if path ends with "..." and colorize it correctly
        local display_path = item.path
        local ellipsis_pos = display_path:find("/%.%.%.$")
        
        if ellipsis_pos then
            -- Path ends with "/..."
            local base_path = display_path:sub(1, ellipsis_pos - 1)  -- Don't include the slash
            display_path = C.blue .. base_path .. C.reset .. C.gray .. "/" .. 
                          C.green .. "..." .. C.gray
        elseif display_path == "..." then
            -- Just ellipsis
            display_path = C.green .. display_path .. C.gray
        else
            display_path = C.blue .. display_path .. C.gray
        end
        
        print(string.format("    %s → %s", 
            display_path,
            membuddy.format_size(item.size, true)))
    end
    
    -- Show message about hidden paths if any
    if hidden_paths > 0 then
        print(string.format("%s...and %s%d%s other references, totalling %s.%s", 
            C.gray, 
            C.green, 
            hidden_paths, 
            C.gray, 
            membuddy.format_size(hidden_total, true),
            C.reset))
    end
    
    -- Print circular references if any and if not disabled
    local cycles_filtered = false
    local hidden_cycles = 0
    local hidden_cycles_total = 0
    
    if next(results.cycles) and options.cycles ~= false then
        print("\n" .. C.gray .. "Found circular references "
            .. "(potentially retaining data unnecessarily):" .. C.reset)
        local cycles = {}
        
        for path, target in pairs(results.cycles) do
            -- Get the target size
            local target_size = 0
            if results.totalSizes[target] then
                target_size = results.totalSizes[target]
            end
            
            -- Skip zero-byte targets (likely C modules we can't measure)
            if target_size > 0 then
                -- Create a more informative message
                local msg
                if target == "" then
                    msg = string.format("    %s%s%s: %sself-reference%s (%s)", 
                        C.blue, path, C.reset,
                        C.gray, C.reset,
                        membuddy.format_size(target_size, true))
                elseif target == path then
                    msg = string.format("    %s%s%s: %sdirect self-reference%s (%s)", 
                        C.blue, path, C.reset,
                        C.gray, C.reset,
                        membuddy.format_size(target_size, true))
                else
                    -- Just show the referenced object size
                    msg = string.format("    %s%s%s %s→%s %s%s%s (%s)", 
                        C.blue, path, C.reset,
                        C.gray, C.reset,
                        C.green, target, C.reset,
                        membuddy.format_size(target_size, true))
                end
                
                table.insert(cycles, {message = msg, size = target_size})
            end
        end
        
        -- Sort by size to highlight the largest circular references
        table.sort(cycles, function(a, b) return a.size > b.size end)
        
        -- Apply top limit to circular references too
        local cycle_display_count = #cycles
        
        if top ~= false and type(top) == "number" and top < #cycles then
            cycle_display_count = top
            cycles_filtered = true
            
            -- Count hidden cycles
            hidden_cycles = #cycles - top
            for i = top + 1, #cycles do
                hidden_cycles_total = hidden_cycles_total + cycles[i].size
            end
        end
        
        -- Print circular references
        if #cycles > 0 then
            for i = 1, cycle_display_count do
                print(cycles[i].message)
            end
            
            -- Show message about hidden cycles if any
            if hidden_cycles > 0 then
                print(string.format("%s...and %s%d%s other circular references, totalling %s.%s", 
                    C.gray, 
                    C.green, 
                    hidden_cycles, 
                    C.gray, 
                    membuddy.format_size(hidden_cycles_total, true),
                    C.reset))
            end
        else
            print(string.format("    %sNo significant circular references found%s", 
                C.gray, C.reset))
        end
    end
    
    -- Show a single help message if anything was filtered
    if paths_filtered or cycles_filtered then
        print(string.format("\n%s%d%s results were filtered. Use %stop = number|false%s to show more results.%s", 
            C.green, hidden_paths + hidden_cycles, C.gray, C.blue, C.gray, C.reset))
    end
    
    -- Do not return the results
    return nil
end

Membuddy = membuddy
return membuddy