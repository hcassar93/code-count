-- Code Count Hammerspoon Configuration
-- Author: Hayden
-- Description: Hammerspoon configuration for code counting functionality

-- Forward declarations
local updateMenubar
local latestResults = {} -- Store latest cloc results

-- Reload configuration when this file changes
hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", function(files)
    local doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then
            doReload = true
        end
    end
    if doReload then
        hs.reload()
    end
end):start()

-- Check if cloc is installed
local function checkClocInstallation()
    -- Common paths where cloc might be installed
    local possiblePaths = {
        "/opt/homebrew/bin/cloc",  -- Apple Silicon Homebrew
        "/usr/local/bin/cloc",     -- Intel Homebrew
        "/usr/bin/cloc"            -- System installation
    }
    
    -- First try the which command with expanded PATH
    local clocCheck = hs.execute("export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH && which cloc")
    if clocCheck and clocCheck ~= "" then
        print("cloc found via which at: " .. clocCheck:gsub("\n", ""))
        return true
    end
    
    -- If which fails, check common installation paths directly
    for _, path in ipairs(possiblePaths) do
        local file = io.open(path, "r")
        if file then
            file:close()
            print("cloc found at: " .. path)
            return true
        end
    end
    
    -- If all checks fail
    hs.notify.new({
        title="Code Count - Error", 
        informativeText="cloc is not installed. Please install via: brew install cloc",
        hasActionButton=false
    }):send()
    print("ERROR: cloc is not installed. Please run: brew install cloc")
    return false
end

-- Check cloc installation on startup
local clocAvailable = checkClocInstallation()

-- Get the path to cloc executable
local function getClocPath()
    -- First try the which command with expanded PATH
    local clocCheck = hs.execute("export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH && which cloc")
    if clocCheck and clocCheck ~= "" then
        return clocCheck:gsub("\n", "")
    end
    
    -- Check common installation paths directly
    local possiblePaths = {
        "/opt/homebrew/bin/cloc",  -- Apple Silicon Homebrew
        "/usr/local/bin/cloc",     -- Intel Homebrew
        "/usr/bin/cloc"            -- System installation
    }
    
    for _, path in ipairs(possiblePaths) do
        local file = io.open(path, "r")
        if file then
            file:close()
            return path
        end
    end
    
    return nil
end

-- Show notification on startup
if clocAvailable then
    hs.notify.new({title="Code Count", informativeText="Configuration loaded - cloc ready"}):send()
    print("Code Count Hammerspoon configuration loaded successfully")
else
    hs.notify.new({title="Code Count", informativeText="Configuration loaded - cloc missing"}):send()
    print("Code Count Hammerspoon configuration loaded with warnings")
end

-- Configuration storage
local configFile = os.getenv("HOME") .. "/.hammerspoon/code_count_config.json"
local countsDir = os.getenv("HOME") .. "/Desktop/Counts"
local config = {
    directories = {}
}

-- Create Counts directory if it doesn't exist
local function ensureCountsDirectory()
    local checkDir = hs.execute("test -d '" .. countsDir .. "' && echo 'exists' || echo 'missing'")
    if not checkDir or checkDir:gsub("\n", "") ~= "exists" then
        local createResult = hs.execute("mkdir -p '" .. countsDir .. "'")
        print("Created Counts directory on Desktop:", createResult or "success")
    end
end

-- Save CSV result to file
local function saveCsvResult(dirPath, dirName, csvOutput, timestamp)
    ensureCountsDirectory()
    
    -- Create a safe filename from directory name
    local safeFileName = dirName:gsub("[^%w%-_.]", "_") .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".csv"
    local csvFilePath = countsDir .. "/" .. safeFileName
    
    -- Add metadata header to CSV
    local csvContent = "# Code Count Results for: " .. dirPath .. "\n"
    csvContent = csvContent .. "# Generated: " .. timestamp .. "\n"
    csvContent = csvContent .. "# \n"
    csvContent = csvContent .. csvOutput
    
    local file = io.open(csvFilePath, "w")
    if file then
        file:write(csvContent)
        file:close()
        print("Saved CSV results to:", csvFilePath)
        return csvFilePath
    else
        print("Failed to save CSV to:", csvFilePath)
        return nil
    end
end

