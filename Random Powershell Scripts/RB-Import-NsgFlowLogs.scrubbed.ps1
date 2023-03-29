Param(
    [ValidateSet("AZ")]
	[string] $CloudServiceProvider = "AZ",
    [ValidateSet("GA","GI","GT","GV","DE","DC")]
    [Parameter(Mandatory = $false)]
    [string] $Region,
    [ValidateSet("DOD")]
    [string] $Enterprise = "DOD",
    [ValidateSet("AF","AR","CG","MC","NV")]
    [string] $Department = "AF",
    [ValidateSet("CIE", "")]
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
	[string] $RunAsConnectionName,
    [Parameter(Mandatory = $true)]
    $SubscriptionName,
    [String] $OmsWorkspaceId,
    [String] $OmsSharedKey,
    [String] $OmsLogType = "NsgFlowLogs",
    [String] $StorageAccountName,   
    [String] $StorageAccountKey,
    [String] $SasToken,
    [String] $ContainerName = "insights-logs-networksecuritygroupflowevent",
    [String] $LogFileSizeThreshhold = 3000000,
    [String] $LargeFileArchiveContainer = "nsg-flowevent-largefilearchive"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

#Requires -Modules AzureRM.OperationalInsights, AzureRM.Storage, Azure.Storage

#region Authenticate to Subscription
try{
	Write-Output "[INFO]::AZURE LOGIN..."
    Login-RunAsConnection -RunAsConnectionName $RunAsConnectionName -Verbose
	Write-Output "[INFO]::LOGGED INTO AZURE."
} #end try
catch {
    $ErrorMessage = "Connection $RunAsConnectionName not found."
    Write-Error -Message "[ERROR]::$($ErrorMessage)"
    throw $_.Exception
} #end catch

Write-Output "[INFO]::Selecting Subscription..."
Select-AzureRmSubscription -SubscriptionName $SubscriptionName
#endregion Authenticate to Subscription

#region Set Prerequisite Variables
$allowedRegions = @{
	"IL4" = @("GV","GT")
	"IL5" = @("DE","DC")
}
# Field with the created time for the records
$TimeStampField = "DateTime"
# Set epoch time for date calculations
$epoch = get-date "1/1/1970"
[string]$stgNameSfx = $null
[hashtable]$omsParams = $null
if($Application){
	$stgNameSfx = "$($Application)$($Environment)$($ImpactLevel)STG"
    $omsParams = @{
        ResourceGroupName = ("$($CloudServiceProvider)-GV-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-$($ResourceGroupType)-RGP-$($Ordinal)").ToUpper()
        Name = ("$($CloudServiceProvider)-GV-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($Application)-OMS-$($Ordinal)").ToUpper()
    }
} #end if
else{
	$stgNameSfx = "$($FunctionalArea)$($Environment)$($ImpactLevel)STG"
    $omsParams = @{
        ResourceGroupName = ("$($CloudServiceProvider)-GV-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-$($ResourceGroupType)-RGP-$($Ordinal)").ToUpper()
        Name = ("$($CloudServiceProvider)-GV-$($Enterprise)-$($Department)-$($Account)-$($FunctionalArea)-$($Environment)-$($ImpactLevel)-OMS-$($Ordinal)").ToUpper()
    }
} #end else

if($OmsWorkspaceId){} #end if
else{
	Write-Output "[INFO]::Getting OMS WorkspaceId..."
	$OmsWorkspaceId = (Get-AzureRmOperationalInsightsWorkspace @omsParams).CustomerId.Guid
	Write-Output "[INFO]::OMS WorkspaceId Retrieved."
} #end else
if($OmsSharedKey){} #end if
else{
	Write-Output "[INFO]::Getting OMS SharedKey..."
	$OmsSharedKey = (Get-AzureRmOperationalInsightsWorkspaceSharedKeys @omsParams).PrimarySharedKey
	Write-Output "[INFO]::OMS SharedKey Retrieved."
} #end else
#endregion Set Prerequisite Variables

#region FUNCTIONS
# Function to create the authorization signature
function Build-Signature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{    
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
} #end function Build-Signature

# Function to create and post the request
function Post-OMSData($customerId, $sharedKey, $body, $logType)
{
    $fileName = $null    
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = Build-Signature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -fileName $fileName `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.us" + $resource + "?api-version=2016-04-01"

    $headers = @{
        "Authorization" = $signature;
        "Log-Type" = $logType;
        "x-ms-date" = $rfc1123date;
        "time-generated-field" = $TimeStampField;
    }

    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body -UseBasicParsing
    return $response.StatusCode
} #end function Post-OMSData

function Split-array
{
  param($inArray,[int]$parts,[int]$size)
  
  if($parts){
    $PartSize = [Math]::Ceiling($inArray.count / $parts)
  } #end if
  if($size){
    $PartSize = $size
    $parts = [Math]::Ceiling($inArray.count / $size)
  } #end if

  $outArray = New-Object 'System.Collections.Generic.List[object]'

  for($i=1; $i -le $parts; $i++){
    $start = (($i-1)*$PartSize)
    $end = (($i)*$PartSize) - 1
    if($end -ge $inArray.count){$end = $inArray.count -1}
	$outArray.Add(@($inArray[$start..$end]))
  } #end for loop
  return ,$outArray
} #end function Split-array

function Archive-LargeLogFile($blob, $context)
{ 
    Write-Output "[INFO]::Starting large file log copy to archive container..."
    Write-Output "[INFO]::Source container Name $($ContainerName)"
    Write-Output "[INFO]::Destination container Name $($LargeFileArchiveContainer)"
    Write-Output "[INFO]::$($context.BlobEndPoint)"
    Write-Output "[INFO]::$($context.ConnectionString)"

    Start-AzureStorageBlobCopy -SrcContainer $ContainerName -SrcBlob $blob.Name -DestContainer $LargeFileArchiveContainer -Context $context -Force
    Write-Output "[INFO]::Complete"
    Write-Output "[INFO]::Setting blob metadata log type..."
    $CloudBlockBlob = $Blob.ICloudBlob
    $CloudBlockBlob.Metadata["OmsLogType"] = $OmsLogType
    $CloudBlockBlob.SetMetadata() 

    Write-Output "[INFO]::Complete"
} #end function Archive-LargeLogFile

# Function to parse through the flow log and upload to OMS, function accepts a standard object
function Submit-FlowData($nsgflowobject)
{
    Write-Output "[INFO]::Submitting Flow Data..."
    $uploadErrors = 0
    $json = @()
    foreach($record in $nsgflowobject.records){
        $time = $record.time
        $resourceId = $record.resourceId
        $splitresourceId = $resourceId.Split("/")
        $sub = $splitresourceId[2]
        $rg = $splitresourceId[4]
        $nsg = $splitresourceId[8]

        foreach($property in $record.properties){
            foreach ($flows in $property.flows){
                $rule = $flows.rule
                foreach($flows2 in $flows.flows){
                    $mac = $flows2.mac
                    foreach($flowTuples in $flows2.flowTuples){
                        $splitflowTuples = $flowTuples.Split(",")
                        $dt = $epoch.AddSeconds($splitflowTuples[0]).ToUniversalTime().ToString()
                        
                        $jsonObjProps = @{
                            SubscriptionId = $sub
                            ResourceGroup = $rg
                            NSG = $nsg
                            Rule = $rule
                            MAC = $mac
                            DateTime = $dt
                            SourceIp = $splitflowTuples[1]
                            DestinationIp = $splitflowTuples[2]
                            SourcePort = $splitflowTuples[3]
                            DestinationPort = $splitflowTuples[4]
                            TcpOrUdp = $splitflowTuples[5]
                            InOrOut = $splitflowTuples[6]
                            AllowOrDeny = $splitflowTuples[7]
                        }
                        $json += @(New-Object pscustomobject -Property $jsonObjProps)
                    } #end foreach loop
                } #end foreach loop
            } #end foreach loop
        } #end foreach loop
    } #end foreach loop
    Write-Output "[INFO]::Count of log records: $($json.Count)"
    
    if($json -ne $null -and $json.Count -gt 0){
        Write-Output "[INFO]::Started split of existing records."
        $uploadRecords = Split-array -inArray $json -size 10000

        Write-Output "[INFO]::Completed split of existing records."
        foreach ($uploadRecord in $uploadRecords){
                Write-Output "[INFO]::Submitting: json object with $($uploadRecord.Count) records."
                $jsonCombined =  ConvertTo-Json $uploadRecord
                $returnCode = Post-OMSData -customerId $OmsWorkspaceId -sharedKey $OmsSharedKey -body ([System.Text.Encoding]::UTF8.GetBytes($jsonCombined)) -logType $OmsLogType
                Write-Output "[INFO]::Return code: $($returnCode)"
                if ($returnCode -ne "200"){
                    $uploadErrors++
                } #end if
        } #end foreach loop
    } #end if
    if ($uploadErrors -eq 0){
        Write-Output "[INFO]::Upload Success..."
        # All uploads were successful, update file metadata so we don't re-upload on subsequent script runs
        Write-Output "[INFO]::Return code 200 on all uploads, updating file metadata"
        $CloudBlockBlob = $Blob.ICloudBlob
        $CloudBlockBlob.Metadata["OmsLogType"] = $OmsLogType
        $CloudBlockBlob.SetMetadata() 
    } #end if
    else {
        # Had one or more errors during upload, log an error and move on
        Write-Output "[INFO]::One or more uploads had errors, please retry upload for file $($blob.Name)"
    } #end else
} #end function Submit-FlowData
#endregion FUNCTIONS

#region Generate Primary and Secondary Region StorageAccount Names
$stgNameArray = @()
if($StorageAccountName){
	$stgNameArray += $StorageAccountName.ToLower()
} #end if
else{
	$allowedRegions[$ImpactLevel] | %{
		$stgNameArray += ("$($_)$($stgNameSfx)").ToLower()
	} #end foreach loop 
} #end else
#endregion Generate Primary and Secondary Region StorageAccount Names

#region Import Content ForEach StorageAccount
foreach($s in $stgNameArray){
	$StorageAccountName = $s
    $StorageAccount = $null

	#region Get StorageAccount
	Write-Output "[INFO]::Getting SAS Token..."
	$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})
	if($StorageAccount){
		$SasToken = New-AzureStorageAccountSASToken -Service Blob -ResourceType Service,Container,Object -Permission rwdl -ExpiryTime (Get-Date).AddHours(6) -Context $StorageAccount.Context
		Write-Output "[INFO]::Retrieved SAS Token."
		#endregion Get StorageAccount

		#region Set StorageAccount Context
		# Loop through the storage and check the files
        Write-Output "[INFO]::Getting Storage Account Context..."
		if($StorageAccountKey){
		   $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
		} #end if
		elseif ($SasToken){
		   $storageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -SasToken $SasToken 
		} #end else
        Write-Output "[INFO]::Retrieved Storage Account Context."
		#endregion Set StorageAccount Context

		#region Retrieve and Import Logs
		# Get all the blobs in the container.
        Write-Output "[INFO]::Getting Storage Account Blobs..."
        try{
            $blobs = Get-AzureStorageBlob -Container $ContainerName -Context $storageContext
            foreach($blob in $blobs){
                # Check to see if the year, month, day, and hour of the flow log (as defined in the blob name) match the current universal time values
                # If they match, it's the current file and we're going to leave it alone
                if( -not (`
                (((Get-Date).ToUniversalTime() | Get-Date -UFormat %Y) -eq ($blob.Name.Split("/")[9].Split("=")[1])) -and `
                (((Get-Date).ToUniversalTime() | Get-Date -UFormat %m) -eq ($blob.Name.Split("/")[10].Split("=")[1])) -and `
                (((Get-Date).ToUniversalTime() | Get-Date -UFormat %d) -eq ($blob.Name.Split("/")[11].Split("=")[1])) -and `
                (((Get-Date).ToUniversalTime() | Get-Date -UFormat %H) -eq ($blob.Name.Split("/")[12].Split("=")[1]))))
                {
                    # Check for metadata to see if it's already been uploaded to OMS
                    if($blob.ICloudBlob.Metadata["OmsLogType"] -ne $OmsLogType){
                        Write-Output "[INFO]::Processing file: $($blob.Name)"

                    if($blob.Length -gt $LogFileSizeThreshhold){
                            Write-Output "[INFO]::Blob with name: $($blob.Name) exceeds file size thresshold for log parsing.  Copying to archive container for more analyis." 
                            Archive-LargeLogFile -blob $blob -context $storageContext
                        } #end if
                        else{
                            if($StorageAccountKey){
                                # Download the file content locally, have to do this as there's currently no way to stick it straight into a variable with just the storage key
                                Get-AzureStorageBlobContent -Container $ContainerName -Context $storageContext -Blob $blob.Name -Force -Destination .
                                # Convert blob content from JSON to a standard object
                                $blobcontent = Get-Content -Raw -Path $blob.Name | ConvertFrom-Json
                                # Call function to process file and upload to OMS
                                Submit-FlowData($blobcontent)
                                # Remove the temp file
                                Remove-Item $blob.Name
                            } #end if
                            elseif($SasToken){
                                # Download the blob content via HTTPS directly to a variable, we can do this because we have SAS token
                                $blobcontent = Invoke-RestMethod -Uri  $($blob.ICloudBlob.Uri.ToString() + $SasToken)
                                # Call function to process file and upload to OMS
                                Submit-FlowData($blobcontent)
                            } #end elseif
                        } #end else
                    } #end if
                } #end if
                else{
                    Write-Output "[INFO]::Not processing current file: $($blob.Name)"
                } #end else
            } #end foreach $blobs
            Write-Output "[INFO]::Retrieved and processed [$($blobs.Count)] Storage Account Blobs."
        } #end try
        catch{
            Write-Output "[INFO]::Retrieved [0] Storage Account Blobs."
            Write-Output "$($_.Exception.Message)"
        } #end catch
		#endregion Retrieve and Import Logs
	} #end if
} #end foreach loop
#endregion Import Content ForEach StorageAccount