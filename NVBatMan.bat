@echo off & setlocal EnableDelayedExpansion & (set "ARGS=" & for %%I in (%*) do set ARGS=!ARGS!'%%~I' ) & powershell.exe -ExecutionPolicy Bypass "$script = Get-Content '%~dpnx0'; $script -notmatch 'supercalifragilisticexpialidocious' | Out-File '%TEMP%\%~n0.ps1' -Force; Start-Process powershell.exe -Verb RunAs -ArgumentList ""-ExecutionPolicy Bypass -Command Set-Location '%~dp0'; & '%TEMP%\%~n0.ps1' !ARGS!""" & exit /b

<#
////////////////////////////
//  NVBatMan by Lulech23  //
////////////////////////////

Fix NVIDIA GPUs hogging all that battery power!

What's New:
* Added support for explicitly enabling/disabling power limits via Start Menu shortcuts

To-do:
* Find better way to detect insufficient power supply that doesn't return false positives on AC power
#>



<#
INITIALIZATION
#>

# Version... obviously
$version = "1.0.5"

# NVBatMan data path
$path = "$env:ProgramData\NVBatMan"
$menu = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\NVBatMan"

# Old version (if any)
$oldVersion = $version
if (Test-Path "$path\NVBatMan.ps1") {
    $oldVersion = ((Get-Content "$path\NVBatMan.ps1" -TotalCount 1) -replace '^<#(.*)v(.*)#>$','$2').Trim()
}



<#
SHOW VERSION
#>

# Ooo, shiny!
Write-Host "`n                               " -BackgroundColor Green -NoNewline
Write-Host "`n NVBatMan [v$version] by Lulech23 " -NoNewline -BackgroundColor Green -ForegroundColor Black
Write-Host "`n                               " -BackgroundColor Green

# About
Write-Host "`nThis script will install a scheduled task to limit NVIDIA GPU power consumption"
Write-Host "while running on battery power. Counter-intuitively, this actually improves"
Write-Host "performance by reducing throttling due to competition with the CPU."
Write-Host "`nTo undo changes and restore the original behavior, run this script again later."

# Current Status
Write-Host "`nBattery Management is currently set to: " -NoNewline
if (Test-Path "$path\NVBatMan.ps1") {
     if ($version -ne $oldVersion) {
        Write-Host "NVBatMan (previous version)" -ForegroundColor Cyan
        Write-Host " * System will balance GPU and CPU when operating on battery power" -ForegroundColor Gray
        $task = "Update NVBatMan"
    } else {
        Write-Host "NVBatMan" -ForegroundColor Cyan
        Write-Host " * System will balance GPU and CPU when operating on battery power" -ForegroundColor Gray
        $task = "Revert to NVIDIA Platform Controllers and Framework"
    }
} else {
    Write-Host "NVIDIA Platform Controllers and Framework" -ForegroundColor Magenta
    Write-Host " * System may heavily throttle CPU when operating on battery power" -ForegroundColor Gray
    $task = "Install NVBatMan"
}