-- Load previous results from CSV files
local function loadPreviousResults()
    ensureCountsDirectory()
    
    -- Get list of CSV files in Counts directory
    local listFiles = hs.execute("ls -1 '" .. countsDir .. "'/*.csv 2>/dev/null | head -20")
    if not listFiles or listFiles == "" then
        print("No previous CSV results found")
        return
    end
    
    local csvFiles = {}
    for file in listFiles:gmatch("[^\r\n]+") do
        table.insert(csvFiles, file)
    end
    
    print("Found", #csvFiles, "previous CSV files")
    
    -- Load results from most recent CSV files for each directory
    local loadedResults = {}
    for _, csvFile in ipairs(csvFiles) do
        local file = io.open(csvFile, "r")
        if file then
            local content = file:read("*all")
            file:close()
            
            -- Extract directory path from header
            local dirPath = content:match("# Code Count Results for: ([^\n]+)")
            local timestamp = content:match("# Generated: ([^\n]+)")
            
            if dirPath and timestamp then
                -- Extract just the CSV data (skip header lines)
                local csvData = content:gsub("^#[^\n]*\n", ""):gsub("^#[^\n]*\n", ""):gsub("^#[^\n]*\n", "")
                
                local dirName = dirPath:match("([^/]+)$") or dirPath
                
                -- Only load if we don't have a newer result for this directory
                if not loadedResults[dirPath] or timestamp > loadedResults[dirPath].timestamp then
                    loadedResults[dirPath] = {
                        name = dirName,
                        path = dirPath,
                        csvOutput = csvData,
                        timestamp = timestamp,
                        csvFile = csvFile,
                        loaded = true
                    }
                    
                    -- Parse total lines from CSV
                    for line in csvData:gmatch("[^\r\n]+") do
                        if line:match("SUM,") then
                            local parts = {}
                            for part in line:gmatch("([^,]+)") do
                                table.insert(parts, part)
                            end
                            if #parts >= 5 then
                                loadedResults[dirPath].totalLines = parts[5]
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    
    -- Merge loaded results with current results
    for path, result in pairs(loadedResults) do
        latestResults[path] = result
    end
    
    print("Loaded", hs.fnutils.reduce(hs.fnutils.map(loadedResults, function() return 1 end), function(acc, val) return acc + val end, 0), "previous results")
end

-- Load configuration from file
local function loadConfig()
    local file = io.open(configFile, "r")
    if file then
        local content = file:read("*all")
        file:close()
        local success, data = pcall(hs.json.decode, content)
        if success and data then
            config = data
        end
    end
end

-- Save configuration to file
local function saveConfig()
    local file = io.open(configFile, "w")
    if file then
        file:write(hs.json.encode(config))
        file:close()
    end
end

-- HTML content for settings webview
local function getSettingsHTML()
    local directoriesJSON = hs.json.encode(config.directories or {})
    return [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Code Count Settings</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 700px;
            margin: 0 auto;
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        .directory-item {
            display: flex;
            align-items: center;
            margin: 10px 0;
            padding: 15px;
            background: #f8f9fa;
            border-radius: 6px;
            border-left: 4px solid #007AFF;
            cursor: move;
        }
        .directory-item:hover {
            background: #e9ecef;
        }
        .directory-item.dragging {
            opacity: 0.5;
        }
        .directory-path {
            font-family: monospace;
            font-size: 14px;
            color: #333;
            flex: 1;
            margin-right: 10px;
        }
        .directory-controls {
            display: flex;
            gap: 5px;
        }
        .btn {
            background: #007AFF;
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
        }
        .btn:hover {
            background: #0051D5;
        }
        .btn.remove {
            background: #FF3B30;
        }
        .btn.remove:hover {
            background: #D70015;
        }
        .btn.up, .btn.down {
            background: #34C759;
        }
        .btn.up:hover, .btn.down:hover {
            background: #28A745;
        }
        .add-section {
            margin-top: 20px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 6px;
        }
        .add-controls {
            display: flex;
            gap: 10px;
            margin-bottom: 10px;
        }
        input[type="text"] {
            flex: 1;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        .save-section {
            margin-top: 20px;
            text-align: center;
            padding: 20px;
            background: #e8f4fd;
            border-radius: 6px;
        }
        .empty-state {
            text-align: center;
            padding: 40px;
            color: #666;
        }
        .drag-handle {
            color: #999;
            margin-right: 10px;
            cursor: move;
        }
        .save-status {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 10px 15px;
            border-radius: 6px;
            color: white;
            font-weight: bold;
            z-index: 1000;
            transform: translateX(100%);
            transition: transform 0.3s ease;
        }
        .save-status.show {
            transform: translateX(0);
        }
        .save-status.success {
            background: #28A745;
        }
        .save-status.error {
            background: #DC3545;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 Code Count Settings</h1>
        <h3>Configured Directories</h3>
        <div id="directories">
            <!-- Directories will be populated here -->
        </div>
        
        <div class="add-section">
            <h3>Add New Directory</h3>
            <div class="add-controls">
                <input type="text" id="newDirectory" placeholder="/path/to/your/code/directory">
                <button class="btn" onclick="addDirectory()">Add</button>
            </div>
            <small>Enter a path manually or use "Add Directory" from the menu bar to browse</small>
        </div>
        
        <div class="save-section">
            <button class="btn" style="background: #28A745; font-size: 16px; padding: 12px 24px;" onclick="saveSettings()">💾 Save All Changes</button>
            <p style="margin-top: 10px; font-size: 12px; color: #666;">
                Changes to directory order and removal are automatically saved when you click Save.
            </p>
        </div>
    </div>
    
    <div id="saveStatus" class="save-status">
        Changes saved!
    </div>

    <script>
        let directories = ]] .. directoriesJSON .. [[;
        let draggedIndex = -1;

        function renderDirectories() {
            const container = document.getElementById('directories');
            container.innerHTML = '';
            
            if (directories.length === 0) {
                container.innerHTML = '<div class="empty-state"><p>No directories configured.</p><p>Add some directories below to get started.</p></div>';
                return;
            }
            
            directories.forEach((dir, index) => {
                const item = document.createElement('div');
                item.className = 'directory-item';
                item.draggable = true;
                item.dataset.index = index;
                item.innerHTML = `
                    <span class="drag-handle">⋮⋮</span>
                    <div class="directory-path">${dir}</div>
                    <div class="directory-controls">
                        <button class="btn up" onclick="moveUp(${index})" ${index === 0 ? 'disabled' : ''}>↑</button>
                        <button class="btn down" onclick="moveDown(${index})" ${index === directories.length - 1 ? 'disabled' : ''}>↓</button>
                        <button class="btn remove" onclick="removeDirectory(${index})">Remove</button>
                    </div>
                `;
                
                // Add drag and drop event listeners
                item.addEventListener('dragstart', handleDragStart);
                item.addEventListener('dragover', handleDragOver);
                item.addEventListener('drop', handleDrop);
                item.addEventListener('dragend', handleDragEnd);
                
                container.appendChild(item);
            });
        }

        function addDirectory() {
            const input = document.getElementById('newDirectory');
            const path = input.value.trim();
            if (path && !directories.includes(path)) {
                directories.push(path);
                input.value = '';
                renderDirectories();
                autoSave(); // Auto-save when adding
            } else if (directories.includes(path)) {
                alert('This directory is already in the list.');
            } else {
                alert('Please enter a valid directory path.');
            }
        }

        function removeDirectory(index) {
            if (confirm('Remove this directory from the list?')) {
                directories.splice(index, 1);
                renderDirectories();
                autoSave(); // Auto-save when removing
            }
        }

        function moveUp(index) {
            if (index > 0) {
                const temp = directories[index];
                directories[index] = directories[index - 1];
                directories[index - 1] = temp;
                renderDirectories();
                autoSave(); // Auto-save when reordering
            }
        }

        function moveDown(index) {
            if (index < directories.length - 1) {
                const temp = directories[index];
                directories[index] = directories[index + 1];
                directories[index + 1] = temp;
                renderDirectories();
                autoSave(); // Auto-save when reordering
            }
        }

        // Drag and drop functionality
        function handleDragStart(e) {
            draggedIndex = parseInt(e.target.dataset.index);
            e.target.classList.add('dragging');
        }

        function handleDragOver(e) {
            e.preventDefault();
        }

        function handleDrop(e) {
            e.preventDefault();
            const dropIndex = parseInt(e.target.closest('.directory-item').dataset.index);
            
            if (draggedIndex !== dropIndex && draggedIndex !== -1) {
                const draggedItem = directories[draggedIndex];
                directories.splice(draggedIndex, 1);
                directories.splice(dropIndex, 0, draggedItem);
                renderDirectories();
                autoSave(); // Auto-save when drag/drop reordering
            }
        }

        function handleDragEnd(e) {
            e.target.classList.remove('dragging');
            draggedIndex = -1;
        }

        function saveSettings() {
            // Store in localStorage for Hammerspoon to read
            localStorage.setItem('codeCountDirectories', JSON.stringify(directories));
            localStorage.setItem('codeCountSaveTimestamp', Date.now().toString());
            
            // Also trigger a custom event that Hammerspoon can listen for
            const event = new CustomEvent('saveSettings', {
                detail: { directories: directories }
            });
            window.dispatchEvent(event);
            
            showSaveStatus('Settings saved successfully! Menubar will update.', 'success');
        }
        
        function autoSave() {
            // Automatically save changes without showing alert
            localStorage.setItem('codeCountDirectories', JSON.stringify(directories));
            localStorage.setItem('codeCountSaveTimestamp', Date.now().toString());
            
            // Trigger event for Hammerspoon
            const event = new CustomEvent('saveSettings', {
                detail: { directories: directories }
            });
            window.dispatchEvent(event);
            
            // Visual feedback that changes are auto-saved
            showSaveStatus('Changes auto-saved', 'success');
            console.log('Auto-saved directory changes');
        }
        
        function showSaveStatus(message, type) {
            const status = document.getElementById('saveStatus');
            status.textContent = message;
            status.className = 'save-status ' + type;
            status.classList.add('show');
            
            setTimeout(() => {
                status.classList.remove('show');
            }, 3000);
        }

        // Initial render
        renderDirectories();
        
        // Handle Enter key in input
        document.getElementById('newDirectory').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                addDirectory();
            }
        });
    </script>
</body>
</html>
    ]]
