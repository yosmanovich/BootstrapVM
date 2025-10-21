function Test-DockerInstalled
{
    $result = @{
        Installed = $false
        InstallationType = $null
        Version = $null
        Location = $null
        ServiceStatus = $null
        ExecutablePath = $null
        Details = @()
    }
    
    # Method 1: Check common installation paths
    $commonPaths = @(
        "${env:ProgramFiles}\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "${env:LOCALAPPDATA}\Programs\Docker\Docker\Docker Desktop.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $result.Installed = $true
            $result.ExecutablePath = $path
            $result.Location = Split-Path $path -Parent
            
            # Determine installation type based on path
            if ($path -like "${env:ProgramFiles}*") {
                $result.InstallationType = "System-wide (All Users)"
            } elseif ($path -like "${env:LOCALAPPDATA}*") {
                $result.InstallationType = "User Installation"
            }
            
            # Try to get version from executable
            try {
                $versionInfo = Get-ItemProperty $path | Select-Object -ExpandProperty VersionInfo
                if ($versionInfo.ProductVersion) {
                    $result.Version = $versionInfo.ProductVersion
                }
            } catch {
                # Version detection failed, will try other methods
            }
            
            $result.Details += "Found Docker Desktop executable at: $path"
            break
        }
    }
    
    # Method 2: Check Windows Registry (Uninstall entries)
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $registryPaths) {
        try {
            $programs = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
            $dockerEntry = $programs | Where-Object { 
                $_.DisplayName -like "*Docker Desktop*" -or 
                $_.DisplayName -like "*Docker for Windows*"
            }
            
            if ($dockerEntry) {
                $result.Installed = $true
                if (-not $result.Version -and $dockerEntry.DisplayVersion) {
                    $result.Version = $dockerEntry.DisplayVersion
                }
                if (-not $result.Location -and $dockerEntry.InstallLocation) {
                    $result.Location = $dockerEntry.InstallLocation
                }
                
                $result.Details += "Found in registry: $($dockerEntry.DisplayName) v$($dockerEntry.DisplayVersion)"
                
                # Check if it's a system or user installation
                if ($regPath -like "*HKLM*") {
                    $result.InstallationType = "System-wide (All Users)"
                } else {
                    $result.InstallationType = "User Installation"
                }
            }
        } catch {
            # Registry check failed, continue with other methods
        }
    }
    
    # Method 3: Check for Docker CLI availability
    try {
        $dockerVersion = docker --version 2>$null
        if ($dockerVersion) {
            $result.Details += "Docker CLI available: $dockerVersion"
            
            # If we haven't found Desktop yet, this might be Docker Engine only
            if (-not $result.Installed) {
                $result.Details += "Note: Found Docker CLI but not Docker Desktop"
            }
        }
    } catch {
        # Docker CLI not available
    }
    
    # Method 4: Check Docker Desktop service
    try {
        $dockerService = Get-Service -Name "com.docker.service" -ErrorAction SilentlyContinue
        if ($dockerService) {
            $result.ServiceStatus = $dockerService.Status
            $result.Details += "Docker Desktop service status: $($dockerService.Status)"
            if (-not $result.Installed) {
                $result.Installed = $true
                $result.Details += "Detected via Docker Desktop service"
            }
        }
    } catch {
        # Service check failed
    }
    
    # Method 5: Check for Docker Desktop process
    try {
        $dockerProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
        if ($dockerProcess) {
            $result.Details += "Docker Desktop process is running (PID: $($dockerProcess.Id))"
            if (-not $result.Installed) {
                $result.Installed = $true
                $result.Details += "Detected via running process"
            }
        }
    } catch {
        # Process check failed
    }
    
    # Method 6: Check for Docker daemon socket (WSL/Linux containers)
    try {
        if (Test-Path "\\.\pipe\docker_engine") {
            $result.Details += "Docker daemon pipe found (Windows containers mode)"
        }
        if (Test-Path "\\.\pipe\docker_engine_linux") {
            $result.Details += "Docker daemon pipe found (Linux containers mode)"
        }
    } catch {
        # Pipe check failed
    }
    
    # Method 7: Check Docker Desktop settings file
    $settingsPath = "$env:APPDATA\Docker\settings.json"
    if (Test-Path $settingsPath) {
        $result.Details += "Docker Desktop settings file found at: $settingsPath"
        
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($settings.version) {
                if (-not $result.Version) {
                    $result.Version = $settings.version
                }
                $result.Details += "Settings file version: $($settings.version)"
            }
        } catch {
            $result.Details += "Settings file exists but couldn't parse version"
        }
    }
    
    # Method 8: Check Windows Features (if Hyper-V or WSL is enabled)
    try {
        $hyperV = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Hyper-V" -ErrorAction SilentlyContinue
        if ($hyperV -and $hyperV.State -eq "Enabled") {
            $result.Details += "Hyper-V is enabled (supports Docker Desktop)"
        }
        
        $wsl = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux" -ErrorAction SilentlyContinue
        if ($wsl -and $wsl.State -eq "Enabled") {
            $result.Details += "WSL is enabled (supports Docker Desktop)"
        }
    } catch {
        # Windows features check failed
    }
    
    return $result.Installed
}
function Install-Docker 
{
    # Create temporary directory
    $tempDir = Join-Path $env:TEMP "DockerDesktopInstaller"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "Downloading Docker Desktop installer..." 
    # Docker Desktop download URL
    $downloadUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $installerPath = Join-Path $tempDir "DockerDesktopInstaller.exe"

    try {
        # Use TLS 1.2 for secure connection
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Download with progress
        $webClient = New-Object System.Net.WebClient
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $percent = $Event.SourceEventArgs.ProgressPercentage
            Write-Progress -Activity "Downloading Docker Desktop installer" -Status "$percent% Complete" -PercentComplete $percent
        } | Out-Null
        
        $webClient.DownloadFile($downloadUrl, $installerPath)
        $webClient.Dispose()
        Write-Progress -Activity "Downloading Docker Desktop installer" -Completed
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download Docker Desktop installer: $($_.Exception.Message)"
        Write-Host "Please download Docker Desktop manually from https://www.docker.com/products/docker-desktop" -ForegroundColor Red
        exit 1
    }

    # Verify the downloaded file
    if (-not (Test-Path $installerPath)) {
        Write-Error "Installer file not found at $installerPath"
        exit 1
    }

    $fileSize = (Get-Item $installerPath).Length
    Write-Host "Installer downloaded: $([math]::Round($fileSize / 1MB, 2)) MB" 

    Write-Host "Starting Docker Desktop installation..." 

    # Prepare installation arguments
    $installArgs = @("install", "--quiet")

    # Add WSL2 backend configuration
    $installArgs += "--backend=wsl-2"

    try {
        Write-Host "Running Docker Desktop installer..." 
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Docker Desktop installation completed successfully!" -ForegroundColor Green
        } else {
            Write-Error "Docker Desktop installation failed with exit code: $($process.ExitCode)"
            exit 1
        }
    } catch {
        Write-Error "Failed to run Docker Desktop installer: $($_.Exception.Message)"
        exit 1
    }

    # Wait for Docker Desktop to be available
    Write-Host "Waiting for Docker Desktop to initialize..." 
    Start-Sleep -Seconds 10
}

