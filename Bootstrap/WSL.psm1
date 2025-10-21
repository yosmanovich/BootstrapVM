function Test-WSL 
{    
    $enabled = $true
    $features = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")
    foreach ($FeatureName in $features) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        $enabled = $enabled -and $feature.State 
    }
    return $enabled
}

function Test-WSLUbuntuInstalled 
{
    try {
        $wslList = & cmd.exe /c "wsl --list --verbose 2>nul"
        if ($wslList) {
            $output = $wslList -join " "
            $output = $output -replace [char][int]0, ""
            return $output -match "Ubuntu-22\.04"
        }
        return $false
    } catch {
        return $false
    }
}

function Install-WSL
{
    Write-Host "Enabling WSL..." 
    Write-Host "Checking required Windows features..." 
    
    $features = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")
    $needsReboot = $false
    
    foreach ($feature in $features) {

        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
            $needsReboot = $true
        } catch {
            Write-Error "Failed to enable ${feature}: $($_.Exception.Message)"
            return @{
                "Success"=$false 
                "NeedsReboot"=$needsReboot 
            }
        }
    }
    if ($needsReboot) {
        Write-Host "Windows features have been enabled. A reboot is required." -ForegroundColor Yellow
        Write-Host "Please reboot your system and run this script again." -ForegroundColor Red
        return @{
                "Success"=$false 
                "NeedsReboot"=$needsReboot 
        }
    }
    return @{
        "Success"=$true 
        "NeedsReboot"=$needsReboot 
    }
}

function Update-WSL 
{
    Write-Host "Download Ubuntu-22.04"     
    $versionSuccess = Invoke-WSLCommand "wsl" @("--install", "-d", "Ubuntu-22.04", "--no-launch") "WSL download Ubuntu-22.04"
    if ($versionSuccess) {
        Write-Host "WSL downloaded Ubuntu 22.04 successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Failed to download Ubuntu 22.04"
        return $false
    }

    $versionSuccess = Invoke-WSLCommand "ubuntu2204.exe" @("install", "--root") "Install Ubuntu-22.04"       
    if ($versionSuccess) {
        Write-Host "Ubuntu 22.04 installed successfully!" -ForegroundColor Green
    } else {
        
        Write-Warning "Failed to install Ubuntu 22.04"
        return $false
    }
    Write-Host "Set WSL to use version 2" 
    Write-Host "Executing: wsl --set-default-version 2" -ForegroundColor Gray

    $versionSuccess = Invoke-WSLCommand "wsl" @("--set-default-version", "2") "WSL default version configuration"

    if ($versionSuccess) {
        Write-Host "WSL default version set to 2 successfully!" -ForegroundColor Green
    } else {
        Write-Warning "Failed to set WSL default version to 2"
        return $false
    }
    return $true
}

function Invoke-WSLCommand 
{
    param(
        [string]$Command = "wsl",
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
        # Enhanced error handling for common WSL issues
        $errorMessage = $_.Exception.Message       
        Write-Error "$Description failed: $errorMessage"        
        return $false
    }
}