# Setup Info
Write-Host "`nSetup will: " -NoNewline
Write-Host "$task`n" -ForegroundColor Cyan
for ($s = 10; $s -ge 0; $s--) {
    $p = if ($s -eq 1) { "" } else { "s" }
    Write-Host "`rPlease wait $s second$p to continue, or close now (Ctrl + C) to exit..." -NoNewLine -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host



<#
INSTALL/UPDATE NVBATMAN
#>

if ($task.contains("Install") -or $task.contains("Update")) {
    # Get performance mode to apply on battery
    Write-Host "`nSelect the performance mode to apply when on battery:" -ForegroundColor Green
    Write-Host " 1" -NoNewLine -ForegroundColor Yellow
    Write-Host " - Balanced Mode (Lower FPS; more stable)" -ForegroundColor Gray
    Write-Host " 2" -NoNewLine -ForegroundColor Yellow
    Write-Host " - Performance Mode (Higher FPS; may stutter)`n" -ForegroundColor Gray
    $mode = Read-Host "Enter mode (1 or 2)"

    # Validate input (default to Balanced Mode)
    $mode = [Math]::Max(1, [Math]::Min(2, $mode -as [int]))

    # Define base memory and graphics clocks to select
    if ($mode -eq 1) {
        $mc = 1000
        $gc = 1100
    } else {
        $mc = 5000
        $gc = 400
    }

    # Get available memory/graphics clock pairs for the current GPU
    $clocks = (nvidia-smi --query-supported-clocks=memory,graphics --format=nounits)
    if ($mode -eq 1) {
        # Find nearest matching frequency pair (Balanced Mode)
        for ($c = 0; $c -lt $clocks.Count; $c++) {
            $clock = $clocks[$c]
            if ($clock -match '(\d+),\s*(\d+)') {
                if ((($matches[1] -as [int]) -lt $mc) -and (($matches[2] -as [int]) -lt $gc)) {
                    $mc = $matches[1]
                    $gc = $matches[2]
                    break
                }
            }
        }
    } else {
        # Find nearest matching frequency pair (Performance Mode)
        for ($c = ($clocks.Count - 1); $c -ge 0; $c--) {
            $clock = $clocks[$c]
            if ($clock -match '(\d+),\s*(\d+)') {
                if ((($matches[1] -as [int]) -gt $mc) -and (($matches[2] -as [int]) -gt $gc)) {
                    $mc = $matches[1]
                    $gc = $matches[2]
                    break
                }
            }
        }
    }

    # Insert minimum clocks to ranges
    $clocks[$clocks.count - 1] -match '(\d+),\s*(\d+)' | Out-Null
    $mc = "$($matches[1]),$mc"
    $gc = "$($matches[2]),$gc"

    # Show setup info
    Start-Sleep -Seconds 1
    if ($mode -eq 1) {
        Write-Host "`nInstalling NVBatMan (Balanced Mode)..."
    } else {
        Write-Host "`nInstalling NVBatMan (Performance Mode)..."
    }
    Start-Sleep -Seconds 1

    # Ensure NVBatMan directory exists
    if (!(Test-Path -Path "$path")) {
        New-Item -ItemType Directory -Path "$path" -Force | Out-Null
    }



    <#
    FILES
    #>
    
    # NVBatMan.ps1 - Main script to monitor power state and apply GPU power limits
    $ps1 = @"
<# NVBatMan by Lulech23 v$version #>
param(
    [switch] `$Enable,
    [switch] `$Disable
)



<# 
FUNCTIONS 
#>

function Set-GpuPowerState([Nullable[Boolean]] `$Limit) {
    # Check current system power status
    `$isPConAC = (Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus).PowerOnline

    # Check current GPU power status
    `$isGPUonAC = ((nvidia-smi --query-gpu=power.default_limit,enforced.power.limit --format=csv,noheader) -split ',' | ForEach-Object {
        [double](`$_.Replace("W", "").Trim())
    })
    `$isGPUonAC = (`$isGPUonAC[0] -le `$isGPUonAC[1])

    # Check current power limit conditions
    if (`$null -eq `$Limit) {
        `$Limit = (-not `$isPConAC) -or (-not `$isGPUonAC)
    }
    
    # Apply power limits based on current power status
    if (`$Limit) {
        Write-Host "Status: DC. Applying GPU power limits..." -ForegroundColor Yellow
        
        # Disable NVIDIA Platform Controller to prevent clock speed overrides
        Get-PnpDevice -FriendlyName "NVIDIA Platform Controllers and Framework" | Disable-PnpDevice -Confirm:`$false
        
        # Lock clocks to limit power consumption ("Balanced Mode")
        nvidia-smi -lmc $mc
        nvidia-smi -lgc $gc
    } else {
        <# AC (Plugged In) #>
        Write-Host "Status: AC. Restoring GPU defaults..." -ForegroundColor Green
        
        # Re-enable NVIDIA Platform Controller to automatically manage clocks
        Get-PnpDevice -FriendlyName "NVIDIA Platform Controllers and Framework" | Enable-PnpDevice -Confirm:`$false
        
        # Reset clocks to defaults
        nvidia-smi -rmc
        nvidia-smi -rgc
    }
}



<#
MANUAL
#>

if (`$Enable) {
    Set-GpuPowerState -Limit `$true
    exit
}

if (`$Disable) {
    Set-GpuPowerState -Limit `$false
    exit
}



<#
SERVICE
#>

`$singleInstance = `$false
`$mutex = New-Object System.Threading.Mutex(`$true, "Global\NVBatMan", [ref]`$singleInstance)
if (-not `$singleInstance) {
    Write-Host "Status: Already running! Exiting..." -ForegroundColor Yellow
    exit
}

Register-WmiEvent -Query "SELECT * FROM Win32_PowerManagementEvent WHERE EventType = 10" -SourceIdentifier "BatteryStatusChanged"
try {
    Write-Host "Monitoring power state... " -NoNewline
    Write-Host "Press Ctrl + C to stop" -ForegroundColor Yellow
    
    # Run once at startup to set initial state
    Set-GpuPowerState
    
    while (`$true) {
        # Wait for the next WMI event
        Wait-Event -SourceIdentifier "BatteryStatusChanged"
        
        # Run when power state changes
        Set-GpuPowerState

        # Clear event queue
        Remove-Event -SourceIdentifier "BatteryStatusChanged"
    }
} finally {
    `$mutex.ReleaseMutex()
    `$mutex.Dispose()
    Unregister-Event -SourceIdentifier "BatteryStatusChanged"
    Write-Host "Stopped monitoring power state."
}
"@
    Write-Output $ps1 | Out-File "$path\NVBatMan.ps1" -Encoding UTF8 -Force

    # NVBatMan.xml - Scheduled Task definition to run NVBatMan.ps1 at user logon
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Date>2026-03-04T20:58:59.9634052</Date>
        <Author>lucasc.me</Author>
        <Description>Automatically limit NVIDIA GPU power consumption for best performance on battery</Description>
        <URI>\NVBatMan</URI>
    </RegistrationInfo>
    <Triggers>
        <BootTrigger>
            <Enabled>true</Enabled>
        </BootTrigger>
        <LogonTrigger>
            <Enabled>true</Enabled>
        </LogonTrigger>
        <SessionStateChangeTrigger>
            <Enabled>true</Enabled>
            <StateChange>SessionUnlock</StateChange>
        </SessionStateChangeTrigger>
    </Triggers>
    <Principals>
        <Principal id="Author">
            <GroupId>S-1-5-32-544</GroupId>
            <RunLevel>HighestAvailable</RunLevel>
        </Principal>
    </Principals>
    <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>false</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
        <IdleSettings>
            <StopOnIdleEnd>false</StopOnIdleEnd>
            <RestartOnIdle>false</RestartOnIdle>
        </IdleSettings>
        <AllowStartOnDemand>true</AllowStartOnDemand>
        <Enabled>true</Enabled>
        <Hidden>false</Hidden>
        <RunOnlyIfIdle>false</RunOnlyIfIdle>
        <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
        <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
        <WakeToRun>false</WakeToRun>
        <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
        <Priority>7</Priority>
        <RestartOnFailure>
            <Interval>PT1M</Interval>
            <Count>4</Count>
        </RestartOnFailure>
    </Settings>
    <Actions Context="Author">
        <Exec>
            <Command>C:\Windows\System32\conhost.exe</Command>
            <Arguments>--headless powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "$path\NVBatMan.ps1"</Arguments>
        </Exec>
    </Actions>
