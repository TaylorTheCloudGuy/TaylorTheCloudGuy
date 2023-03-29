Param(
    [bool] $RunLocally = $false,
    [ValidateSet("AZ")]
    [string] $CloudServiceProvider = "AZ",
    [string]
    [ValidateSet("GA","GI","GT","GV","DE","DC","DW")]
    [Parameter(Mandatory = $true)]
    $Region,
    [ValidateSet("DOD")]
    [string] $Enterprise = "DOD",
    [ValidateSet("AF")]
    [string] $Department = "AF",
    [string]
    [ValidateSet("")]
    $Account = "",
    [string]
    [ValidateSet("P","I","T","D","L")]
    [Parameter(Mandatory = $true)]
    $Environment,
    [string]
    [ValidateSet("IL2","IL4","IL5")]
    [Parameter(Mandatory = $true)]
    $ImpactLevel,
    [string]
    [Parameter(Mandatory = $true)]
    $FunctionalArea,
    [string] 
    $Application,
	[string] $Ordinal = "01",
    [string] $StorageAccountName,
    [string]
    [Parameter(Mandatory = $true)]
    $SubscriptionName,
	[string] $CommonServiceName = "CMNSVC",
    [string]
    [ValidateSet("DMZ","SVC","AGW","GWY","DAT","CMN","APP","WEB","EGR")]
    $SubnetAbbreviation = "CMN"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

$connectionName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($CommonServiceName)-$($Environment)-$($ImpactLevel)-RunAsConn-$($Ordinal)").ToUpper()
$servicePrincipalConnection = $null
if($RunLocally){
    $servicePrincipalConnection = @{}
    $servicePrincipalConnection['TenantId'] =  (Get-AzureRmContext).Tenant.Id
}
else{
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

Write-Output "INFO:: Selecting Subscription..."
Select-AzureRmSubscription -SubscriptionName $SubscriptionName

$rgpCor = $null
$rgpNet = $null
$vntName = $null
$stgName = $null

if([string]::IsNullOrEmpty($Application)){
    $rgpCor = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-COR-RGP-$($Ordinal)").ToUpper()
    $rgpNet = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-NET-RGP-$($Ordinal)").ToUpper()
    $vntName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-VNT-$($Ordinal)").ToUpper()
    if($StorageAccountName){
        Write-Output "INFO:: Storage Account Name provided."
        $stgName = $StorageAccountName
    } #end if
    else{
        Write-Output "INFO:: Creating Storage Account Name..."
        $stgName = ("$($Region)$($FunctionalArea)$($Environment)$($ImpactLevel)stg").ToLower()
        Write-Output "SUCCESS:: Storage Account Name Created = $($stgName)"
    } #end else
} #end if
else{
    $rgpCor = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-COR-RGP-$($Ordinal)").ToUpper()
    $rgpNet = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-NET-RGP-$($Ordinal)").ToUpper()
    $vntName = ("$($CloudServiceProvider)-$($Region)-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-VNT-$($Ordinal)").ToUpper()
    if($StorageAccountName){
        Write-Output "INFO:: Storage Account Name provided."
        $stgName = $StorageAccountName
    } #end if
    else{
        Write-Output "INFO:: Creating Storage Account Name..."
        $stgName = ("$($Region)$($Application)$($Environment)$($ImpactLevel)stg").ToLower()
        Write-Output "SUCCESS:: Storage Account Name Created = $($stgName)"
    } #end else
} #end else
try{
    $subnet = Get-AzureRmVirtualNetwork -ResourceGroupName $rgpNet -Name $vntName | Get-AzureRmVirtualNetworkSubnetConfig | ?{$_.Name -match "-$($SubnetAbbreviation)-SNT-01"}
    $ruleSet = Get-AzureRmStorageAccountNetworkRuleSet -ResourceGroupName $rgpCor -Name $stgName
    if($ruleSet.VirtualNetworkRules.virtualNetworkResourceId.Contains($subnet.Id)){
        Write-Output "INFO:: Rule for Subnet $($subnet.Id) already exists."
    } #end if
    else{
        Write-Output "INFO:: Adding Rule for Subnet $($subnet.Id) to Storage Account $($stgName)"
        Add-AzureRmStorageAccountNetworkRule -ResourceGroupName $rgpCor -Name $stgName -VirtualNetworkResourceId $subnet.Id
        Write-Output "SUCCESS:: Added Rule for Subnet $($subnet.Id) to Storage Account $($stgName)"
    } #end else
} #end try
catch{
    Write-Error -Message $_.Exception
    throw $_.Exception
} #end catch