end

-- Settings webview
local settingsWebview = nil

-- Open settings window
local function openSettings()
    print("Opening settings window...")
    
    if settingsWebview then
        print("Closing existing settings window")
        settingsWebview:delete()
        settingsWebview = nil
    end
    
    local success, webview = pcall(function()
        return hs.webview.new({x = 100, y = 100, w = 750, h = 600})
    end)
    
    if not success then
        print("Error creating webview:", webview)
        hs.notify.new({title="Code Count", informativeText="Error opening settings"}):send()
        return
    end
    
    settingsWebview = webview
    
    -- Configure webview step by step
    settingsWebview:windowTitle("Code Count Settings")
    settingsWebview:allowTextEntry(true)
    
    -- Try to set window style - some versions might not support all options
    local styleSuccess = pcall(function()
        settingsWebview:windowStyle({"closable", "titled"})
    end)
    if not styleSuccess then
        print("Warning: Could not set window style")
    end
    
    settingsWebview:closeOnEscape(true)
    
    -- Load HTML content
    local htmlContent = getSettingsHTML()
    settingsWebview:html(htmlContent)
    
    -- Initialize the lastSaveTimestamp when opening settings
    local lastSaveTimestamp = 0
    
    -- Set up a timer to check for settings updates from the webview
    local lastSaveTimestamp = 0
    local settingsTimer = hs.timer.new(0.3, function()
        if settingsWebview then
            settingsWebview:evaluateJavaScript([[
                const saved = localStorage.getItem('codeCountDirectories');
                const timestamp = localStorage.getItem('codeCountSaveTimestamp');
                JSON.stringify({directories: saved, timestamp: timestamp});
            ]], function(result)
                if result then
                    local success, data = pcall(hs.json.decode, result)
                    if success and data and data.directories and data.directories ~= '[]' and data.timestamp then
                        local timestamp = tonumber(data.timestamp)
                        if timestamp and timestamp > lastSaveTimestamp then
                            lastSaveTimestamp = timestamp
                            
                            local newDirSuccess, newDirectories = pcall(hs.json.decode, data.directories)
                            if newDirSuccess and newDirectories then
                                -- Check if directories have changed
                                local changed = false
                                if #newDirectories ~= #config.directories then
                                    changed = true
                                else
                                    for i, dir in ipairs(newDirectories) do
                                        if config.directories[i] ~= dir then
                                            changed = true
                                            break
                                        end
                                    end
                                end
                                
                                if changed then
                                    print("Settings updated from webview:", hs.inspect(newDirectories))
                                    config.directories = newDirectories
                                    saveConfig()
                                    updateMenubar()
                                    print("Configuration saved and menubar updated")
                                    hs.notify.new({
                                        title="Code Count", 
                                        informativeText="Settings updated - " .. #newDirectories .. " directories configured",
                                        hasActionButton=false
                                    }):send()
                                end
                            end
                        end
                    end
                end
            end)
        else
            -- Stop timer if webview is closed
            settingsTimer:stop()
        end
    end)
    
    -- Set up close callback to stop timer
    settingsWebview:windowCallback(function(action, webView)
        if action == "closing" then
            settingsTimer:stop()
            settingsWebview = nil
        end
    end)
    
    -- Show the window and start monitoring
    settingsWebview:show()
    settingsTimer:start()
    
    print("Settings window created and shown")
end

-- Function to add directory via dialog (called from menu)
local function addDirectoryDialog()
    local result = hs.dialog.chooseFileOrFolder("Choose directory to count:", os.getenv("HOME"), false, true, false, {}, false)
    
    -- Debug: print the entire result structure
    print("Dialog result:", hs.inspect(result))
    
    if result then
        local path = nil
        
        -- Try different possible result structures
        if result["1"] then
            path = result["1"]
            print("Found path via string index:", path)
        elseif result[1] then
            path = result[1]
            print("Found path via numeric index:", path)
        elseif result.hasDroppedFiles and result.files and #result.files > 0 then
            path = result.files[1]
            print("Found path via files array:", path)
        elseif type(result) == "string" then
            path = result
            print("Found path as direct string:", path)
        elseif result.file then
            path = result.file
            print("Found path via file property:", path)
        end
        
        if path then
            -- If settings window is open, populate the text field instead of adding directly
            if settingsWebview then
                settingsWebview:evaluateJavaScript(string.format([[
                    document.getElementById('newDirectory').value = '%s';
                    document.getElementById('newDirectory').focus();
                ]], path:gsub("'", "\\'")))
                hs.notify.new({title="Code Count", informativeText="Directory path added to settings form"}):send()
                return
            end
            
            -- Otherwise, add directly if not already in list
            if not hs.fnutils.contains(config.directories, path) then
                table.insert(config.directories, path)
                saveConfig()
                updateMenubar()
                hs.notify.new({title="Code Count", informativeText="Directory added: " .. path}):send()
                print("Directory added:", path)
            else
                hs.notify.new({title="Code Count", informativeText="Directory already exists"}):send()
            end
        else
            print("Could not extract path from result")
        end
    else
        print("No directory selected or dialog cancelled")
    end
end