</Task>
"@
    Write-Output $xml | Out-File "$path\NVBatMan.xml" -Force



    <#
    SCHEDULED TASK
    #>

    # Register Scheduled Task from XML
    if (Get-ScheduledTask -TaskName "NVBatMan" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "NVBatMan" -Confirm:$false
    }
    Register-ScheduledTask -Xml (Get-Content "$path\NVBatMan.xml" | Out-String) -TaskName "NVBatMan" -Force
    Start-ScheduledTask -TaskName "NVBatMan"

    # If installation was successful...
    if (
        (Test-Path -Path "$path\NVBatMan.ps1") -and 
        (Get-ScheduledTask -TaskName "NVBatMan" -ErrorAction SilentlyContinue)
    ) {
        # End process, we're done!
        Write-Host "`nProcess complete! " -NoNewline -ForegroundColor Green
        Write-Host "NVBatMan installed successfully. Enjoy!"
        Write-Host "`nIf you liked this, stop by my website at " -NoNewline
        Write-Host "https://lucasc.me" -NoNewline -ForegroundColor Yellow
        Write-Host "!"
    } else {
        # Show error if installation failed
        Write-Host "Installation failed! " -NoNewline -ForegroundColor Magenta
        Write-Host "Could not access required resources!"
        Write-Host "`nPlease ensure correct system permissions and run this script again."
    }



    <#
    SHORTCUTS
    #>

    # Ensure Start Menu shortcut directory exists
    if (!(Test-Path $menu)) {
        New-Item -ItemType Directory -Path $menu -Force
    }

    # Remove old shortcuts, if they exist
    if (Test-Path "$menu\Start NVBatMan.lnk") {
        Remove-Item "$menu\Start NVBatMan.lnk" -Force
    }
    if (Test-Path "$menu\Stop NVBatMan.lnk") {
        Remove-Item "$menu\Stop NVBatMan.lnk" -Force
    }
    
    # Create "Start NVBatMan" shortcut
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut("$menu\Start NVBatMan.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-File `"$path\NVBatMan.ps1`" -Enable"
    $shortcut.IconLocation = "C:\Windows\System32\wpdshext.dll, 13"
    $shortcut.Save()
    $bytes = [System.IO.File]::ReadAllBytes("$menu\Start NVBatMan.lnk")
    $bytes[0x15] = $bytes[0x15] -bor 0x20                                   # Enable "Run as administrator" flag
    [System.IO.File]::WriteAllBytes("$menu\Start NVBatMan.lnk", $bytes)
    
    # Create "Stop NVBatMan" shortcut
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut("$menu\Stop NVBatMan.lnk")
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-File `"$path\NVBatMan.ps1`" -Disable"
    $shortcut.IconLocation = "C:\Windows\System32\wpdshext.dll, 9"
    $shortcut.Save()
    $bytes = [System.IO.File]::ReadAllBytes("$menu\Stop NVBatMan.lnk")
    $bytes[0x15] = $bytes[0x15] -bor 0x20                                   # Enable "Run as administrator" flag
    [System.IO.File]::WriteAllBytes("$menu\Stop NVBatMan.lnk", $bytes)
}



