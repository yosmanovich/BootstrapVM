<#
.SYNOPSIS
    The Bootstrap script will retrieve and install all dependencies to allow a developer 
    to build and deploy the info-assist solution in a secure environment.
.DESCRIPTION
    Detailed description of what the script does
.EXAMPLE
    ./Bootstrap.ps1
#>

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Warning "This script should be run as Administrator for best results."
    Write-Host "Attempting to restart as Administrator..." -ForegroundColor Yellow
    
    $arguments = "-Silent -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""   
    Start-Process PowerShell -Verb RunAs -ArgumentList $arguments
    exit
}
Import-Module ".\Modules\WSL.psm1" -Force
Import-Module ".\Modules\Git.psm1" -Force
Import-Module ".\Modules\Docker.psm1" -Force
Import-Module ".\Modules\VSCode.psm1" -Force

$test = Test-WSL
if ($test -eq $false) { Install-WSL }
else { Write-Host "WSL already installed" }

$test = Test-WSLUbuntuInstalled 
if ($test -eq $false) { Update-WSL }
else { Write-Host "Ubuntu already installed" }

$test = Test-GitInstalled 
if ($test -eq $false) { Install-Git }
else { Write-Host "Git already installed" }

$test = Test-GCMWInstalled
if ($test -eq $false) { Install-GCMW }
else { Write-Host "Git already installed" }

$test = Test-DockerInstalled 
if ($test -eq $false) { Install-Docker }
else { Write-Host "Docker already installed" }

$test = Test-VSCodeInstalled
if ($test -eq $false) { Install-VSCode }
else { Write-Host "VS Code already installed" }

Configure-WSL 
Configure-Docker 

if ($(Test-WSL) -and $(Test-WSLUbuntuInstalled) -and  $(Test-GitInstalled) -and $(Test-GCMWInstalled) -and $(Test-DockerInstalled) -and  $(Test-VSCodeInstalled))
{ Write-Host "Components are all installed" }
else { Write-Host "Re-run script, components failed to install" }