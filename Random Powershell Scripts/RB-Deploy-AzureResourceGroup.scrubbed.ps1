<#
.SYNOPSIS
    Deploys Azure Resource Manager (ARM) templates to an Azure Government subscription using a distinct naming convention.
	Review each section to identify this naming convention.
.DESCRIPTION
    This script will take a *.parameters.json file and multiple linked *.json files that are stored in an Azure Government storage account.
	After retrieving the *.parameters.json, using a SAS Token, the script converts the file to a Powershell Hashtable as a parameters object supplied to the New-AzureRmResourceGroupDeploymnet along with the Uri for the *.json.
	The script can run locally (-RunLocally = $true) or using an Azure Automation Certificate Credential, in either instances the *.json files need to be in an Azure stoage account.
	Using the (-UploadTemplates) switch will ensure that the content in the storage account is uploaded and overwritten to the latest.
	If a storage account doesn't exist one will be created with	3 containers (templates, dsc, and scripts).
	The script deploys 3 resource group types COR, NET, and APP and should be deployed in that order as separate deployments.
.PARAMETER RunLocally
	If $true uses local powershell context, else run as a runbook in Azure Autmoation to call a runAs account with Certificate credentials.
.PARAMETER CloudServiceProvider
	Default to AZ for Azure
.PARAMETER Region
	Use either GV (usgovvirginia) or DE (usdodeast) at this time
.PARAMETER OMSLocation
	Default to usgovvirginia
.PARAMETER Enterprise
	Default to
.PARAMETER Department
	Default to 
.PARAMETER Account
	If deploying in a lab environment for integration
.PARAMETER Environment
	Acceptable values are L (lab), D (Dev/Int), T (Test), and P (Prod)
.PARAMETER ImpactLevel
	Acceptable values are IL2, IL4, and IL5
.PARAMETER FunctionalArea
	This represents the Billing Unit/Organization e.g. 
.PARAMETER Application
	This represents within the 7 charaters the name of the Application, but not required if deploying to Common or Shared Services Zones
.PARAMETER ResourceGroupType
	Acceptable values are COR, NET, and APP, update the ValidateSet in the parameters section if you wish to change the naming convention but this naming convention is directly tied to the file names of the *.json.
.PARAMETER Ordinal
	Defaults to 01 and is suffixed on all resource groups
.PARAMETER StorageAccountName
	If they templates live in a storage account other than the one created via the script supply the name (must be in same subscription)
.PARAMETER SubscriptionName
	Required subscription name
.PARAMETER ArtifactStagingDirectory
	Parent directory ending in "\" to directories templates, dsc, and scripts for artifacts that need to be uploaded
.PARAMETER UploadTemplates
	Switch to upload template files from local workstation to storage account
.PARAMETER UploadScripts
	Switch to upload script files from local workstation to storage account
.PARAMETER UploadDSC
	Switch to upload dsc files from local workstation to storage account
.EXAMPLE
    $deployParams = @{
		RunLocally = $true
		Region = "GV"
		Environment = "L"
		ImpactLevel = "IL4"
		FunctionalArea = "FUNCT"
		Application = "NAME"
		ResourceGroupType = "COR"
		SubscriptionName = "A"
		ArtifactStagingDirectory = ".\"
		UploadTemplates = $true
		UploadScripts = $true
		UploadDSC = $true
		Verbose = $true
	}
	.\RB-Deploy-AzureResourceGroup.ps1 @deployParams
.NOTES
#>

#Requires -Version 3.0
#Requires -Module AzureRM.Resources
#Requires -Module Azure.Storage