function Set-WSLConfiguration
{
    param(
        [switch]$ReInitialize
    )
    if ($ReInitialize) {    
        if (Test-WSLUbuntuInstalled)
        {
            $versionSuccess = Invoke-WSLCommand "wsl" @("--unregister", "Ubuntu-22.04") "Remove Ubuntu 22.04"
            $versionSuccess = Invoke-WSLCommand "ubuntu2204.exe" @("install", "--root") "Install Ubuntu-22.04"    
            $versionSuccess = Invoke-WSLCommand "wsl" @("--set-default", "Ubuntu-22.04") "Set Default WSL distribution to Ubuntu 22.04"
            Write-Host "Ubuntu reinstalled successfully!" -ForegroundColor Green  
        }
        else
        {
            $versionSuccess = Invoke-WSLCommand "ubuntu2204.exe" @("install", "--root") "Install Ubuntu-22.04"    
            $versionSuccess = Invoke-WSLCommand "wsl" @("--set-default", "Ubuntu-22.04") "Set Default WSL distribution to Ubuntu 22.04" 
            Write-Host "Ubuntu installed successfully!" -ForegroundColor Green  
        }
    }

    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"install -m 0755 -d /etc/apt/keyrings`"") "Setup Keyrings"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null`"") "Configure Node"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null`"") "Obtain Docker SSL Cert"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"chmod a+r /etc/apt/keyrings/docker.gpg > /dev/null`"") "Set security on Docker SSL Cert"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --yes --dearmor -o /etc/apt/keyrings/microsoft.gpg > /dev/null`"") "Obtain Microsoft SSL Cert"    
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"chmod a+r /etc/apt/keyrings/microsoft.gpg > /dev/null`"") "Set security on Microsoft SSL Cert"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --yes --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg > /dev/null`"") "Obtain Hashicorp SSL Cert"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg > /dev/null`"") "Set security on hashicorp cert"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable' | tee /etc/apt/sources.list.d/docker.list > /dev/null`"") "Get docker source list"        
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"echo 'deb [signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ jammy main' | tee /etc/apt/sources.list.d/azure-cli.list > /dev/null`"") "Get docker source list"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com jammy main' | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null`"") "Get hashicorp source list"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt update`"") "Update Apt"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt remove -y libnode-dev`"") "Remove libnode-de"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y nodejs`"") "Install NodeJS"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y jq`"") "Install jq"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y ca-certificates curl`"") "Install ca-certificates and curl"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y docker.io docker-compose`"") "Install docker"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y dos2unix`"") "Install dos2unix"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y terraform`"") "Setup Install terraform"

    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y azure-cli`"") "Setup Azure CLI"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt install -y make`"") "Instal make"


    
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"apt autoremove -y`"") "Setup Keyrings"

    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"groupadd -f docker`"") "Create Docker group"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"usermod -aG docker root`"") "Add user to docker group"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"ln -sf /mnt/c/Program\ Files/Docker/Docker/resources/bin/docker.exe /usr/local/bin/docker-desktop`"") "Create link for docker to docker desktop"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"ln -sf /mnt/c/Program\ Files/Docker/Docker/resources/bin/docker-compose.exe /usr/local/bin/docker-compose-desktop`"") "Create link for docker compose to docker compose desktop"

    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"mkdir /var/source`"") "Install jq"

    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"git config --global credential.helper '/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe'`"") "Configure Git Credential Manager"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"git config --global credential.useHttpPath true`"") "Configure Git HTTPS"

    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"echo -e '=============================================================================\n\rRun the following commands to prepare your environment:\n\r1. Configure and pull the files from GitHub:\n\r   git config --global user.email <Your email>\n\r   git config --global user.name <Your Name>\n\r   git clone https://github.com/microsoft/Federal-Information-Assistant.git info-assist\n\r   cd info-assist\n\r   git fetch --tags\n\r\n\r2. Authenticate to Azure\n\r   Open a browser and login to your Azure subscription -> https://portal.azure.com\n\r\n\r3. Authenticate to Azure CLI\n\r   az login --user-device-code\n\r\n\r4. Configure the scripts/environments/local.env file\n\r\n\r5. Run make to deploy environment\n\r=============================================================================\n\r' > /etc/motd`"") "MOTD created" 
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"echo -e '#!/bin/sh\n\ncat /etc/motd' > /etc/update-motd.d/99-system`"") "MOTD Startup created"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"chmod +x /etc/motd`"") "MOTD security set"
    $versionSuccess = Invoke-WSLCommand "wsl" @("-e", "bash", "-c", "`"chmod +x /etc/update-motd.d/99-system`"") "MOTD Startup security set"
}

Export-ModuleMember -Function Test-WSL
Export-ModuleMember -Function Test-WSLUbuntuInstalled
Export-ModuleMember -Function Update-WSL
Export-ModuleMember -Function Install-WSL
Export-ModuleMember -Function Set-WSLConfiguration