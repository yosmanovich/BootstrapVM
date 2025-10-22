<#
.SYNOPSIS
    The install script will install the BootstrapVM solution into an Azure VM
.DESCRIPTION
    This script will set up the necessary environment and dependencies for the BootstrapVM solution.
.EXAMPLE
    ./Install.ps1
#>
param(
    [string]$admin = "admInfoAssist"
)

Start-Transcript -Path transcript.log

New-Item -ItemType Directory -Path C:\Bootstrap\
Move-Item -Path .\Bootstrap.ps1 -Destination C:\Bootstrap\
Move-Item -Path .\*.psm1 -Destination C:\Bootstrap\

# Define the target file or application
$Script= "C:\Bootstrap\Bootstrap.ps1"

# Define the shortcut name
$ShortcutName = "BootstrapVM Launcher"

# Get the desktop path
$DesktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory')

# Create the shortcut
$WScriptShell = New-Object -ComObject WScript.Shell
$ShortcutPath = "$DesktopPath\$ShortcutName.lnk"
$Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)

# Set shortcut properties
$Shortcut.TargetPath = "powershell"
$Shortcut.Arguments = $Script
$Shortcut.WorkingDirectory = Split-Path $Script
$Shortcut.Save()

#Modify the shortcut to always run as administrator
$Bytes = [System.IO.File]::ReadAllBytes($ShortcutPath)
$Bytes[0x15] = $Bytes[0x15] -bor 0x20 # Set the RunAsAdministrator flag (bit 6 of byte 21)
[System.IO.File]::WriteAllBytes($ShortcutPath, $Bytes)
Write-Host "Shortcut created successfully on the desktop!"

Stop-Transcript -Path transcript.log