function Test-VSCodeInstalled 
{
    $paths = @(
        "${env:ProgramFiles}\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe",
        "${env:LOCALAPPDATA}\Programs\Microsoft VS Code\Code.exe"
    )
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            return $true
        }
    }
    
    # Check if code command is available
    try {
        $version = code --version 2>$null | Select-Object -First 1
        if ($version) {
            return $true
        }
    } catch { }
    
    return $false
}

function Install-VSCode
{
    # Create temporary directory
    $tempDir = Join-Path $env:TEMP "VSCodeInstaller"
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "Downloading Visual Studio Code..." 

    # Determine download URL based on channel and architecture
    $architecture = if ([Environment]::Is64BitOperatingSystem) { "win32-x64" } else { "win32" }

    $downloadUrl = "https://update.code.visualstudio.com/latest/$architecture/stable"
    $installerName = "VSCodeSetup-$architecture.exe"

    $installerPath = Join-Path $tempDir $installerName

    try {
        # Use TLS 1.2 for secure connection
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Download with progress
        Write-Host "Downloading from: $downloadUrl" -ForegroundColor Gray
        
        $webClient = New-Object System.Net.WebClient
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -Action {
            $percent = $Event.SourceEventArgs.ProgressPercentage
            Write-Progress -Activity "Downloading VS Code installer" -Status "$percent% Complete" -PercentComplete $percent
        } | Out-Null
        
        $webClient.DownloadFile($downloadUrl, $installerPath)
        $webClient.Dispose()
        Write-Progress -Activity "Downloading VS Code installer" -Completed
        
        Write-Host "Download completed successfully!" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download VS Code installer: $($_.Exception.Message)"
        Write-Host "Please download VS Code manually from https://code.visualstudio.com/" -ForegroundColor Red
        exit 1
    }

    # Verify the downloaded file
    if (-not (Test-Path $installerPath)) {
        Write-Error "Installer file not found at $installerPath"
        exit 1
    }

    $fileSize = (Get-Item $installerPath).Length
    Write-Host "Installer downloaded: $([math]::Round($fileSize / 1MB, 2)) MB" 

    Write-Host "Starting Visual Studio Code installation..." 

    # Prepare installation arguments
    $installArgs = @("/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES", "/ALLUSERS")

    # Additional options
    $tasks = @()
    $tasks += "desktopicon"
    $tasks += "quicklaunchicon"
    $tasks += "addcontextmenufiles"
    $tasks += "addcontextmenufolders"
    $tasks += "addtopath"
    $tasks += "associatewithfiles"

    if ($tasks.Count -gt 0) {
        $installArgs += "/TASKS=`"$($tasks -join ',')`""
    }

    # Run the installer
    try {
        Write-Host "Running VS Code installer..." 
        Write-Host "Command: $installerPath $($installArgs -join ' ')" -ForegroundColor Gray
        
        $process = Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Host "Visual Studio Code installation completed successfully!" -ForegroundColor Green
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            
            # Verify installation
            Start-Sleep -Seconds 3
            $newInstall = Test-VSCodeInstalled
            
            if ($newInstall.Installed) {
                Write-Host "Verification successful:" -ForegroundColor Green
                Write-Host "  Location: $($newInstall.Path)" -ForegroundColor Gray
                Write-Host "  Version: $($newInstall.Version)" -ForegroundColor Gray
            } else {
                Write-Host "VS Code installed but verification failed. You may need to restart your terminal." -ForegroundColor Yellow
            }
            
        } else {
            Write-Error "Visual Studio Code installation failed with exit code: $($process.ExitCode)"
            exit 1
        }
    } catch {
        Write-Error "Failed to run VS Code installer: $($_.Exception.Message)"
        exit 1
    }

    # Cleanup
    Write-Host "Cleaning up temporary files..." 
    Remove-Item $tempDir -Recurse -Force    
}

Export-ModuleMember -Function Test-VSCodeInstalled
Export-ModuleMember -Function Install-VSCode