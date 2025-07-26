# Code Count - Instant Project Metrics

> Built By Github Copiliot

## Problems This Solves

### Manual Code Analysis is Tedious
Running `cloc` commands manually every time you want to check project metrics is a pain. Remembering the right flags, navigating to the right directories, and formatting output takes time away from actual development work.

### No Quick Project Overview
When jumping between projects or reviewing codebases, you often need a quick snapshot of project size, language distribution, and complexity. Traditional tools require multiple commands and manual analysis.

### Missing Workflow Integration
Most code counting tools are standalone utilities that don't integrate with your development workflow. You want metrics **at your fingertips** without breaking your flow.

### The Solution
This Hammerspoon plugin puts powerful code analysis directly in your menu bar. **One click, instant insights.** No terminal commands, no context switching - just the metrics you need, when you need them.

## Features

- 📊 **Instant Code Metrics**: Get lines of code, file counts, and language breakdowns with one click
- 🎯 **Project-Aware**: Automatically detects and analyzes your current project directory
- 🏃‍♂️ **Lightning Fast**: Leverages `cloc` for accurate, fast analysis
- 📋 **Menu Bar Integration**: Access all functionality from your macOS menu bar
- ⌨️ **Keyboard Shortcuts**: Quick access via customizable hotkeys
- 📁 **Smart Directory Detection**: Intelligently finds project roots and excludes unnecessary files
- 🔄 **Real-time Updates**: Refresh metrics as your codebase evolves

## Installation

### Step 0: Clone the Repository

First, clone this repository to your local machine:

```bash
git clone <repository-url>
cd code-count
```

### Step 1: Install Homebrew

If you don't have Homebrew installed, run this command in Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Step 2: Install Hammerspoon

```bash
brew install hammerspoon
```

### Step 3: Install cloc

```bash
brew install cloc
```

### Step 4: Add to Hammerspoon Configuration

#### Basic Setup

1. Open Hammerspoon and go to the menu bar → Hammerspoon → Open Config
2. This will open your `~/.hammerspoon/init.lua` file
3. Add this line to import the code counter:

```lua
dofile(os.getenv("HOME") .. "/Code/code-count/init.lua")
```

#### Alternative Path Examples

**If you cloned to your home directory:**
```lua
dofile(os.getenv("HOME") .. "/code-count/init.lua")
```

**If you cloned to your Desktop:**
```lua
dofile(os.getenv("HOME") .. "/Desktop/code-count/init.lua")
```

**If you cloned to a Documents folder:**
```lua
dofile(os.getenv("HOME") .. "/Documents/code-count/init.lua")
```

**If you cloned to a specific path:**
```lua
dofile("/Users/yourusername/path/to/code-count/init.lua")
```

#### Advanced Configuration

**Multiple Hammerspoon Modules:**
```lua
-- Load code-count
dofile(os.getenv("HOME") .. "/Code/code-count/init.lua")

-- Load other Hammerspoon modules
require("your-other-module")
dofile(os.getenv("HOME") .. "/hammerspoon-configs/window-management.lua")
```

**Conditional Loading:**
```lua
-- Only load if the file exists
local code_count_path = os.getenv("HOME") .. "/Code/code-count/init.lua"
local file = io.open(code_count_path, "r")
if file then
    file:close()
    dofile(code_count_path)
    print("Code-count loaded successfully")
else
    print("Code-count not found at: " .. code_count_path)
end
```

**Error Handling:**
```lua
-- Load with error protection
local success, error_msg = pcall(function()
    dofile(os.getenv("HOME") .. "/Code/code-count/init.lua")
end)

if not success then
    hs.alert.show("Failed to load code-count: " .. tostring(error_msg), 3)
    print("Error loading code-count:", error_msg)
end
```

### Step 5: Configure and Reload

1. Save your Hammerspoon configuration
2. Reload Hammerspoon: menu bar → Hammerspoon → Reload Config
3. Look for the 📊 icon in your menu bar

## Usage

### Setting Up Your Directories

Before you can count code, you need to add the directories you want to analyze:

1. **Add Directories**: Click the 📊 icon in your menu bar
2. **Select Projects**: Choose "Add Directory" to add repositories/projects you want to track
3. **Build Your List**: Add all the directories you're interested in analyzing

### Counting Code

Once you have directories added, you have two options:

#### Count Individual Repositories
1. **Menu Bar**: Click the 📊 icon in your menu bar
2. **Select Specific Repo**: Click on any specific repository name in the menu
3. **Instant Analysis**: The tool will analyze that specific repository

#### Count All Repositories
1. **Menu Bar**: Click the 📊 icon in your menu bar
2. **Count All**: Select "Count All" to analyze all added directories at once
3. **Bulk Analysis**: This will run `cloc` on all your tracked repositories

### Viewing Results

After running either individual or bulk analysis:

1. **Access Results**: Click the 📊 icon → "Results"
2. **View Metrics**: See comprehensive LOC (Lines of Code) statistics for analyzed repositories
3. **Language Breakdown**: Review distribution across programming languages
4. **Compare Projects**: Compare metrics across different repositories

### Managing Your Directory List

Keep your tracked directories organized:

1. **Settings**: Click the 📊 icon → "Settings"
2. **Reorder Directories**: Change the order of repositories in your list
3. **Remove Directories**: Remove repositories you no longer want to track
4. **Customize Display**: Adjust how repositories appear in the menu

### Understanding Output

The results provide comprehensive metrics including:
- **Total Lines**: Blank, comment, and source lines per repository
- **File Counts**: Total files analyzed by language
- **Language Breakdown**: Distribution across programming languages
- **Project Comparison**: Side-by-side metrics across all tracked repositories

## Customization

### Modifying Excluded Directories

Edit the `init.lua` file to customize which directories are excluded:

```lua
local excluded_dirs = {
    "node_modules",
    ".git",
    "build",
    "dist",
    ".vscode",
    -- Add your custom exclusions here
}
```

### Custom File Extensions

Configure which file types to analyze:

```lua
local included_extensions = {
    "js", "ts", "py", "lua", "go", "rs",
    -- Add your preferred extensions
}
```

### Keyboard Shortcuts

Customize the hotkey in `init.lua`:

```lua
-- Change Cmd+Option+C to your preference
hs.hotkey.bind({"cmd", "alt"}, "c", function()
    analyzeCurrentDirectory()
end)
```

## Troubleshooting

### "cloc not found" Error

Make sure `cloc` is installed and accessible:

```bash
which cloc
```

If not found, reinstall with Homebrew:

```bash
brew install cloc
```

### Menu Bar Icon Missing

1. Check Hammerspoon Console for errors:
   - Menu bar → Hammerspoon → Console
   - Look for initialization errors

2. Verify the path in your `init.lua` configuration

3. Reload Hammerspoon configuration:
   - Menu bar → Hammerspoon → Reload Config

### No Analysis Results

1. **Check Directory Permissions**: Ensure Hammerspoon can read the target directory
2. **Verify File Types**: Make sure the directory contains recognized source code files
3. **Console Debug**: Check Hammerspoon Console for `cloc` command output

### Performance Issues

For very large codebases:
1. **Increase Exclusions**: Add more directories to the exclusion list
2. **Limit Depth**: Modify the analysis to limit directory traversal depth
3. **Cache Results**: The tool caches results - subsequent runs will be faster

## Requirements

- macOS (tested on macOS 12+)
- Homebrew
- Hammerspoon
- cloc (Count Lines of Code)
- Read access to directories you want to analyze

## Privacy Note

This tool analyzes local files only. No data is sent to external servers. All analysis is performed locally using the `cloc` utility.
