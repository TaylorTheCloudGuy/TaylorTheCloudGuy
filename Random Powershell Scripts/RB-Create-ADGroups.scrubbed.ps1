#Requires -Modules ActiveDirectory

Param(
    [ValidateSet("P","I","T","D","L")]
	[Parameter(Mandatory = $true)]
	[string]$Environment,
    [Parameter(Mandatory = $true)]
    [string]$AutomationCredentialName,
    [Parameter(Mandatory = $true)]
    [string]$DomainController,
    [switch]$RemoteAccess,
    [switch]$ReadOnly,
    [switch]$Contributor,
    [switch]$IA,
	[switch]$Artifactory,
	[switch]$TFS,
    [switch]$Subscription
)

function ValidateEnvironment{
    Param(
        [string]$Environment,
        [string]$DomainDN
    )
    Write-Output "INFO:: Validating Environment [$($Environment)]..."
    $domain = $DomainDN.ToLower().Replace("dc=","").Split(',')
    if($domain -contains $envName.ToLower()){
        Write-Output "SUCCESS:: Environment [$($Environment)] and Domain [$($DomainDN)] MATCH!!!"
    } #end if
    else{
        throw "ERROR:: Incorrect Environment Specified...Exiting!!!"
    } #end else
}

$ErrorActionPreference = "Stop"

$groups = @(
    "CMNSVC"
)
$remoteGroups = @(
    "Admins"
    "Auditors"
    "VMT"
)
$artifactoryGroups = @(
    "ART__PLACEHOLDER__MANAGER"
    "ART__PLACEHOLDER__CONTRIBUTOR"
    "ART__PLACEHOLDER__READER"
)
$tfsGroups = @(
    "TFS-_PLACEHOLDER_-Manager"
    "TFS-_PLACEHOLDER_-Contributor"
    "TFS-_PLACEHOLDER_-Reader"
)