Param(
    [bool] $RunLocally = $false,
    [ValidateSet("AZ")]
    [string] $CloudServiceProvider = "AZ",
    [string]
    [ValidateSet("GA","GI","GT","GV","DE","DC","DW")]
    [Parameter(Mandatory = $true)]
    $Region,
    [string] $OMSLocation = "usgovvirginia",
    [ValidateSet("")]
    [string] $Enterprise = "",
    [ValidateSet("")]
    [string] $Department = "",
    [string]
    [ValidateSet("CIE", "")]
    $Account = "",
    [string]
    [ValidateSet("P","I","T","D","L","R")]
    [Parameter(Mandatory = $true)]
    $Environment,
    [string]
    [ValidateSet("IL2","IL4","IL5")]
    [Parameter(Mandatory = $true)]
    $ImpactLevel,
    [string]
	[ValidateLength(2,7)]
    [Parameter(Mandatory = $true)]
    $FunctionalArea,
    [string] 
	[ValidateLength(3,7)]
    $Application,
    [string]
    [ValidateSet("NET","APP","COR")]
	[Parameter(Mandatory = $true)] 
    $ResourceGroupType,
	[string] $Ordinal = "01",
    [string] $StorageAccountName,
    [string]
    [Parameter(Mandatory = $true)]
    $SubscriptionName,
	[string] $CommonServiceName = "CMNSVC",
	[bool] $MultipleSubscriptions = $true,
    [string] $ArtifactStagingDirectory = '.\',
    [switch] $UploadTemplates,
    [switch] $UploadScripts,
    [switch] $UploadDSC,
	[switch] $UploadRunbooks,
	[switch] $UploadModules
)

function Convert-PSObjectToHashTable {
    Param(
        $property
    )
    if($property -eq $null){return $null}
    $propHash = New-Object -TypeName HashTable
    if($property.GetType().Name -eq "PSCustomObject"){
        $property | Get-Member -MemberType *Property | %{
            if($property."$($_.Name)".GetType().Name -match "Object"){
                [void]$propHash.Add($_.Name,(Convert-PSObjectToHashTable $property."$($_.Name)"))
            } #end if
            else{
                [void]$propHash.Add($_.Name,($property."$($_.Name)"))
            }
        } #end foreach
        return $propHash
    } #end if
    elseif($property.GetType().Name -eq "Object[]" -or $property.GetType().Name -match "List"){
        $propArray = New-Object System.Collections.Generic.List[System.Object]
        for($i=0;$i -lt $property.Count;$i++){
            $arrayPropHash = New-Object -TypeName HashTable
            if($property[$i].GetType().Name -eq "Object[]" -or $property.GetType().Name -match "List"){
                [void]$propArray.Add((Convert-PSObjectToHashTable $property[$i]))
            } #end if
            elseif($property[$i].GetType().Name -eq "PSCustomObject"){
                $property[$i] | Get-Member -MemberType *Property | Select Name | %{
                    [void]$arrayPropHash.Add($_.Name,(Convert-PSObjectToHashTable $property[$i]."$($_.Name)"))
                }
                [void]$propArray.Add($arrayPropHash)
            } #end else
            else{
                [void]$propArray.Add($property[$i])
            }
        } #end foreach
        if($propArray.Count -eq 1){
            [array]$pa = $propArray
            return ,$pa
        }
        else{
            [array]$pa = $propArray
            return $pa
        }
    } #end elseif
    else{
        return $property
    } #end else
} #end Convert-PSObjectToHashTable

function Get-KvtAccessPolicy {
	Param(
		$KvtName,
		$RgpName
	)
	Write-Verbose "[INFO]::Retrieving Keyvault Access Policy..."
	$Kvt = (Get-AzureRmKeyVault -VaultName $KvtName -ResourceGroupName $RgpName)
	$KvtPol = $null
	if($Kvt){
		$CceKvtPol = $cceKvt.AccessPolicies
	} #end if
	if($KvtPol){
		Write-Verbose "[SUCCESS]::Retrieved Keyvault Access Policy!"
		$polArray = New-Object System.Collections.Generic.List[System.Object]
		$KvtPol | %{
			$polObj = New-Object -TypeName HashTable
			$polObj.Add('permissions',(New-Object -TypeName HashTable))
			$p = $_
			$p | Get-Member -MemberType Property | %{
				switch($_.Name){
					"TenantId" {$polObj.Add('tenantId',(Convert-PSObjectToHashTable $p.TenantId))}
					"ObjectId" {if($p.ObjectId){$polObj.Add('objectId',(Convert-PSObjectToHashTable $p.ObjectId))}}
					"ApplicationId" {if($p.ApplicationId){$polObj.Add('applicationId',(Convert-PSObjectToHashTable $p.ApplicationId))}}
					"PermissionsToCertificates" {if($p.PermissionsToCertificates){$polObj.permissions.Add('certificates',(Convert-PSObjectToHashTable $p.PermissionsToCertificates))}}
					"PermissionsToKeys" {if($p.PermissionsToKeys){$polObj.permissions.Add('keys',(Convert-PSObjectToHashTable $p.PermissionsToKeys))}}
					"PermissionsToSecrets" {if($p.PermissionsToSecrets){$polObj.permissions.Add('secrets',(Convert-PSObjectToHashTable $p.PermissionsToSecrets))}}
					"PermissionsToStorage" {if($p.PermissionsToStorage){$polObj.permissions.Add('storage',(Convert-PSObjectToHashTable $p.PermissionsToStorage))}}
				} #end switch
			} #end foreach loop
			[void]$polArray.Add($polObj)
		} #end foreach loop
		return $polArray
	} #end if
	else{
		Write-Verbose "[INFO]::No Keyvault Access Policy."
		$KvtPol = New-Object System.Collections.Generic.List[System.Object]
		return $KvtPol
	} #end else
} #end Get-KvtAccessPolicy

