Param(
    [ValidateSet("AZ")]
	[string] $CloudServiceProvider = "AZ",
    [ValidateSet("GA","GI","GT","GV","DE","DC","DW")]
    [Parameter(Mandatory = $true)]
    [string] $Region,
    [ValidateSet("")]
    [string] $Enterprise = "",
    [ValidateSet("")]
    [string] $Department = "",
    [ValidateSet("")]
    [string] $Account = "",
    [ValidateSet("P","I","T","D","L")]
    [Parameter(Mandatory = $true)]
    [string] $Environment,
    [ValidateSet("IL2","IL4","IL5")]
    [Parameter(Mandatory = $true)]
	[string] $ImpactLevel,
    [Parameter(Mandatory = $true)]
    [string] $FunctionalArea,
    [string] $Application,
    [ValidateSet("COR")]
	[string] $ResourceGroupType = "COR",
	[string] $Ordinal = "01",
    [Parameter(Mandatory = $true)]
    $SubscriptionName,
    [string] $StorageAccountName,
    [string] $sourceContainerName = "insights-logs-networksecuritygroupflowevent",
    [string] $destinationContainerName = "nsg-flowevent-archive",
    [int] $blobMaxCount = 1000,
    [string] $metadataKeyName = "OmsLogType",
    [string] $logtype = "NsgFlowLogs"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

#region Set Prerequisite Variables
$connectionName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-").ToUpper()
switch($FunctionalArea){
    "CMNSVC"{
        $connectionName += ("$($FunctionalArea)-$($Environment)-$($ImpactLevel)-RunAsConn-$($Ordinal)").ToUpper()
        $stgName = ("$($Region)$($FunctionalArea)$($Environment)$($ImpactLevel)STG").ToLower()
        if($StorageAccountName){} #end if
        else{$StorageAccountName = $stgName} #end else
    }
    "SHDSVC" {
        $connectionName += ("$($FunctionalArea)-$($Environment)-$($ImpactLevel)-RunAsConn-$($Ordinal)").ToUpper()
        $stgName = ("$($Region)$($FunctionalArea)$($Environment)$($ImpactLevel)STG").ToLower()
        if($StorageAccountName){} #end if
        else{$StorageAccountName = $stgName} #end else
    }
    default{
        $connectionName += ("$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-RunAsConn-$($Ordinal)").ToUpper()
        $stgName = ("$($Region)$($Application)$($Environment)$($ImpactLevel)STG").ToLower()
        if($StorageAccountName){} #end if
        else{$StorageAccountName = $stgName} #end else
    }
} #end switch
#endregion Set Prerequisite Variables

#region Authenticate to Subscription
$servicePrincipalConnection = $null

Write-Output "Authenticating against Azure..."
try
{
    # Get the connection "AzureRunAsConnection "
    if($ImpactLevel -eq "IL5"){$connectionName = $connectionName.Replace("-DE-","-GV-")}
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName

    "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
        -EnvironmentName AzureUSGovernment
} #end try
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } #end if
    else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    } #end else
} #end catch

Write-Output "Selecting Subscription..."
Select-AzureRmSubscription -SubscriptionName $SubscriptionName
#endregion Authenticate to Subscription

#region Get StorageAccount
Write-Output "Getting SAS Token..."
$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})
$context = $storageAccount.Context;
#endregion Get StorageAccount

#region Archive Blobs
$blobs = Get-AzureStorageBlob -Context $context -Container $sourceContainerName -MaxCount $blobMaxCount

foreach($blob in $blobs)
{
    #$CloudBlockBlob = [Microsoft.WindowsAzure.Storage.Blob.CloudBlockBlob] $blob.ICloudBlob
    #$logtype = $CloudBlockBlob.Metadata[$metadataKeyName]
    $metadata = $blob.ICloudBlob.Metadata
    $setlogtype = $metadata["OmsLogType"]
    Write-Output "Log type: $($setlogtype)"
    if($setlogtype -eq $logtype)
    {
        Write-Output "Log type set on file, copying to archive container" 

        Start-AzureStorageBlobCopy -SrcContainer $sourceContainerName -SrcBlob $blob.Name -DestContainer $destinationContainerName -Context $context -Force
        $copyState = Get-AzureStorageBlobCopyState -Blob $blob.Name -Container $destinationContainerName -Context $context -WaitForComplete
        if($copyState.Status -eq "Success")
        {
            Write-Output "Copy to archive container succeeded, removing source blob."
            Remove-AzureStorageBlob -Blob $blob.Name -Container $sourceContainerName -Context $context
            Write-Output "Source blob removed removed successfully: $($blob.Name)"
        }
    }
   
}
#endregion Archive Blobs
