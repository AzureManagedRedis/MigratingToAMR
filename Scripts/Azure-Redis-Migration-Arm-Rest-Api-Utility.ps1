<#
.SYNOPSIS
    Script for migrating a cache from Azure Cache for Redis to Azure Managed Redis using ARM REST APIs.
.DESCRIPTION
    This script allows you to initiate, check the status of, or cancel a migration from an Azure Cache for Redis resource to Azure Managed Redis.
.PARAMETER Action
    The action to perform: "Migrate", "Status", or "Cancel".
.PARAMETER SourceResourceId
    The resource ID of the source Azure Cache for Redis resource.
.PARAMETER AmrCacheName
    The name of the target Azure Managed Redis resource.
.PARAMETER ResourceGroupName
    The name of the resource group containing the Azure Managed Redis resource.
.PARAMETER SubscriptionId
    The subscription ID that contains both the source and target resources.
.PARAMETER Environment
    The Azure environment to use (default is the public "AzureCloud").
.PARAMETER TrackMigration
    If set, the script will wait for the migration operation to complete (default is $false).
.PARAMETER Verbose
    If set, the script will output detailed information about its operations (default is $false).
.PARAMETER Help
    If set, displays help information about the script (default is $false).
.EXAMPLE
    .\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 -Action Migrate -SourceResourceId "/subscriptions/xxxxx/resourceGroups/rg1/providers/Microsoft.Cache/Redis/redis1" -AmrCacheName "myAmrCache" -ResourceGroupName "rg1" -SubscriptionId "xxxx-xxxx-xxxx-xxxx" -TrackMigration
    Initiates a migration and tracks its progress.
    .\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 -Action Status -AmrCacheName "myAmrCache" -ResourceGroupName "rg1" -SubscriptionId "xxxx-xxxx-xxxx-xxxx"
    Checks the status of the migration.
    .\Azure-Redis-Migration-Arm-Rest-Api-Utility.ps1 -Action Cancel -AmrCacheName "myAmrCache" -ResourceGroupName "rg1" -SubscriptionId "xxxx-xxxx-xxxx-xxxx"
    Cancels the migration.
.NOTES
    This script requires the Az PowerShell module.
#>

[CmdletBinding()]
param
(
    [Parameter()]
    [ValidateSet("Migrate", "Status", "Cancel")]
    [string] $Action,

    [Parameter()]
    [string] $SourceResourceId,

    [Parameter()]
    [string] $AmrCacheName,

    [Parameter()]
    [string] $ResourceGroupName,

    [Parameter()]
    [string] $SubscriptionId,

    [Parameter()]
    [ValidateSet("AzureCloud")]
    [string] $Environment = "AzureCloud",

    [Parameter()]
    [switch] $TrackMigration = $false,

    [Parameter(DontShow = $true)]
    [string] $ArmApiVersion = "2025-08-01-preview",

    [Parameter()]
    [switch] $Help = $false
)

$ErrorActionPreference = "Stop"
$currentScript = $MyInvocation.MyCommand.Source

function Show-Help
{
    Get-Help -Name $currentScript -Full
}

if ($Help)
{
    Show-Help
    exit 0
}

function Login-ToAzure
{
    $context = Get-AzContext

    if ($context -and $context.Environment.Name -eq $Environment)
    {
        if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId)
        {
            Set-AzContext -Subscription $SubscriptionId | Out-Null

            $context = Get-AzContext
            Write-Host "'$($context.Account.Id)' already logged in to Azure. Switched current subscription to '$($context.Subscription.Id)'"
        }
    }
    else
    {
        Connect-AzAccount -EnvironmentName $Environment -Subscription $SubscriptionId -WarningAction SilentlyContinue | Out-Null

        $context = Get-AzContext
        Write-Host "Logged in to $($context.Environment.Name) as '$($context.Account.Id)' and selected subscription '$($context.Subscription.Id)'"
    }

    Write-Host
    return $context
}

Login-ToAzure | Out-Null

function Print-Response(
    [Microsoft.Azure.Commands.Profile.Models.PSHttpResponse] $response = "$(throw 'Specify -response param')")
{
    # Check status code
    $statusCode = $response.StatusCode
    if ($statusCode -eq 200)
    {
        Write-Host "The request is successful." -ForegroundColor Green
    }
    elseif ($statusCode -gt 200 -and $statusCode -lt 300)
    {
        Write-Host "The request is accepted." -ForegroundColor Green
    }
    else
    {
        Write-Host "The request has encountered a failure. Status Code: $statusCode" -ForegroundColor Red
    }

    # Display relevant Azure headers if available
    $headersToShow = @(
        "x-ms-request-id",
        "x-ms-correlation-request-id", 
        "x-ms-operation-identifier"
    )

    if ($response.Headers)
    {
        foreach ($header in $response.Headers)
        {
            if ($headersToShow -contains $header.Key)
            {
                $headerValue = ($header.Value -join ", ")
                Write-Host "$($header.Key) : $headerValue"
            }
        }
    }

    Write-Host $response.Content
}

switch ($Action)
{
    "Migrate"
    {
        $payload = @{
            properties = @{
                sourceResourceId  = $SourceResourceId;
                cacheResourceType = "AzureCacheForRedis";
                switchDns         = $true;
                skipDataMigration = $true;
            };
        } | ConvertTo-Json -Depth 3

        if ($TrackMigration.IsPresent)
        {
            Write-Host "This command will trigger the migration and will track the long running operation until its completion."
            $response = Invoke-AzRestMethod `
                -Method PUT `
                -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cache/RedisEnterprise/$AmrCacheName/migrations/default?api-version=$ArmApiVersion" `
                -Payload $payload `
                -WaitForCompletion
        }
        else
        {
            Write-Host "This command will trigger the migration and will exit immediately. It will not track the long running migration operation until its completion. Please use the 'Status' action to check and track the migration completion status"
            $response = Invoke-AzRestMethod `
                -Method PUT `
                -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cache/RedisEnterprise/$AmrCacheName/migrations/default?api-version=$ArmApiVersion" `
                -Payload $payload
        }

        Print-Response $response

        break
    }

    "Status"
    {
        $response = Invoke-AzRestMethod `
            -Method GET `
            -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cache/RedisEnterprise/$AmrCacheName/migrations/default?api-version=$ArmApiVersion"

        Print-Response $response

        break
    }

    "Cancel"
    {
        if ($TrackMigration.IsPresent)
        {
            Write-Host "This command will trigger the cancellation and will track the long running operation until its completion."
            $response = Invoke-AzRestMethod `
                -Method POST `
                -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cache/RedisEnterprise/$AmrCacheName/migrations/default/cancel?api-version=$ArmApiVersion" `
                -WaitForCompletion
        }
        else
        {
            Write-Host "This command will trigger the cancellation and will exit immediately. It will not track the long running operation until its completion. Use the 'Status' action to check and track migration cancellation status."
            $response = Invoke-AzRestMethod `
                -Method POST `
                -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Cache/RedisEnterprise/$AmrCacheName/migrations/default/cancel?api-version=$ArmApiVersion"
        }

        Print-Response $response

        break
    }

    Default
    {
        throw "Invalid action specified. Please use one of the following: 'Migrate', 'Status', 'Cancel'."
    }
}