function Upload-Artifacts {
	Param(
		[string]$ContainerName,
		[string]$ArtifactsStagingDirectory,
		$ctx
	)

	Write-Output "[INFO]::Uploading [$($ContainerName)]..."
	$stagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot,".\"))
	$stagingDirectory = "$($stagingDirectory)$($ArtifactsStagingDirectory)$($ContainerName)"
	Write-Output "[INFO]::Local $($ContainerName) Path = $($stagingDirectory)"
	$ArtifactFilePaths = Get-ChildItem $stagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
	foreach ($SourcePath in $ArtifactFilePaths) {
		Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Split("\")[-1] `
			-Container $ContainerName -Context $ctx -Force
		Write-Output "[SUCCESS]::Uploaded $($SourcePath)"
	}
} #end Upload-Artifacts

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

#region AUTHENTICATE
$servicePrincipalConnection = $null
if($RunLocally){
    $servicePrincipalConnection = @{}
    $servicePrincipalConnection['TenantId'] =  (Get-AzureRmContext).Tenant.Id
}
else{
	$connectionName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($CommonServiceName)-$($Environment)-$($ImpactLevel)-RunAsConn-$($Ordinal)").ToUpper()
    try
    {
        # Get the connection "AzureRunAsConnection "
        if($ImpactLevel -eq "IL5"){$connectionName = $connectionName.Replace("-$($Region)-","-GV-")}
        $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName

        "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
            -EnvironmentName AzureUSGovernment
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception
            throw $_.Exception
        }
    }
}

Write-Output "Selecting Subscription..."
Select-AzureRmSubscription -SubscriptionName $SubscriptionName
#endregion AUTHENTICATE

#region SET ENVIRONMENT SPECIFIC VARIABLES
$TemplateFile = $null
$TemplateParametersFile = $null
$ResourceGroupName = $null
$domainName = $null
$rootOUPath = $null
$dscNodeConfigurationName = $null

if([string]::IsNullOrEmpty($Application)){
    $TemplateFile = ("$($Environment)-$($ImpactLevel)-$($FunctionalArea)-$($ResourceGroupType).json").ToLower()
    $TemplateParametersFile = ("$($Environment)-$($ImpactLevel)-$($FunctionalArea)-$($ResourceGroupType)-$($Region).parameters.json").ToLower()
    $ResourceGroupName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($ResourceGroupType)-RGP-$($Ordinal)").ToUpper()
    $dscNodeConfigurationName = $FunctionalArea
}
else{
    $TemplateFile = ("$($Environment)-$($ImpactLevel)-$($FunctionalArea)-$($Application)-$($ResourceGroupType).json").ToLower()
    $TemplateParametersFile = ("$($Environment)-$($ImpactLevel)-$($FunctionalArea)-$($Application)-$($ResourceGroupType)-$($Region).parameters.json").ToLower()
    $ResourceGroupName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-$($ResourceGroupType)-RGP-$($Ordinal)").ToUpper()
    $dscNodeConfigurationName = "$($FunctionalArea)_$($Application)"
}

