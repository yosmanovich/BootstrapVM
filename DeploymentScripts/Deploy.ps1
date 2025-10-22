function Get-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [ValidateRange(4,[int]::MaxValue)]
        [int] $length,
        [int] $upper = 1,
        [int] $lower = 1,
        [int] $numeric = 1,
        [int] $special = 1
    )
    if($upper + $lower + $numeric + $special -gt $length) {
        throw "number of upper/lower/numeric/special char must be lower or equal to length"
    }
    $uCharSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lCharSet = "abcdefghijklmnopqrstuvwxyz"
    $nCharSet = "0123456789"
    $sCharSet = "/*-+,!?=()@;:._"
    $charSet = ""
    if($upper -gt 0) { $charSet += $uCharSet }
    if($lower -gt 0) { $charSet += $lCharSet }
    if($numeric -gt 0) { $charSet += $nCharSet }
    if($special -gt 0) { $charSet += $sCharSet }
    
    $charSet = $charSet.ToCharArray()
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($length)
    $rng.GetBytes($bytes)
 
    $result = New-Object char[]($length)
    for ($i = 0 ; $i -lt $length ; $i++) {
        $result[$i] = $charSet[$bytes[$i] % $charSet.Length]
    }
    $password = (-join $result)
    $valid = $true
    if($upper   -gt ($password.ToCharArray() | Where-Object {$_ -cin $uCharSet.ToCharArray() }).Count) { $valid = $false }
    if($lower   -gt ($password.ToCharArray() | Where-Object {$_ -cin $lCharSet.ToCharArray() }).Count) { $valid = $false }
    if($numeric -gt ($password.ToCharArray() | Where-Object {$_ -cin $nCharSet.ToCharArray() }).Count) { $valid = $false }
    if($special -gt ($password.ToCharArray() | Where-Object {$_ -cin $sCharSet.ToCharArray() }).Count) { $valid = $false }
 
    if(!$valid) {
         $password = Get-RandomPassword $length $upper $lower $numeric $special
    }
    return $password
}

$password = Get-RandomPassword -length 16 -upper 2 -lower 2 -numeric 2 -special 2
$securepassword = ConvertTo-SecureString $(Get-RandomPassword -length 12 -upper 1 -lower 1 -numeric 1 -special 1)-AsPlainText -Force
az config set extension.use_dynamic_install=yes_without_prompt

$EnvironmentSettings = (Get-Content "../Configuration/Environment.json" -Raw) | ConvertFrom-Json
$ParameterFile = (Get-Content "../Infrastructure/Parameters/VM.parameters.json" -Raw) | ConvertFrom-Json

$resourceGroupName = az group show --name  $($EnvironmentSettings.ResourceGroupName) --query name -o tsv
if ($null -eq $resourceGroupName)
{
    az group create --name $($EnvironmentSettings.ResourceGroupName) --location $($EnvironmentSettings.Location) --output none
    Write-Host "Resource Group created"
}

az deployment group create --name "VM" `
    --resource-group $($EnvironmentSettings.ResourceGroupName) `
    --template-file "../Infrastructure/Templates/VM.template.json" `
    --parameters "../Infrastructure/Parameters/VM.parameters.json" `
    --parameters "virtualMachineName=$($EnvironmentSettings.VirtualMachineName)"  `
    --parameters "adminPassword=$securepassword"  `
    --output none
Write-Host "Virtual Machine provisioned"

$protectedSettings = @{
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -File .\Install.ps1 -admin $($ParameterFile.parameters.adminUsername.value)"
    fileUris = @(
        "https://github.com/yosmanovich/BootstrapVM/releases/download/initial/Install.ps1",        
        "https://github.com/yosmanovich/BootstrapVM/releases/download/initial/Bootstrap.ps1",
        "https://github.com/yosmanovich/BootstrapVM/releases/download/initial/Docker.psm1",
        "https://github.com/yosmanovich/BootstrapVM/releases/download/initial/Git.psm1",
        "https://github.com/yosmanovich/BootstrapVM/releases/download/initial/VSCode.psm1",
        "https://github.com/yosmanovich/BootstrapVM/releases/download/initial/WSL.psm1"
    )
    managedIdentity = @{}
}
# Convert to JSON without escaping - Azure CLI handles JSON parsing
$protectedSettingsJson = $protectedSettings | ConvertTo-Json -Compress
$settingsJson = $settings | ConvertTo-Json -Compress

# Write JSON to temporary files to avoid command line escaping issues
$settingsFile = [System.IO.Path]::GetTempFileName()
$protectedSettingsFile = [System.IO.Path]::GetTempFileName()

$settingsJson | Out-File -FilePath $settingsFile -Encoding utf8 -NoNewline
$protectedSettingsJson | Out-File -FilePath $protectedSettingsFile -Encoding utf8 -NoNewline

try {
    az vm extension set `
        --resource-group $($EnvironmentSettings.ResourceGroupName) `
        --vm-name $($EnvironmentSettings.VirtualMachineName) `
        --name "CustomScriptExtension" `
        --publisher "Microsoft.Compute" `
        --version "1.10" `
        --settings "@$settingsFile" `
        --protected-settings "@$protectedSettingsFile"
}
finally {
    # Clean up temporary files
    Remove-Item $settingsFile -ErrorAction SilentlyContinue
    Remove-Item $protectedSettingsFile -ErrorAction SilentlyContinue
}