<#
UNINSTALL NVBATMAN
#>

if ($task.contains("Revert")) {
    # Show setup info
    Start-Sleep -Seconds 1
    Write-Host "`nUninstalling NVBatMan..."
    Start-Sleep -Seconds 1

    # Remove Start Menu shortcuts
    Remove-Item -Path "$menu" -Recurse -Force -ErrorAction SilentlyContinue

    # Unregister Scheduled Task
    if (Get-ScheduledTask -TaskName "NVBatMan" -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName "NVBatMan" -Confirm:$false
    }

    # Remove NVBatMan files from target folder
    Remove-Item -Path "$path\NVBatMan.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$path\NVBatMan.xml" -Force

    # Reset NVIDIA GPU clocks
    nvidia-smi -rmc
    nvidia-smi -rgc

    # Enable NVIDIA Platform Controller to restore default clock management
    Get-PnpDevice -FriendlyName "NVIDIA Platform Controllers and Framework" | Enable-PnpDevice -Confirm:$false

    # If uninstallation was successful...
    if (
        !(Test-Path -Path "$path\NVBatMan.ps1") -and 
        !(Get-ScheduledTask -TaskName "NVBatMan" -ErrorAction SilentlyContinue)
    ) {
        # End process, we're done!
        Write-Host "`nProcess complete! " -NoNewline -ForegroundColor Green
        Write-Host "NVBatMan removed. Enjoy, I guess..."
    } else {
        # Show error if uninstallation failed
        Write-Host "Removal failed! " -NoNewline -ForegroundColor Magenta
        Write-Host "Could not access required resources!"
        Write-Host "`nPlease ensure correct system permissions and run this script again."
    }
}



<#
FINALIZATION
#>

# Exit, we're done!
Write-Host
for ($s = 10; $s -ge 0; $s--) {
    $p = if ($s -eq 1) { "" } else { "s" }
    Write-Host "`rSetup will cleanup and exit in $s second$p, please wait..." -NoNewLine -ForegroundColor Yellow
    Start-Sleep -Seconds 1
}
Write-Host
