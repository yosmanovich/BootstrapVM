    az config set extension.use_dynamic_install=yes_without_prompt

    $EnvironmentSettings = (Get-Content "../Configuration/Environment.json" -Raw) | ConvertFrom-Json

    $VMVnet = "$($EnvironmentSettings.VirtualMachineName)-vnet"

    infoasst-dns
    az network private-dns zone list --query "[?starts_with(name, 'infoasst-dns')].name" --output tsv
    $InfoAssistVnet = az network vnet list --query "[?starts_with(name, 'infoasst-vnet')].name" --output tsv
    if ($InfoAssistVnet.Count -gt 1)
    {
        Write-Host "Multiple InfoAssist vNets found, please check the environment configuration." -ForegroundColor Red
        exit
    }    
    if ($null -eq $InfoAssistVnet)
    {
        Write-Host "InfoAssist vNet not found, please deploy the InfoAssist infrastructure first." -ForegroundColor Red
        exit
    }
    $InfoAssistRG = az network vnet list --query "[?starts_with(name, 'infoasst-vnet')].resourceGroup" --output tsv
    
    Write-Host "Creating VNet peering from VM to InfoAssist..."
    az network vnet peering create `
        --name VM-to-InfoAssist `
        --vnet-name $VMVnet `
        --remote-vnet "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/$InfoAssistRG/providers/Microsoft.Network/virtualNetworks/$InfoAssistVnet" `
        --resource-group $($EnvironmentSettings.ResourceGroupName) `
        --allow-vnet-access 
    
    Write-Host "Creating VNet peering from InfoAssist to VM..."
    az network vnet peering create `
        --name InfoAssist-to-VM `
        --vnet-name $InfoAssistVnet `
        --remote-vnet "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/$($EnvironmentSettings.ResourceGroupName)/providers/Microsoft.Network/virtualNetworks/$VMVnet" `
        --resource-group $InfoAssistRG `
        --allow-vnet-access 

    $DNSResolverName = az dns-resolver list --resource-group $InfoAssistRG --query "[0].name" --output tsv    
    $InboundEndpointIP = az dns-resolver inbound-endpoint list --dns-resolver-name $DNSResolverName --resource-group $InfoAssistRG --query "[0].ipConfigurations[0].privateIpAddress" --output tsv
    Write-Host "DNS Resolver Inbound Endpoint IP: $InboundEndpointIP" -ForegroundColor Green
        
    Write-Host "Configuring VNet DNS to use resolver endpoint..." -ForegroundColor Yellow
    az network vnet update `
        --name $VMVnet `
        --resource-group $($EnvironmentSettings.ResourceGroupName) `
        --dns-servers $InboundEndpointIP
    
    Write-Host "VNet DNS configuration updated successfully!" -ForegroundColor Green 