#region Get DomainController PSSession
$session = $null
try{
    Write-Output "INFO:: Getting Automation Credential..."
    $credential = Get-AutomationPSCredential -Name $AutomationCredentialName
    Write-Output "INFO:: Automation Credential Retrieved."
    Write-Output "INFO:: Creating PSSession..."
    $session = New-PSSession -ComputerName $DomainController -Credential $credential
    Write-Output "INFO:: PSSession Created."
}
catch{
    throw $_.Exception.Message
}
#endregion
#region Get Domain Name
[string]$path = "OU=Groups,OU=Remote Access,OU=CmnSvc,"
[string]$domainDN = $null
try{
    Write-Output "INFO:: Retrieving the domain name..."
    $domainDN = (Get-ADDomain).DistinguishedName
    Write-Output "INFO:: Domain [$($domainDN)] retrieved."
    $path += $domainDN
    Write-Output "INFO:: Group path [$($path)]."
}
catch{
    Write-Output "FAIL:: Error retrieving the domain name."
    throw $_.Exception.Message
}
#endregion
#region Set Environment and Validate Domain
[string]$envName = $null
switch($Environment){
    "L" {
        $envName = "LAB"
        ValidateEnvironment -Environment $envName -DomainDN $domainDN
        break
    }
    "D" {
        $envName = "DEV"
        ValidateEnvironment -Environment $envName -DomainDN $domainDN
        break
    }
    "T" {
        $envName = "TEST"
        ValidateEnvironment -Environment $envName -DomainDN $domainDN
        break
    }
    "P" {
        $envName = "PROD"
        ValidateEnvironment -Environment $envName -DomainDN $domainDN
        break
    }
    "I" {
        $envName = "INT"
        ValidateEnvironment -Environment $envName -DomainDN $domainDN
        break
    }
}
#endregion
#region Execute ScriptBlock to Create ADGroups
Write-Output "INFO:: Executing ScriptBlock..."
Invoke-Command -Session $session -ScriptBlock{
    function CreateADGroup{
        Param(
            [string]$GroupName,
            [string]$OUPath
        )
        try{
            $grp = Get-ADGroup -Filter * -Properties Name | ?{($_.Name).ToLower() -eq ($GroupName).ToLower()}
            if($grp){Write-Output "INFO:: [$GroupName] already exists."}
            else{
                Write-Output "INFO:: [$GroupName] does not exists, creating group..."
                $newADGroupParams = @{
                    GroupScope = "Global"
                    Name = $GroupName
                    DisplayName = $GroupName
                    GroupCategory = "Security"
                    Path = $OUPath
                }
                New-ADGroup @newADGroupParams
                Write-Output "SUCCESS:: [$GroupName] created."
            }
        }
        catch{
            Write-Output "FAIL:: Create [$GroupName]."
        }

    }
    function AddMemberADGroup{
        Param(
            [string]$GroupName,
            [string]$MemberName
        )
        try{
            Write-Output "INFO:: Retrieving Group [$GroupName] and Member [$MemberName]..."
            $grp = Get-ADGroup -Filter * -Properties Name | ?{($_.Name).ToLower() -eq ($GroupName).ToLower()}
            $mbr = Get-ADGroup -Filter * -Properties Name | ?{($_.Name).ToLower() -eq ($MemberName).ToLower()}
            if($grp -and $mbr){
                if($grp | Get-ADGroupMember | ?{$_.Name.ToLower() -eq $MemberName.ToLower()}){
                    Write-Output "INFO:: Member [$MemberName] already exists in Group [$GroupName]."
                } #end if
                else{
                    Write-Output "INFO:: Adding Member [$MemberName] to Group [$GroupName]..."
                    $grp | Add-ADGroupMember -Members $mbr
                    Write-Output "SUCCESS:: Added Member [$MemberName] to Group [$GroupName]."
                } #end else
            } #end if
            else{
                Write-Output "FAIL:: Add member [$MemberName] to group [$GroupName], one of the groups doesn't exist."
            } #end else
        }
        catch{
            Write-Output "FAIL:: Add member [$MemberName] to group [$GroupName], error retrieving one of the groups."
        }
    }
    #region Remote Access Non-Mission App
    if($using:RemoteAccess){
        $using:remoteGroups | %{
            CreateADGroup -GroupName "Remote Access $($_)" -OUPath $using:path
        } #end foreach loop
    } #end if
    #endregion
    #region IA All CCE
    if($using:IA -and $using:Subscription){
        CreateADGroup -GroupName "IA Auditors-$($using:envName)" -OUPath $using:path
    } #end if
    #endregion
    #region Mission App Groups
    $using:groups | %{
        #region Remote Access Mission Apps
        if($using:RemoteAccess){
            $grpName = "Remote Access $($_)"
            CreateADGroup -GroupName $grpName -OUPath $using:path
        } #end if
        #endregion
        #region ReadOnly Mission Apps
        if($using:ReadOnly){
            if($using:Subscription){
                $grpName = "ReadOnly-CCE-$($_)-$($using:envName)"
                CreateADGroup -GroupName $grpName -OUPath $using:path
                if($_ -ne "CMNSVC"){
                    AddMemberADGroup -GroupName $grpName -MemberName "ReadOnly-CCE-CMNSVC-$($using:envName)"
                } #end if
            } #end if
            $grpName = "ReadOnly-CCE-$($_)"
            CreateADGroup -GroupName "$grpName-APP-$($using:envName)" -OUPath $using:path
            CreateADGroup -GroupName "$grpName-COR-$($using:envName)" -OUPath $using:path
            CreateADGroup -GroupName "$grpName-NET-$($using:envName)" -OUPath $using:path
        } #end if
        #endregion
        #region Contributor Mission Apps
        if($using:Contributor){
            if($using:Subscription){
                $grpName = "Contributor-CCE-$($_)-$($using:envName)"
                CreateADGroup -GroupName $grpName -OUPath $using:path
				AddMemberADGroup -GroupName "ReadOnly-CCE-$($_)-$($using:envName)" -MemberName $grpName
                if($_ -ne "CMNSVC"){
                    AddMemberADGroup -GroupName $grpName -MemberName "Contributor-CCE-CMNSVC-$($using:envName)"
                } #end if
            } #end if
            $grpName = "Contributor-CCE-$($_)"
            CreateADGroup -GroupName "$grpName-APP-$($using:envName)" -OUPath $using:path
			AddMemberADGroup -GroupName "ReadOnly-CCE-$($_)-APP-$($using:envName)" -MemberName "$grpName-APP-$($using:envName)"e
            CreateADGroup -GroupName "$grpName-COR-$($using:envName)" -OUPath $using:path
			AddMemberADGroup -GroupName "ReadOnly-CCE-$($_)-COR-$($using:envName)" -MemberName "$grpName-COR-$($using:envName)"
            CreateADGroup -GroupName "$grpName-NET-$($using:envName)" -OUPath $using:path
			AddMemberADGroup -GroupName "ReadOnly-CCE-$($_)-NET-$($using:envName)" -MemberName "$grpName-NET-$($using:envName)"
        } #end if
        #endregion
        #region IA Mission Apps
        if($using:IA -and $using:Subscription){
            $grpName = "IA-Auditors-CCE-$($_)-$($using:envName)"
            CreateADGroup -GroupName $grpName -OUPath $using:path
            #region Add IA Groups to Appropriate Groups
            AddMemberADGroup -GroupName "ReadOnly-CCE-$($_)-$($using:envName)" -MemberName $grpName
            AddMemberADGroup -GroupName $grpName -MemberName "IA Auditors-$($using:envName)"
            #endregion
        } #end if
        #endregion
		#region Artifactory Mission Apps
        if($using:Artifactory){
			$artPath = ($using:path).Replace("Remote Access","Artifactory")
			foreach($art in $using:artifactoryGroups){
				$grpName = $art.Replace("_PLACEHOLDER_",$_).Replace("-","_")
				CreateADGroup -GroupName $grpName -OUPath $artPath
            } #end foreach loop
        } #end if
        #endregion
		#region TFS Mission Apps
        if($using:TFS){
			$tfsPath = ($using:path).Replace("Remote Access","TFS")
			foreach($tfs in $using:tfsGroups){
				$grpName = $tfs.Replace("_PLACEHOLDER_",$_)
				CreateADGroup -GroupName $grpName -OUPath $tfsPath
            } #end foreach loop
        } #end if
        #endregion
    } #end foreach loop
    #endregion
} #end scriptblock
Write-Output "INFO:: Completed ScriptBlock."
#endregion