function Set-DockerConfiguration 
{
    # Path to Docker Desktop settings file
    $settingsPath = "$env:APPDATA\Docker\settings-store.json"

    # Read current settings
    $settings = Get-Content $settingsPath | ConvertFrom-Json

    if ($null -ne ($settings | Get-Member -Name "EnableIntegrationWithDefaultWslDistro")) 
    {
        $settings.EnableIntegrationWithDefaultWslDistro = $true
    }
    else 
    {
        $settings | Add-Member -NotePropertyName EnableIntegrationWithDefaultWslDistro -NotePropertyValue $true
    }
        # Enable WSL integration
    if ($null -ne ($settings | Get-Member -Name "IntegratedWslDistros")) 
    {
        $settings.IntegratedWslDistros = @("Ubuntu-22.04")
    }
    else 
    {
        $settings | Add-Member -NotePropertyName IntegratedWslDistros -NotePropertyValue @("Ubuntu-22.04")
    }

    # Write back to file
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

    # Restart Docker Desktop to apply changes
    Stop-Process -Name "Docker Desktop" -Force -ErrorAction SilentlyContinue
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
}

Export-ModuleMember -Function Test-DockerInstalled
Export-ModuleMember -Function Install-Docker
Export-ModuleMember -Function Set-DockerConfiguration 