-- Function to remove directory (called from menu)
local function removeDirectoryDialog()
    if #config.directories == 0 then
        hs.notify.new({title="Code Count", informativeText="No directories configured"}):send()
        return
    end
    
    local choices = {}
    for i, dir in ipairs(config.directories) do
        table.insert(choices, {
            text = dir,
            subText = "Click to remove this directory",
            uuid = tostring(i)
        })
    end
    
    local chooser = hs.chooser.new(function(choice)
        if choice then
            local index = tonumber(choice.uuid)
            local removedDir = config.directories[index]
            table.remove(config.directories, index)
            saveConfig()
            updateMenubar()
            hs.notify.new({title="Code Count", informativeText="Directory removed: " .. removedDir}):send()
            print("Directory removed:", removedDir)
            
            -- If settings window is open, refresh it
            if settingsWebview then
                settingsWebview:html(getSettingsHTML())
            end
        end
    end)
    
    chooser:choices(choices)
    chooser:placeholderText("Select directory to remove...")
    chooser:show()
end

-- Function to count all directories
local function countAllDirectories()
    if not config or not config.directories or #config.directories == 0 then
        hs.notify.new({title="Code Count", informativeText="No directories configured"}):send()
        return
    end
    
    -- Limit to reasonable number of directories to prevent crashes
    if #config.directories > 10 then
        hs.notify.new({
            title="Code Count", 
            informativeText="Too many directories (" .. #config.directories .. "). Please use individual counts.",
            hasActionButton=false
        }):send()
        return
    end
    
    hs.notify.new({title="Code Count", informativeText="Counting " .. #config.directories .. " git repositories..."}):send()
    print("Starting count for all directories (git-tracked files only)...")
    
    -- Clear previous results
    latestResults = {}
    
    local currentIndex = 1
    local totalDirectories = #config.directories
    
    -- Process directories one by one using a timer to prevent blocking
    local countTimer = hs.timer.new(0.5, function()
        if currentIndex > totalDirectories then
            -- All done
            countTimer:stop()
            hs.notify.new({
                title="Code Count Complete", 
                informativeText="Counted " .. totalDirectories .. " directories. Check Results for details.",
                hasActionButton=false
            }):send()
            print("Finished counting all directories")
            return
        end
        
        local dir = config.directories[currentIndex]
        local dirName = dir:match("([^/]+)$") or dir
        print("=== DEBUG: Async counting (" .. currentIndex .. "/" .. totalDirectories .. "):", dir)
        
        -- Safety check: multiple layers of protection
        print("DEBUG: Starting comprehensive safety checks for async count")
        
        -- Check 1: Is it a git repository?
        local gitCheckCommand = string.format("cd '%s' && git rev-parse --is-inside-work-tree 2>/dev/null", dir)
        local isGitRepo = hs.execute(gitCheckCommand)
        print("DEBUG: Git repo check:", isGitRepo and isGitRepo:gsub("\n", "") or "not a git repo")
        
        if not isGitRepo or isGitRepo:gsub("\n", "") ~= "true" then
            print("DEBUG: Not a git repository, skipping async")
            latestResults[dir] = {
                name = dirName,
                path = dir,
                error = "Not a git repository. Only git repositories are supported for safety.",
                timestamp = os.date("%Y-%m-%d %H:%M:%S")
            }
            currentIndex = currentIndex + 1
            return
        end
        
        -- Check 2: Count git-tracked files with timeout
        local fileCountCommand = string.format("cd '%s' && timeout 10 git ls-files 2>/dev/null | wc -l", dir)
        local fileCountOutput = hs.execute(fileCountCommand)
        local fileCount = tonumber(fileCountOutput)
        print("DEBUG: Git tracked files count:", fileCount or "failed to count")
        
        -- Check 3: Git-tracked files size check with timeout
        local sizeCheckCommand = string.format("cd '%s' && timeout 10 git ls-files -z 2>/dev/null | xargs -0 du -cm 2>/dev/null | tail -1 | cut -f1", dir)
        local sizeOutput = hs.execute(sizeCheckCommand)
        local repoSizeMB = tonumber(sizeOutput)
        print("DEBUG: Git-tracked files size:", repoSizeMB and (repoSizeMB .. "MB") or "unknown")
        
        -- Stricter thresholds for batch processing
        local maxFiles = 3000  -- More conservative for batch
        local maxSizeMB = 200  -- More conservative for batch
        
        if fileCount and fileCount > maxFiles then
            print("DEBUG: Repository too large for batch processing - file count exceeded")
            latestResults[dir] = {
                name = dirName,
                path = dir,
                error = "Repository too large (" .. fileCount .. " files > " .. maxFiles .. " limit). Use individual count for large repos.",
                timestamp = os.date("%Y-%m-%d %H:%M:%S")
            }
            currentIndex = currentIndex + 1
            return
        end
        
        if repoSizeMB and repoSizeMB > maxSizeMB then
            print("DEBUG: Repository too large for batch processing - git-tracked size exceeded")
            latestResults[dir] = {
                name = dirName,
                path = dir,
                error = "Git-tracked files too large (" .. repoSizeMB .. "MB > " .. maxSizeMB .. "MB limit). Use individual count for large repos.",
                timestamp = os.date("%Y-%m-%d %H:%M:%S")
            }
            currentIndex = currentIndex + 1
            return
        end
        
        -- Show progress notification with debug info
        if fileCount then
            hs.notify.new({
                title="Code Count Progress", 
                informativeText="Processing " .. dirName .. " (" .. currentIndex .. "/" .. totalDirectories .. ") - " .. fileCount .. " files"
            }):send()
        else
            hs.notify.new({
                title="Code Count Progress", 
                informativeText="Processing " .. dirName .. " (" .. currentIndex .. "/" .. totalDirectories .. ")"
            }):send()
        end
        
        -- Run cloc with VCS integration for optimal performance (async version)
        print("DEBUG: Starting async cloc command with VCS integration for:", dir)
        local command = string.format(
            "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH && " ..
            "cd '%s' && " ..
            "timeout 30 cloc " ..
            "--vcs=git " ..
            "--exclude-ext=lock,log,cache,tmp,map,min.js,min.css,bundle.js,bundle.css,d.ts " ..
            "--ignore-whitespace " ..
            "--max-file-size=0.5 " ..
            "--progress-rate=0 " ..
            "--quiet " ..
            "--csv " ..
            "2>&1", 
            dir
        )
        print("DEBUG: Async command:", command)
        
        local startTime = os.time()
        local output, status = hs.execute(command)
        local endTime = os.time()
        local duration = endTime - startTime
        
        print("DEBUG: Async command completed in", duration, "seconds")
        print("DEBUG: Async status:", status)
        print("DEBUG: Async output length:", output and #output or 0)
        
        if status and output and output ~= "" and not output:match("timeout") and not output:match("error") then
            print("DEBUG: Async processing successful output")
            
            -- Validate CSV output format
            local validCSV = false
            local lines = {}
            for line in output:gmatch("[^\r\n]+") do
                table.insert(lines, line)
                if line:match("^files,language,blank,comment,code") then
                    validCSV = true
                end
            end
            
            if not validCSV then
                print("DEBUG: Async invalid CSV format detected")
                latestResults[dir] = {
                    name = dirName,
                    path = dir,
                    error = "Invalid output format from cloc (async)",
                    timestamp = os.date("%Y-%m-%d %H:%M:%S")
                }
            else
                -- Store the raw CSV output for this directory
                latestResults[dir] = {
                    name = dirName,
                    path = dir,
                    csvOutput = output,
                    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                    duration = duration
                }
                
                -- Save CSV to Desktop/Counts directory
                local csvFile = saveCsvResult(dir, dirName, output, latestResults[dir].timestamp)
                if csvFile then
                    latestResults[dir].csvFile = csvFile
                end
                
                -- Parse for quick summary
                local totalLines = "No code found"
                for j = #lines, 1, -1 do
                    local line = lines[j]
                    if line:match("SUM,") then
                        local parts = {}
                        for part in line:gmatch("([^,]+)") do
                            table.insert(parts, part)
                        end
                        if #parts >= 5 then
                            totalLines = parts[5] .. " lines"
                            latestResults[dir].totalLines = parts[5]
                        end
                        break
                    end
                end
                
                print("DEBUG: Async result for " .. dir .. ": " .. totalLines)
            end
        else
            print("DEBUG: Async command failed or timed out")
            local errorMsg = "Failed to count or timeout (async)"
            if output and output:match("timeout") then
                errorMsg = "Timeout after 30 seconds (async)"
            elseif output and output:match("error") then
                errorMsg = "cloc error (async): " .. (output:match("error[^%s]*") or "unknown")
            elseif not status then
                errorMsg = "Command execution failed (async)"
            end
            
            latestResults[dir] = {
                name = dirName,
                path = dir,
                error = errorMsg,
                timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                duration = duration
            }
            print("DEBUG: Async failed to run cloc on:", dir, "Error:", errorMsg)
        end
        
        currentIndex = currentIndex + 1
    end)
    
    countTimer:start()
end

-- Generate HTML for results view
local function getResultsHTML()
    -- Helper function to format numbers with commas
    local function formatNumber(num)
        local formatted = tostring(num)
        while true do
            local k
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then
                break
            end
        end
        return formatted
    end
    
    local html = [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Code Count Results</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
            margin: 20px; 
            background: #f5f5f5; 
        }
        .container { 
            max-width: 1000px; 
            margin: 0 auto; 
            background: white; 
            padding: 20px; 
            border-radius: 8px; 
            box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
        }
        h1 { 
            color: #333; 
            border-bottom: 2px solid #007AFF; 
            padding-bottom: 10px; 
        }
        .summary { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 15px; 
            margin-bottom: 30px; 
        }
        .summary-card { 
            background: #f8f9fa; 
            padding: 15px; 
            border-radius: 6px; 
            border-left: 4px solid #007AFF; 
        }
        .summary-card h3 { 
            margin: 0 0 5px 0; 
            font-size: 14px; 
            color: #666; 
        }
        .summary-card .value { 
            font-size: 24px; 
            font-weight: bold; 
            color: #333; 
        }
        .directory { 
            border: 1px solid #ddd; 
            border-radius: 6px; 
            margin-bottom: 20px; 
            overflow: hidden; 
        }
        .directory-header { 
            background: #f8f9fa; 
            padding: 15px; 
            border-bottom: 1px solid #ddd; 
            font-weight: bold; 
        }
        .directory-path { 
            font-size: 12px; 
            color: #666; 
            margin-top: 5px; 
        }
        .directory-content { 
            padding: 15px; 
        }
        .csv-table { 
            width: 100%; 
            border-collapse: collapse; 
            font-size: 12px; 
        }
        .csv-table th, .csv-table td { 
            border: 1px solid #ddd; 
            padding: 8px; 
            text-align: left; 
        }
        .csv-table th { 
            background: #f8f9fa; 
            font-weight: bold; 
        }
        .csv-table .sum-row { 
            background: #e8f4f8; 
            font-weight: bold; 
        }
        .error { 
            color: #dc3545; 
            font-style: italic; 
        }
        .timestamp { 
            font-size: 11px; 
            color: #999; 
            text-align: right; 
        }
        .no-results { 
            text-align: center; 
            color: #666; 
            font-style: italic; 
            padding: 40px; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 Code Count Results</h1>
        ]]
    
    if not latestResults or not next(latestResults) then
        html = html .. [[
        <div class="no-results">
            <p>No results available.</p>
            <p>Use "Count All" from the menu bar to generate results.</p>
        </div>
        ]]
    else
        -- Calculate summary stats
        local totalDirectories = 0
        local totalLines = 0
        local totalFiles = 0
        local errorCount = 0
        
        for _, result in pairs(latestResults) do
            totalDirectories = totalDirectories + 1
            if result.error then
                errorCount = errorCount + 1
            elseif result.totalLines then
                totalLines = totalLines + tonumber(result.totalLines)
            end
        end
        
        -- Add summary cards
        html = html .. string.format([[
        <div class="summary">
            <div class="summary-card">
                <h3>Total Directories</h3>
                <div class="value">%d</div>
            </div>
            <div class="summary-card">
                <h3>Total Lines of Code</h3>
                <div class="value">%s</div>
            </div>
            <div class="summary-card">
                <h3>Errors</h3>
                <div class="value">%d</div>
            </div>
        </div>
        ]], totalDirectories, formatNumber(totalLines), errorCount)
        
        -- Add detailed results for each directory
        for path, result in pairs(latestResults) do
            html = html .. string.format([[
            <div class="directory">
                <div class="directory-header">
                    %s
                    <div class="directory-path">%s</div>
                    <div class="timestamp">%s%s</div>
                </div>
                <div class="directory-content">
            ]], result.name, result.path, result.timestamp, 
            result.loaded and " (loaded from file)" or "",
            result.csvFile and (" • <a href=\"file://" .. result.csvFile .. "\">Open CSV</a>") or "")
            
            if result.error then
                html = html .. string.format('<div class="error">%s</div>', result.error)
            elseif result.csvOutput then
                -- Parse and display CSV as table
                html = html .. [[
                <table class="csv-table">
                    <thead>
                        <tr>
                            <th>Files</th>
                            <th>Language</th>
                            <th>Blank Lines</th>
                            <th>Comments</th>
                            <th>Code Lines</th>
                        </tr>
                    </thead>
                    <tbody>
                ]]
                
                local lines = {}
                for line in result.csvOutput:gmatch("[^\r\n]+") do
                    table.insert(lines, line)
                end
                
                for i, line in ipairs(lines) do
                    if line:match("^%d") or line:match("SUM,") then
                        local parts = {}
                        for part in line:gmatch("([^,]+)") do
                            table.insert(parts, part)
                        end
                        
                        if #parts >= 5 then
                            local rowClass = line:match("SUM,") and " class=\"sum-row\"" or ""
                            html = html .. string.format([[
                            <tr%s>
                                <td>%s</td>
                                <td>%s</td>
                                <td>%s</td>
                                <td>%s</td>
                                <td>%s</td>
                            </tr>
                            ]], rowClass, parts[1], parts[2], parts[3], parts[4], parts[5])
                        end
                    end
                end
                
                html = html .. [[
                    </tbody>
                </table>
                ]]
            end
            
            html = html .. [[
                </div>
            </div>
            ]]
        end
    end
    
    html = html .. [[
    </div>
</body>
</html>
    ]]
    
    return html
end

-- Function to open results web view
local resultsWebview = nil

local function openResults()
    if resultsWebview then
        resultsWebview:show()
        return
    end
    
    resultsWebview = hs.webview.new({x=100, y=100, w=800, h=600})
    resultsWebview:windowTitle("Code Count Results")
    resultsWebview:allowTextEntry(true)
    
    -- Try to set window style - some versions might not support all options
    local styleSuccess = pcall(function()
        resultsWebview:windowStyle({"closable", "titled", "resizable"})
    end)
    if not styleSuccess then
        print("Warning: Could not set window style for results")
    end
    
    resultsWebview:closeOnEscape(true)
    resultsWebview:html(getResultsHTML())
    resultsWebview:show()
    
    -- Close webview when window is closed
    resultsWebview:windowCallback(function(action)
        if action == "closing" then
            resultsWebview = nil
        end
    end)
end

-- Menu bar setup
local menubar = hs.menubar.new()

updateMenubar = function()
    if not menubar then
        print("Menubar not initialized")
        return
    end
    
    if not clocAvailable then
        menubar:setTitle("⚠️")
        menubar:setTooltip("Code Count - cloc not available")
        menubar:setMenu({
            { title = "cloc not installed", disabled = true },
            { title = "Install with: brew install cloc", disabled = true },
            { title = "-" },
            { title = "Add Directory", fn = addDirectoryDialog },
            { title = "Remove Directory", fn = removeDirectoryDialog },
            { title = "-" },
            { title = "Settings", fn = function() 
                print("Settings menu item clicked")
                openSettings() 
            end }
        })
        return
    end
    
    menubar:setTitle("📊")
    menubar:setTooltip("Code Count")
    
    local menuItems = {
        { title = "Add Directory", fn = addDirectoryDialog },
        { title = "Remove Directory", fn = removeDirectoryDialog },
        { title = "-" },
        { title = "Settings", fn = function() 
            print("Settings menu item clicked")
            openSettings() 
        end },
        { title = "Results", fn = function()
            print("Results menu item clicked")
            openResults()
        end },
        { title = "-" },
        { title = "Count All", fn = function()
            countAllDirectories()
        end },
        { title = "-" },
        { title = "About Code Count", disabled = true }
    }
    
    -- Add directory counts if available
    if config and config.directories and #config.directories > 0 then
        table.insert(menuItems, 6, { title = "-" })
        table.insert(menuItems, 7, { title = "📁 Directories:", disabled = true })
        for _, dir in ipairs(config.directories) do
            local dirName = dir:match("([^/]+)$") or dir -- Get just the directory name
            table.insert(menuItems, 8, { 
                title = "   " .. dirName, 
                fn = function() 
                    -- Wrap everything in pcall for crash protection
                    local success, err = pcall(function()
                        -- Execute cloc command for this directory
                        hs.notify.new({title="Code Count", informativeText="Starting count for " .. dirName}):send()
                        print("=== CRASH DEBUG: Starting count for:", dir)
                        
                        -- Basic directory existence check first
                        local dirCheck = hs.execute("test -d '" .. dir .. "' && echo 'exists' || echo 'missing'")
                        print("CRASH DEBUG: Directory exists check:", dirCheck and dirCheck:gsub("\n", "") or "failed")
                        
                        if not dirCheck or dirCheck:gsub("\n", "") ~= "exists" then
                            print("CRASH DEBUG: Directory does not exist, aborting")
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = "Directory does not exist: " .. dir,
                                timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            }
                            hs.notify.new({
                                title="Code Count - Error", 
                                informativeText="Directory not found: " .. dirName,
                                hasActionButton=false
                            }):send()
                            return
                        end
                        
                        print("CRASH DEBUG: Directory exists, proceeding with safety checks")
                    
                        -- Safety check: multiple layers of protection
                        print("CRASH DEBUG: Starting comprehensive safety checks")
                        
                        -- Check 1: Is it a git repository? (with improved detection)
                        local gitCheckCommand = string.format("cd \"%s\" && test -d .git && echo \"git-dir\" || (git rev-parse --git-dir >/dev/null 2>&1 && echo \"git-repo\" || echo \"not-git\")", dir)
                        print("CRASH DEBUG: Git check command:", gitCheckCommand)
                        
                        local isGitRepo = nil
                        local gitSuccess, gitResult = pcall(function()
                            return hs.execute(gitCheckCommand)
                        end)
                        
                        if gitSuccess and gitResult then
                            isGitRepo = gitResult:gsub("%s+", ""):gsub("\n", "")
                            print("CRASH DEBUG: Git repo check result: '" .. (isGitRepo or "empty") .. "'")
                        else
                            print("CRASH DEBUG: Git check failed:", gitResult or "unknown error")
                            isGitRepo = "not-git"
                        end
                        
                        -- Accept both git-dir (has .git folder) and git-repo (is in git working tree)
                        if not isGitRepo or (isGitRepo ~= "git-dir" and isGitRepo ~= "git-repo") then
                            print("CRASH DEBUG: Not a git repository, result was:", isGitRepo or "nil")
                            
                            -- Try one more alternative check for debugging
                            local altCheck = hs.execute(string.format("cd \"%s\" && ls -la | grep -E '^\\.git' | head -1", dir))
                            print("CRASH DEBUG: Alternative git check (ls -la):", altCheck and altCheck:gsub("\n", "") or "no .git found")
                            
                            -- Offer fallback option to count anyway (with warning)
                            print("CRASH DEBUG: Attempting fallback count for non-git directory")
                            hs.notify.new({
                                title="Code Count - Warning", 
                                informativeText=dirName .. " is not a git repo - counting all files (risky)",
                                hasActionButton=false
                            }):send()
                            
                            -- Use fallback counting method
                            local fallbackSuccess, fallbackResult = pcall(function()
                                local command = string.format(
                                    "cd \"%s\" && " ..
                                    "timeout 20 cloc " ..
                                    "--exclude-dir=node_modules,vendor,.git,build,dist,target,bin,obj,.next,.nuxt,coverage,logs,tmp,temp,.cache,.npm,.yarn,bower_components,public/assets,assets/vendor " ..
                                    "--exclude-ext=lock,log,cache,tmp,map,min.js,min.css,bundle.js,bundle.css,d.ts " ..
                                    "--ignore-whitespace " ..
                                    "--max-file-size=0.5 " ..
                                    "--progress-rate=0 " ..
                                    "--quiet " ..
                                    "--csv " ..
                                    ". 2>&1", 
                                    dir
                                )
                                print("CRASH DEBUG: Fallback cloc command:", command)
                                
                                local startTime = os.time()
                                local output = hs.execute(command)
                                local endTime = os.time()
                                local duration = endTime - startTime
                                
                                return {
                                    output = output,
                                    duration = duration,
                                    success = true
                                }
                            end)
                            
                            if fallbackSuccess and fallbackResult and fallbackResult.output then
                                print("CRASH DEBUG: Fallback count succeeded")
                                -- Process the fallback result similar to git repos
                                local lines = {}
                                for line in fallbackResult.output:gmatch("[^\r\n]+") do
                                    table.insert(lines, line)
                                end
                                
                                local totalLines = "No code found"
                                for i = #lines, 1, -1 do
                                    local line = lines[i]
                                    if line:match("SUM,") then
                                        local parts = {}
                                        for part in line:gmatch("([^,]+)") do
                                            table.insert(parts, part)
                                        end
                                        if #parts >= 5 then
                                            local codeLines = parts[5]
                                            totalLines = codeLines .. " lines of code"
                                            
                                            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
                                            
                                            latestResults[dir] = {
                                                name = dirName,
                                                path = dir,
                                                csvOutput = fallbackResult.output,
                                                totalLines = codeLines,
                                                timestamp = timestamp,
                                                duration = fallbackResult.duration,
                                                warning = "Non-git repository - counted all files"
                                            }
                                            
                                            -- Save CSV to Desktop/Counts directory
                                            local csvFile = saveCsvResult(dir, dirName, fallbackResult.output, timestamp)
                                            if csvFile then
                                                latestResults[dir].csvFile = csvFile
                                            end
                                            
                                            hs.notify.new({
                                                title="Code Count - " .. dirName, 
                                                informativeText=totalLines .. " (non-git, " .. fallbackResult.duration .. "s)",
                                                hasActionButton=false
                                            }):send()
                                            return
                                        end
                                        break
                                    end
                                end
                            end
                            
                            -- If fallback also failed
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = "Not a git repository and fallback count failed.",
                                timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            }
                            hs.notify.new({
                                title="Code Count - Failed", 
                                informativeText="Failed to count " .. dirName .. " (not git repo)",
                                hasActionButton=false
                            }):send()
                            return
                        end
                        
                        print("CRASH DEBUG: Git repository confirmed, proceeding with file count")
                    
                        -- Check 2: Count git-tracked files (with improved error handling)
                        local fileCount = nil
                        local fileCountSuccess, fileCountResult = pcall(function()
                            local fileCountCommand = string.format("cd \"%s\" && git ls-files 2>/dev/null | wc -l || echo \"0\"", dir)
                            print("CRASH DEBUG: File count command:", fileCountCommand)
                            return hs.execute(fileCountCommand)
                        end)
                        
                        if fileCountSuccess and fileCountResult then
                            local cleanResult = fileCountResult:gsub("%s+", ""):gsub("\n", "")
                            fileCount = tonumber(cleanResult)
                            print("CRASH DEBUG: Git tracked files count:", fileCount or ("parse failed from: '" .. cleanResult .. "'"))
                        else
                            print("CRASH DEBUG: File count failed:", fileCountResult or "unknown error")
                            fileCount = 0  -- Default to 0 if we can't count
                        end
                        
                        -- Check 3: Repository size check (with improved error handling - git-tracked files only)
                        local repoSizeMB = nil
                        local sizeSuccess, sizeResult = pcall(function()
                            -- Only measure size of git-tracked files, not entire repo (avoids node_modules, etc.)
                            local sizeCheckCommand = string.format("cd \"%s\" && git ls-files -z 2>/dev/null | xargs -0 du -cm 2>/dev/null | tail -1 | cut -f1 || echo \"0\"", dir)
                            print("CRASH DEBUG: Size check command (git-tracked only):", sizeCheckCommand)
                            return hs.execute(sizeCheckCommand)
                        end)
                        
                        if sizeSuccess and sizeResult then
                            local cleanResult = sizeResult:gsub("%s+", ""):gsub("\n", "")
                            repoSizeMB = tonumber(cleanResult)
                            print("CRASH DEBUG: Git-tracked files size:", repoSizeMB and (repoSizeMB .. "MB") or ("parse failed from: '" .. cleanResult .. "'"))
                        else
                            print("CRASH DEBUG: Git-tracked size check failed:", sizeResult or "unknown error")
                            repoSizeMB = 0  -- Default to 0 if we can't measure
                        end
                    
                        -- Safety thresholds with more conservative limits
                        local maxFiles = 5000  -- Reduced from 8000
                        local maxSizeMB = 200  -- Reduced from 500
                        
                        print("CRASH DEBUG: Applying safety thresholds - maxFiles:", maxFiles, "maxSizeMB:", maxSizeMB)
                        
                        if fileCount and fileCount > maxFiles then
                            print("CRASH DEBUG: Repository too large - file count exceeded:", fileCount)
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = "Repository too large (" .. fileCount .. " files > " .. maxFiles .. " limit). Skipped for safety.",
                                timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            }
                            hs.notify.new({
                                title="Code Count - Skipped", 
                                informativeText=dirName .. " has too many files (" .. fileCount .. ")",
                                hasActionButton=false
                            }):send()
                            return
                        end
                        
                        if repoSizeMB and repoSizeMB > maxSizeMB then
                            print("CRASH DEBUG: Repository too large - git-tracked size exceeded:", repoSizeMB .. "MB")
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = "Git-tracked files too large (" .. repoSizeMB .. "MB > " .. maxSizeMB .. "MB limit). Skipped for safety.",
                                timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            }
                            hs.notify.new({
                                title="Code Count - Skipped", 
                                informativeText=dirName .. " is too large (" .. repoSizeMB .. "MB)",
                                hasActionButton=false
                            }):send()
                            return
                        end
                        
                        print("CRASH DEBUG: Safety checks passed - proceeding with cloc")
                        if fileCount then
                            hs.notify.new({
                                title="Code Count - Processing", 
                                informativeText=dirName .. " (" .. fileCount .. " files)",
                                hasActionButton=false
                            }):send()
                        else
                            hs.notify.new({
                                title="Code Count - Processing", 
                                informativeText=dirName .. " (unknown file count)",
                                hasActionButton=false
                            }):send()
                        end
                    
                        -- Run cloc with VCS integration for optimal performance
                        print("CRASH DEBUG: Starting cloc execution with VCS integration")
                        
                        local clocSuccess, clocResult = pcall(function()
                            -- Use a simpler command structure that's more reliable with hs.execute
                            local command = string.format(
                                "cd \"%s\" && " ..
                                "export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH && " ..
                                "timeout 30 cloc " ..
                                "--vcs=git " ..
                                "--exclude-ext=lock,log,cache,tmp,map,min.js,min.css,bundle.js,bundle.css,d.ts " ..
                                "--ignore-whitespace " ..
                                "--max-file-size=0.5 " ..
                                "--progress-rate=0 " ..
                                "--quiet " ..
                                "--csv",
                                dir
                            )
                            print("CRASH DEBUG: Cloc command:", command)
                            
                            local startTime = os.time()
                            local output = hs.execute(command)
                            local endTime = os.time()
                            local duration = endTime - startTime
                            
                            return {
                                output = output,
                                duration = duration,
                                success = true
                            }
                        end)
                        
                        if not clocSuccess then
                            print("CRASH DEBUG: Cloc execution failed with error:", clocResult or "unknown")
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = "Cloc execution crashed: " .. (clocResult or "unknown error"),
                                timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            }
                            hs.notify.new({
                                title="Code Count - Crashed", 
                                informativeText="Cloc crashed for " .. dirName,
                                hasActionButton=false
                            }):send()
                            return
                        end
                        
                        local output = clocResult.output
                        local duration = clocResult.duration
                        
                        print("CRASH DEBUG: Cloc completed in", duration, "seconds")
                        print("CRASH DEBUG: Output length:", output and #output or 0)
                    
                        -- Process cloc output with crash protection
                        local processSuccess, processResult = pcall(function()
                            if output and #output > 0 and not output:match("timeout") then
                                print("CRASH DEBUG: Processing cloc output")
                                
                                -- Validate CSV output format
                                local validCSV = false
                                local lines = {}
                                for line in output:gmatch("[^\r\n]+") do
                                    table.insert(lines, line)
                                    if line:match("^files,language,blank,comment,code") then
                                        validCSV = true
                                    end
                                end
                                
                                if not validCSV then
                                    return {
                                        success = false,
                                        error = "Invalid CSV format from cloc"
                                    }
                                end
                                
                                -- Parse CSV for results
                                local totalLines = "No code found"
                                for i = #lines, 1, -1 do
                                    local line = lines[i]
                                    if line:match("SUM,") then
                                        local parts = {}
                                        for part in line:gmatch("([^,]+)") do
                                            table.insert(parts, part)
                                        end
                                        if #parts >= 5 then
                                            local codeLines = parts[5]
                                            totalLines = codeLines .. " lines of code"
                                            return {
                                                success = true,
                                                csvOutput = output,
                                                totalLines = totalLines,
                                                codeLines = codeLines,
                                                duration = duration
                                            }
                                        end
                                        break
                                    end
                                end
                                
                                return {
                                    success = true,
                                    csvOutput = output,
                                    totalLines = totalLines,
                                    duration = duration
                                }
                            else
                                return {
                                    success = false,
                                    error = output and output:match("timeout") and "Timeout after 30 seconds" or "No output from cloc"
                                }
                            end
                        end)
                        
                        if not processSuccess then
                            print("CRASH DEBUG: Output processing failed:", processResult or "unknown")
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = "Output processing crashed: " .. (processResult or "unknown error"),
                                timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            }
                            hs.notify.new({
                                title="Code Count - Processing Error", 
                                informativeText="Output processing failed for " .. dirName,
                                hasActionButton=false
                            }):send()
                            return
                        end
                        
                        -- Store results or error
                        if processResult.success then
                            print("CRASH DEBUG: Successfully processed result:", processResult.totalLines or "unknown")
                            
                            local timestamp = os.date("%Y-%m-%d %H:%M:%S")
                            
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                csvOutput = processResult.csvOutput,
                                timestamp = timestamp,
                                duration = processResult.duration
                            }
                            
                            if processResult.codeLines then
                                latestResults[dir].totalLines = processResult.codeLines
                            end
                            
                            -- Save CSV to Desktop/Counts directory
                            local csvFile = saveCsvResult(dir, dirName, processResult.csvOutput, timestamp)
                            if csvFile then
                                latestResults[dir].csvFile = csvFile
                            end
                            
                            hs.notify.new({
                                title="Code Count - " .. dirName, 
                                informativeText=(processResult.totalLines or "Completed") .. " (" .. processResult.duration .. "s)",
                                hasActionButton=false
                            }):send()
                            print("CRASH DEBUG: Result for " .. dir .. ": " .. (processResult.totalLines or "completed"))
                        else
                            print("CRASH DEBUG: Processing failed:", processResult.error)
                            latestResults[dir] = {
                                name = dirName,
                                path = dir,
                                error = processResult.error,
                                timestamp = os.date("%Y-%m-%d %H:%M:%S"),
                                duration = duration or 0
                            }
                            
                            hs.notify.new({
                                title="Code Count - Error", 
                                informativeText=processResult.error .. " for " .. dirName,
                                hasActionButton=false
                            }):send()
                        end
                        
                    end) -- End of main pcall
                    
                    if not success then
                        print("CRASH DEBUG: Main function crashed:", err or "unknown error")
                        hs.notify.new({
                            title="Code Count - CRASHED", 
                            informativeText="Main function crashed for " .. dirName .. ": " .. (err or "unknown error"),
                            hasActionButton=false
                        }):send()
                        
                        -- Store crash information
                        latestResults[dir] = {
                            name = dirName,
                            path = dir,
                            error = "CRASHED: " .. (err or "unknown error"),
                            timestamp = os.date("%Y-%m-%d %H:%M:%S")
                        }
                    end
                end 
            })
        end
    end
    
    menubar:setMenu(menuItems)
    print("Menubar updated with", config and config.directories and #config.directories or 0, "directories")
end

-- Load configuration and setup menubar
loadConfig()
loadPreviousResults()  -- Load previous CSV results from Desktop/Counts
updateMenubar()

-- Main application logic goes here
-- TODO: Implement code counting functionality
