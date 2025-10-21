function Test-GitInstalled
{
    try {
        $gitVersion = git --version 2>$null
        if ($gitVersion) {
            return $true
        }
    } catch {
    
    }
    return $true
}
function Test-GCMWInstalled 
{
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $registryPaths) {
        try {
            $programs = Get-ItemProperty $path -ErrorAction SilentlyContinue
            $gcmw = $programs | Where-Object { 
                $_.DisplayName -like "*Git Credential Manager*" -or 
                $_.DisplayName -like "*GCMW*" -or
                $_.DisplayName -like "*Microsoft Git Credential Manager*"
            }
            
            if ($gcmw) {
                return $true
            }
        } catch {
            # Continue checking other registry paths
        }
    }
    
    # Check if git-credential-manager.exe is available
    try {
        $gcmPath = Get-Command "git-credential-manager.exe" -ErrorAction SilentlyContinue
        if ($gcmPath) {
            return $true
        }
    } catch { }
    
    # Check common installation directories
    $commonPaths = @(
        "${env:ProgramFiles}\Git\mingw64\libexec\git-core\git-credential-manager.exe",
        "${env:ProgramFiles(x86)}\Git\mingw64\libexec\git-core\git-credential-manager.exe",
        "${env:ProgramFiles}\Microsoft\Git Credential Manager for Windows\git-credential-manager.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Git Credential Manager for Windows\git-credential-manager.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $true
        }
    }
    
    return $false
}

function Install-Git
{
    Write-Host "Git Installation Script" -ForegroundColor Green
    Write-Host "======================" -ForegroundColor Green

    # Check if Git is already installed
    try {
        $gitVersion = git --version 2>$null
        if ($gitVersion) {
            Write-Host "Git is already installed: $gitVersion" -ForegroundColor Yellow
            return true
        }
    } catch {
        Write-Host "Git is not currently installed." 
    }

    # Create temporary directory
    $tempDir = Join-Path $env:TEMP "GitInstaller"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "Downloading Git installer..." 

    # Download the latest Git installer
    $downloadUrl = "https://github.com/git-for-windows/git/releases/download/v2.51.0.windows.2/Git-2.51.0.2-64-bit.exe"
    $installerPath = Join-Path $tempDir "Git-installer.exe"

    try {
        
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

        Write-Progress -Activity "Downloading Git installer" -Completed
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download Git installer: $($_.Exception.Message)"
        Write-Host "Trying alternative download method..." -ForegroundColor Yellow
        
        try {
            # Alternative: Get the actual latest release URL from GitHub API
            $apiUrl = "https://api.github.com/repos/git-scm/git/releases/latest"
            $response = Invoke-RestMethod -Uri $apiUrl
            $asset = $response.assets | Where-Object { $_.name -match "Git-.*-64-bit\.exe$" } | Select-Object -First 1
            
            if ($asset) {
                $downloadUrl = $asset.browser_download_url
                Write-Host "Found latest version: $($response.tag_name)" 
                Write-Host "Downloading from: $downloadUrl" 
                
                Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
                Write-Host "Download completed successfully!" -ForegroundColor Green
            } else {
                throw "Could not find 64-bit Git installer in latest release"
            }
        } catch {
            Write-Error "Failed to download Git installer: $($_.Exception.Message)"
            Write-Host "Please download Git manually from https://git-scm.com/download/win" -ForegroundColor Red
            exit 1
        }
    }

    # Verify the downloaded file
    if (-not (Test-Path $installerPath)) {
        Write-Error "Installer file not found at $installerPath"
        exit 1
    }

    $fileSize = (Get-Item $installerPath).Length
    Write-Host "Installer downloaded: $([math]::Round($fileSize / 1MB, 2)) MB" 

    Write-Host "Starting Git installation..." 

    # Prepare installation arguments
    $installArgs = @("/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES")

    # Run the installer
    try {
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Git installation completed successfully!" -ForegroundColor Green
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            # Verify installation
            Start-Sleep -Seconds 2
            try {
                $newGitVersion = & "C:\Program Files\Git\bin\git.exe" --version 2>$null
                if ($newGitVersion) {
                    Write-Host "Verification successful: $newGitVersion" -ForegroundColor Green
                } else {
                    Write-Host "Git installed but verification failed. You may need to restart your terminal." -ForegroundColor Yellow
                }
            } catch {
                Write-Host "Git installed but verification failed. You may need to restart your terminal." -ForegroundColor Yellow
            }
            
            Write-Host "`nNext steps:" -ForegroundColor Cyan
            Write-Host "1. Restart your PowerShell/Command Prompt to use Git" -ForegroundColor White
            Write-Host "2. Configure Git with your name and email:" -ForegroundColor White
            Write-Host "   git config --global user.name `"Your Name`"" -ForegroundColor Gray
            Write-Host "   git config --global user.email `"your.email@example.com`"" -ForegroundColor Gray
            
        } else {
            Write-Error "Git installation failed with exit code: $($process.ExitCode)"
            exit 1
        }
    } catch {
        Write-Error "Failed to run Git installer: $($_.Exception.Message)"
        exit 1
    }

    # Cleanup
    Write-Host "Cleaning up temporary files..." 
    Remove-Item $tempDir -Recurse -Force

    Write-Host "`nGit installation process completed!" -ForegroundColor Green
}