[string] $ResourceGroupLocation = $null
switch($Region){
	"GV" {$ResourceGroupLocation = "usgovvirginia"}
	"GI" {$ResourceGroupLocation = "usgoviowa"}
	"GA" {$ResourceGroupLocation = "usgovarizona"}
	"GT" {$ResourceGroupLocation = "usgovtexas"}
	"DC" {$ResourceGroupLocation = "usdodcentral"}
	"DE" {$ResourceGroupLocation = "usdodeast"}
}
switch($Environment){
    "D" {
        $domainName = "directory.dev.local"
        $rootOUPath = "DC=directory,DC=dev,DC=,DC=local"
        $dscNodeConfigurationName = ("$($dscNodeConfigurationName)_dsc_").ToLower()
        break
    }
    "T" {
        $domainName = "directory.dev.local"
        $rootOUPath = "DC=directory,DC=dev,DC=,DC=local"
        $dscNodeConfigurationName = ("$($dscNodeConfigurationName)_dsc_").ToLower()
        break   
    }
    "P" {
        $domainName = "directory.dev.local"
        $rootOUPath = "DC=directory,DC=dev,DC=,DC=local"
        $dscNodeConfigurationName = ("$($dscNodeConfigurationName)_dsc_").ToLower()
        break
    }
    default {
        $domainName = "lab.local"
        $rootOUPath = "DC=lab,DC=,DC=local"
        $dscNodeConfigurationName = ("$($dscNodeConfigurationName)_dsc_").ToLower()
        break
    }
}
#endregion SET ENVIRONMENT SPECIFIC VARIABLES

#region MANAGE STORAGE ACCOUNT
$StorageAccountName = ""
if($Application){$StorageAccountName = ("$($Region)$($Application)$($Environment)$($ImpactLevel)STG").ToLower()}
else{$StorageAccountName = ("$($Region)$($FunctionalArea)$($Environment)$($ImpactLevel)STG").ToLower()}
$templatesStorageContainerName = "templates"
$dscStorageContainerName = "dsc"
$scriptsStorageContainerName = "scripts"
$softwareStorageContainerName = "software"
$runbooksStorageContainerName = "runbooks"
$modulesStorageContainerName = "modules"
Write-Output "[INFO]::Retrieving Storage Account $($StorageAccountName)"
$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

# Create the storage account if it doesn't already exist
if ($StorageAccount -eq $null) {
	$stgResourceGroupName = $ResourceGroupName
	switch($ResourceGroupType){
		"APP" {$stgResourceGroupName = ($stgResourceGroupName).Replace("-APP-","-COR-")}
		"NET" {$stgResourceGroupName = ($stgResourceGroupName).Replace("-NET-","-COR-")}
	}
    New-AzureRmResourceGroup -Location $ResourceGroupLocation -Name $stgResourceGroupName -Force
    $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $stgResourceGroupName -Location "$ResourceGroupLocation"
} #end if

