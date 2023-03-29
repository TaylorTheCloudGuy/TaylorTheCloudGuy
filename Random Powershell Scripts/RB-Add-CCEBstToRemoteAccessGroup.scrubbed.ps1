#Requires -Modules ActiveDirectory

Param(
    [Parameter(Mandatory = $true)]
    [string]$AutomationCredentialName,
    [Parameter(Mandatory = $true)]
    [string]$DomainController,
    [Parameter(Mandatory = $true)]
    [string]$FunctionalArea,
    [Parameter(Mandatory = $true)]
    [string]$Application,
	[string] $CommonServiceName = "CMNSVC"
)

$ErrorActionPreference = "Stop"

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

#region Invoke-Command SCriptBlock
Invoke-Command -Session $session -ScriptBlock{
    $computers = $null
    try{
        Write-Output "INFO:: Getting Bastion Hosts..."
        $computers = Get-ADComputer -Filter * | ?{$_.Name -match "BST\d+$($using:Application)"}
        Write-Output "SUCCESS:: Getting Bastion Hosts."
        Write-Output "INFO:: Getting Remote Access Group..."
        $maGroup = Get-ADGroup -Filter * | ?{$_.Name -match "Remote Access $($using:FunctionalArea)-$($using:Application)"}
        Write-Output "SUCCESS:: Getting Remote Access Group."
        Write-Output "INFO:: Adding Bastion Hosts to Remote Access Group..."
        $maGroup | Add-ADGroupMember -Members $computers
        Write-Output "SUCCESS:: Adding Bastion Hosts to Remote Access Group."
    } #end try
    catch{
        Write-Output "FAIL:: Adding Bastion Hosts to Remote Access Group..."
        throw $_.Exception.Message
    } #end catch
    try{
        Write-Output "INFO:: Getting Remote Access $($using:CommonServiceName) Group..."
        $cmnGroup = Get-ADGroup -Filter * | ?{$_.Name -match "Remote Access $($using:CommonServiceName)"}
        Write-Output "SUCCESS:: Getting Remote Access $($using:CommonServiceName) Group."
        Write-Output "INFO:: Adding Bastion Hosts to Remote Access $($using:CommonServiceName) Group..."
        $cmnGroup | Add-ADGroupMember -Members $computers
        Write-Output "SUCCESS:: Adding Bastion Hosts to Remote Access $($using:CommonServiceName) Group."
    } #end try
    catch{
        Write-Output "FAIL:: Adding Bastion Hosts to Remote Access $($using:CommonServiceName) Group..."
        throw $_.Exception.Message
    } #end catch
} #end Script Block
#endregion