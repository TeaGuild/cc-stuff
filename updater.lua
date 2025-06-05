-- GitHub Auto-Updater for ComputerCraft
-- Self-updating startup script that manages multiple files from GitHub
-- Uses hash comparison for reliable change detection

-- Configuration
local GITHUB_USER = "TeaGuild"
local GITHUB_REPO = "cc-stuff"
local GITHUB_BRANCH = "main"

-- Files to manage (updater first so it can self-update)
local FILES = {
    {
        github = "updater.lua",
        local_name = "startup.lua",
        description = "Auto-updater"
    },
    {
        github = "payload.lua", 
        local_name = "train_station.lua",
        description = "Train station monitor"
    }
}

-- GitHub raw content URL builder
local function getGitHubURL(file)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s",
        GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, file
    )
end

-- Calculate file hash
local function getFileHash(content)
    -- Simple but effective hash function
    local hash = 0
    for i = 1, #content do
        local byte = string.byte(content, i)
        hash = ((hash * 31) + byte) % 2147483647
    end
    return tostring(hash)
end

-- Read local file hash
local function getLocalHash(filename)
    if not fs.exists(filename) then
        return nil
    end
    
    local file = fs.open(filename, "r")
    if not file then
        return nil
    end
    
    local content = file.readAll()
    file.close()
    
    return getFileHash(content)
end

-- Download file from GitHub
local function downloadFile(github_file)
    local url = getGitHubURL(github_file)
    local response = http.get(url)
    
    if not response then
        return nil, "Failed to download from GitHub"
    end
    
    local content = response.readAll()
    response.close()
    
    if not content or content == "" then
        return nil, "Empty response from GitHub"
    end
    
    -- Basic validation - check if it looks like Lua code
    if not (content:find("%-%-") or content:find("function") or content:find("local") or content:find("end")) then
        return nil, "Content doesn't appear to be valid Lua code"
    end
    
    return content, nil
end

-- Update a single file
local function updateFile(fileInfo)
    local localHash = getLocalHash(fileInfo.local_name)
    
    -- Download from GitHub
    local content, err = downloadFile(fileInfo.github)
    if not content then
        return false, err
    end
    
    local remoteHash = getFileHash(content)
    
    -- Check if update needed
    if localHash == remoteHash then
        return false, "Already up to date"
    end
    
    -- Backup existing file
    if fs.exists(fileInfo.local_name) then
        local backupName = fileInfo.local_name .. ".backup"
        if fs.exists(backupName) then
            fs.delete(backupName)
        end
        fs.copy(fileInfo.local_name, backupName)
    end
    
    -- Write new file
    local file = fs.open(fileInfo.local_name, "w")
    if not file then
        return false, "Cannot write file"
    end
    
    file.write(content)
    file.close()
    
    return true, string.format("Updated (hash: %s -> %s)", localHash or "new", remoteHash)
end

-- Quick update check with timeout
local function quickUpdateCheck()
    local updated = false
    local updaterUpdated = false
    
    -- Show minimal status
    term.clear()
    term.setCursorPos(1, 1)
    if term.isColor() then term.setTextColor(colors.yellow) end
    print("Checking for updates...")
    term.setTextColor(colors.white)
    
    -- Check each file
    for i, fileInfo in ipairs(FILES) do
        term.setCursorPos(1, 2 + i)
        term.write(fileInfo.description .. ": ")
        
        local success, message = updateFile(fileInfo)
        
        if success then
            if term.isColor() then term.setTextColor(colors.green) end
            print("Updated!")
            term.setTextColor(colors.white)
            updated = true
            
            -- Check if updater itself was updated
            if fileInfo.local_name == "startup.lua" then
                updaterUpdated = true
            end
        else
            if message == "Already up to date" then
                if term.isColor() then term.setTextColor(colors.gray) end
                print("Current")
            else
                if term.isColor() then term.setTextColor(colors.red) end
                print("Failed: " .. message)
            end
            term.setTextColor(colors.white)
        end
    end
    
    return updated, updaterUpdated
end

-- Main execution
local function main()
    -- Perform update check
    local updated, updaterUpdated = quickUpdateCheck()
    
    -- If updater was updated, restart immediately
    if updaterUpdated then
        print("\nUpdater updated! Restarting...")
        sleep(2)
        os.reboot()
        return
    end
    
    -- Brief pause if updates were installed
    if updated then
        sleep(2)
    else
        sleep(0.5)
    end
    
    -- Check if main payload exists
    local mainScript = FILES[2].local_name  -- train_station.lua
    if not fs.exists(mainScript) then
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.red) end
        print("ERROR: Main script not found!")
        print("Failed to download " .. mainScript)
        term.setTextColor(colors.white)
        print("\nRetrying in 10 seconds...")
        sleep(10)
        os.reboot()
        return
    end
    
    -- Clear screen and run main script
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Run with error handling
    local ok, err = pcall(function()
        shell.run(mainScript)
    end)
    
    if not ok then
        -- Script crashed
        term.clear()
        term.setCursorPos(1, 1)
        if term.isColor() then term.setTextColor(colors.red) end
        print("ERROR: Main script crashed!")
        term.setTextColor(colors.white)
        print(err)
        print("\nRebooting in 10 seconds...")
        sleep(10)
        os.reboot()
    end
end

-- Emergency error handler
local ok, err = pcall(main)
if not ok then
    if term.isColor() then term.setTextColor(colors.red) end
    print("CRITICAL ERROR in updater:")
    term.setTextColor(colors.white)
    print(err)
    print("\nRebooting in 10 seconds...")
    sleep(10)
    os.reboot()
end