$StorageAccountBlobEndPoint = $StorageAccount.Context.BlobEndPoint + $templatesStorageContainerName
$templatesStorageContainer = New-AzureStorageContainer -Name $templatesStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$templatesStorageSasToken = (New-AzureStorageContainerSASToken -Container $templatesStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
$dscStorageContainer = New-AzureStorageContainer -Name $dscStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$dscStorageSasToken = (New-AzureStorageContainerSASToken -Container $dscStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
$scriptsStorageContainer = New-AzureStorageContainer -Name $scriptsStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$scriptsStorageSasToken = (New-AzureStorageContainerSASToken -Container $scriptsStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
$softwareStorageContainer = New-AzureStorageContainer -Name $softwareStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$softwareStorageSasToken = (New-AzureStorageContainerSASToken -Container $softwareStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
$runbooksStorageContainer = New-AzureStorageContainer -Name $runbooksStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$runbooksStorageSasToken = (New-AzureStorageContainerSASToken -Container $runbooksStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
$modulesStorageContainer = New-AzureStorageContainer -Name $modulesStorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$modulesStorageSasToken = (New-AzureStorageContainerSASToken -Container $modulesStorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))

$templateUri = "$($StorageAccountBlobEndPoint)/$($TemplateFile)$($templatesStorageSasToken)"
Write-Output "[INFO]::Template Uri: $($templateUri)"
$templateParamsUri = "$($StorageAccountBlobEndPoint)/$($TemplateParametersFile)$($templatesStorageSasToken)"
Write-Output "[INFO]::Template Parameters Uri: $($templateParamsUri)"         
#endregion MANAGE STORAGE ACCOUNT

#region UPLOAD CONTENT
switch($true){
	$UploadTemplates {Upload-Artifacts -ContainerName $templatesStorageContainerName -ArtifactsStagingDirectory "$($ArtifactStagingDirectory)$($Environment.ToLower())\" -ctx $StorageAccount.Context}
	$UploadScripts {Upload-Artifacts -ContainerName $scriptsStorageContainerName -ArtifactsStagingDirectory $ArtifactStagingDirectory -ctx $StorageAccount.Context}
	$UploadDSC {Upload-Artifacts -ContainerName $dscStorageContainerName -ArtifactsStagingDirectory $ArtifactStagingDirectory -ctx $StorageAccount.Context}
	$UploadRunbooks {Upload-Artifacts -ContainerName $runbooksStorageContainerName -ArtifactsStagingDirectory $ArtifactStagingDirectory -ctx $StorageAccount.Context}
	$UploadModules {Upload-Artifacts -ContainerName $modulesStorageContainerName -ArtifactsStagingDirectory $ArtifactStagingDirectory -ctx $StorageAccount.Context}
} #end switch
#endregion UPLOAD CONTENT

#region SET OPTIONAL PARAMETERS
$OptionalParameters = New-Object -TypeName Hashtable
$OptionalParameters.Add("cloudServiceProvider",$CloudServiceProvider)
$OptionalParameters.Add("region",$Region)
$OptionalParameters.Add("enterprise",$Enterprise)
$OptionalParameters.Add("department",$Department)
$OptionalParameters.Add("account",$Account)
$OptionalParameters.Add("functionalArea",$FunctionalArea)
$OptionalParameters.Add("environment",$Environment)
$OptionalParameters.Add("impactLevel",$ImpactLevel)
$OptionalParameters.Add('stgDomainName',".blob.core.usgovcloudapi.net")
$OptionalParameters.Add('templatesSasToken',$templatesStorageSasToken)
if($Application){
    $OptionalParameters.Add("application",$Application)
	$OptionalParameters.Add('cmnSvcName',$CommonServiceName)
	$cmnSvcSubscriptionId = $null
	if($MultipleSubscriptions){
		$cmnSvcSubscriptionId = (Get-AzureRmSubscription -SubscriptionName "$($CloudServiceProvider)-$($Enterprise)-$($Department)-$($Account)-$($CommonServiceName)-$($Environment)-01").Id
	} #end if
    else{$cmnSvcSubscriptionId = (Get-AzureRmSubscription -SubscriptionName $SubscriptionName).Id} #end else
    $OptionalParameters.Add('cmnSvcSubscriptionId',$cmnSvcSubscriptionId)
}
if($FunctionalArea -eq $CommonServiceName){} #end if

if($ResourceGroupType -eq "COR"){
    if($ImpactLevel -eq "IL5"){
        New-AzureRmResourceGroup -Location $OMSLocation -Name ($ResourceGroupName.Replace("-$($Region)-","-GV-")) -Force
    } #end if
    $OptionalParameters.Add('tenant',$servicePrincipalConnection.TenantId)
	$KvtAccessPolicy = @()
	if($Application){
		$KvtAccessPolicy += Get-KvtAccessPolicy -KvtName "$($Region)$($Application)$($Environment)$($ImpactLevel)KVT" -RgpName $ResourceGroupName
	} #end if
	else{
		$KvtAccessPolicy += Get-KvtAccessPolicy -KvtName "$($Region)$($FunctionalArea)$($Environment)$($ImpactLevel)KVT" -RgpName $ResourceGroupName
		$OptionalParameters.Add('runbooksSasToken',(ConvertTo-SecureString $runbooksStorageSasToken -AsPlainText -Force))
		$OptionalParameters.Add('modulesSasToken',(ConvertTo-SecureString $modulesStorageSasToken -AsPlainText -Force))
	} #end else
	$OptionalParameters.Add('kvtAccessPolicies',$KvtAccessPolicy)
} #end if
if($ResourceGroupType -eq "NET"){
} #end if
if($ResourceGroupType -eq "APP"){
    $OptionalParameters.Add('',"")
    $OptionalParameters.Add('domainName',$domainName)
    $OptionalParameters.Add('rootOUPath',$rootOUPath)
    $OptionalParameters.Add('vmRemoteAccessOUPath',"OU=Computers,OU=Remote Access,OU=CmnSvc")
    $OptionalParameters.Add('commonServicesOUName',"CmnSvc")
    $OptionalParameters.Add('azureADOUName',"AzureAD")
    $OptionalParameters.Add('dscNodeConfigurationName',$dscNodeConfigurationName)
    $OptionalParameters.Add('dscConfigurationMode',"ApplyAndMonitor")
    $OptionalParameters.Add('dscConfigurationModeFrequencyMins',60)
    $OptionalParameters.Add('dscRefreshFrequencyMins',120)
    $OptionalParameters.Add('dscRebootNodeIfNeeded',$false)
    $OptionalParameters.Add('dscActionAfterReboot',"ContinueConfiguration")
    $OptionalParameters.Add('dscAllowModuleOverwrite', $true)
    $OptionalParameters.Add('dscSasToken',$dscStorageSasToken)
    $OptionalParameters.Add('dscTimestamp',((Get-Date).ToString()))
    $OptionalParameters.Add('scriptsSasToken',$scriptsStorageSasToken)
    $OptionalParameters.Add('softwareSasToken',$softwareStorageSasToken)
	if($Application){} #end if
} #end if
#endregion SET OPTIONAL PARAMETERS

#region CONVERT PARAMETERS FROM JSON TO HASHTABLE
# Get Parameters File Web Content and Parse
$JsonParameters = @{}
try{
    Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Invoking-RestMethod Get to $($templateParamsUri)"
    $JsonParameters = Invoke-RestMethod -Method Get -Uri $templateParamsUri -Verbose
    Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Begin Parameters File Conversion $($templateParamsUri)"
    if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
        $JsonParameters = $JsonParameters.parameters
    } #end if
    $JsonParameters | Get-Member -MemberType *Property | %{
        $propertyName = $JsonParameters."$($_.Name)" | Get-Member -MemberType *Property | Select Name
        if($propertyName.Name -eq 'value'){                           
            if($JsonParameters."$($_.Name)".value.GetType().Name -match "Object"){
                Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Start Converting Parameter :: $($_.Name)"
                if($OptionalParameters[$_.Name]){$OptionalParameters[$_.Name] = (Convert-PSObjectToHashTable $JsonParameters."$($_.Name)".value)}
                else{$OptionalParameters.Add($_.Name,(Convert-PSObjectToHashTable $JsonParameters."$($_.Name)".value))}
                Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Finish Converting Parameter :: $($_.Name) = $($OptionalParameters[$_.Name])"
            } #end if
            else{
                Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Start Converting Parameter :: $($_.Name)"
                if($OptionalParameters[$_.Name]){$OptionalParameters[$_.Name] = ($JsonParameters | Select -Expand $_.Name -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore)}
                else{$OptionalParameters.Add($_.Name,($JsonParameters | Select -Expand $_.Name -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore))}
                Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Finish Converting Parameter :: $($_.Name) = $($OptionalParameters[$_.Name])"
            } #end else
        } #end if
        elseif($propertyName.Name -eq 'reference'){
            Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Start Converting Parameter :: $($_.Name)"
            if($OptionalParameters[$_.Name]){$OptionalParameters[$_.Name] = (Convert-PSObjectToHashTable $JsonParameters."$($_.Name)".reference)}
            else{$OptionalParameters.Add($_.Name,(Convert-PSObjectToHashTable $JsonParameters."$($_.Name)".reference))}
            Write-Output "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Finish Converting Parameter :: $($_.Name) = $($OptionalParameters[$_.Name])"
        } #end elseif
        else{
            throw "Unable to convert parameter $($_.Name) to HashTable"
        } #end else
    } #end foreach
} #end try
catch{
    throw "[$(((Get-Date).ToUniversalTime()).ToString('MM/dd/yyyy HH:mm:ss.ffff'))] Unable to retrieve content from parameters file: $($templateParamsUri) :: Exception: $($_.Exception)"
} #end catch
#endregion CONVERT PARAMETERS FROM JSON TO HASHTABLE

#region DEPLOY TEMPLATE
# Create or update the resource group
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force

Write-Output "[INFO]::Deploying Resource Group: $($ResourceGroupName)"
Write-Output "[INFO]::Using Template: $($templateUri)"
New-AzureRmResourceGroupDeployment -Name ($TemplateFile.Split('.')[0] + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                    -ResourceGroupName $ResourceGroupName `
                                    -TemplateUri $templateUri `
                                    @OptionalParameters `
                                    -Force -Verbose `
                                    -ErrorVariable ErrorMessages
if ($ErrorMessages) {
    Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
}
#endregion DEPLOY TEMPLATE