function Install-GCMW 
{
    Write-Host "Git Credential Manager for Windows (GCMW) Installation Script" -ForegroundColor Green
    Write-Host "=============================================================" -ForegroundColor Green
    Write-Host "Target Version: $Version" 

    # Create temporary directory
    $tempDir = Join-Path $env:TEMP "GCMWInstaller"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "Downloading Git Credential Manager for Windows v$Version..." 

    # Construct download URL for the specified version    
 #   $downloadUrl = "https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.6.1/gcm-win-x86-2.6.1.exe"
    $downloadUrl = "https://github.com/microsoft/Git-Credential-Manager-for-Windows/releases/download/1.20.0/GCMW-1.20.0.exe"
    $installerPath = Join-Path $tempDir "GCMW-$Version.exe"

    try {
        # Download with progress
        Write-Host "Downloading from: $downloadUrl" -ForegroundColor Gray
        

        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath
        Write-Progress -Activity "Downloading GCMW installer" -Completed
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download GCMW installer: $($_.Exception.Message)"
        
        # Try alternative download URLs
        Write-Host "Trying alternative download sources..." -ForegroundColor Yellow
        
        $alternativeUrls = @(
            "https://github.com/microsoft/Git-Credential-Manager-for-Windows/releases/download/v$Version/GCMW-$Version.exe",
            "https://github.com/Microsoft/Git-Credential-Manager-for-Windows/releases/download/$Version/GCMW-$Version.exe"
        )
        
        $downloadSuccess = $false
        foreach ($altUrl in $alternativeUrls) {
            try {
                Write-Host "Trying: $altUrl" -ForegroundColor Gray
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($altUrl, $installerPath)
                $webClient.Dispose()
                $downloadSuccess = $true
                Write-Host "Download completed successfully!" -ForegroundColor Green
                break
            } catch {
                Write-Warning "Failed to download from: $altUrl"
            }
        }
        
        if (-not $downloadSuccess) {
            Write-Error "All download attempts failed."
            Write-Host "Please download GCMW manually from:" -ForegroundColor Red
            Write-Host "https://github.com/Microsoft/Git-Credential-Manager-for-Windows/releases" -ForegroundColor Red
            exit 1
        }
    }

    # Verify the downloaded file
    if (-not (Test-Path $installerPath)) {
        Write-Error "Installer file not found at $installerPath"
        exit 1
    }

    $fileSize = (Get-Item $installerPath).Length
    Write-Host "Installer downloaded: $([math]::Round($fileSize / 1MB, 2)) MB" 

    Write-Host "Starting Git Credential Manager for Windows installation..." 

    # Prepare installation arguments
    $installArgs = @("/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES")

    # Additional installation tasks
    $tasks = @("AddToPath")  # Ensure GCMW is added to PATH

    $installArgs += "/TASKS=`"$($tasks -join ',')`""

    # Run the installer
    try {
        Write-Host "Running GCMW installer..." 
        Write-Host "Command: $installerPath $($installArgs -join ' ')" -ForegroundColor Gray
        
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Git Credential Manager for Windows installation completed successfully!" -ForegroundColor Green
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            # Verify installation
            Start-Sleep -Seconds 3
            $newInstall = Test-GCMWInstalled
            
            if ($newInstall.Installed) {
                Write-Host "Verification successful:" -ForegroundColor Green
                Write-Host "  Name: $($newInstall.Name)" -ForegroundColor Gray
                Write-Host "  Version: $($newInstall.Version)" -ForegroundColor Gray
                if ($newInstall.Path) {
                    Write-Host "  Location: $($newInstall.Path)" -ForegroundColor Gray
                }
            } else {
                Write-Host "GCMW installed but verification failed. You may need to restart your terminal." -ForegroundColor Yellow
            }
            
            # Configure Git to use GCMW
            Write-Host "Configuring Git to use Credential Manager..." 
            try {
                & git config --global credential.helper manager 2>$null
                Write-Host "Git configuration updated successfully!" -ForegroundColor Green
            } catch {
                Write-Warning "Could not configure Git automatically. You may need to run:"
                Write-Host "git config --global credential.helper manager" -ForegroundColor Gray
            }
            
        } else {
            Write-Error "Git Credential Manager for Windows installation failed with exit code: $($process.ExitCode)"
            exit 1
        }
    } catch {
        Write-Error "Failed to run GCMW installer: $($_.Exception.Message)"
        exit 1
    }

    # Cleanup
    Write-Host "Cleaning up temporary files..." 
    Remove-Item $tempDir -Recurse -Force    
}

function Invoke-GitCommand 
{
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$Description
    )
    
    Write-Host "Executing: $Command $($Arguments -join ' ')" -ForegroundColor Gray
    
    try {
        $process = Start-Process -FilePath $Command -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Host "$Description completed successfully!" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "$Description failed with exit code: $($process.ExitCode)"
            return $false
        }
    } catch {
        Write-Error "$Description failed: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Test-GitInstalled
Export-ModuleMember -Function Test-GCMWInstalled
Export-ModuleMember -Function Install-Git
Export-ModuleMember -Function Install-GCMW 
