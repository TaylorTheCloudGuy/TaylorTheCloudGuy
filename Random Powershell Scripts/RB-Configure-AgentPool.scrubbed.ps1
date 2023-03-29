Param(
    #[Parameter(Mandatory = $true)]
    #[string]$AutomationCredentialName,
    [ValidateSet("P","I","T","D","L")]
    [Parameter(Mandatory = $true)]
    $Environment,
    [ValidateSet("GA","GI","GT","GV","DE","DC","DW")]
    [Parameter(Mandatory = $true)]
    $Region,
    [Parameter(Mandatory = $true)]
    $FunctionalArea,
    [string] 
    $Application,
    $NumberOfAgents = 1
)

$cceTfsUrl = $null
switch($Environment){
    "D" {$cceTfsUrl = ""}
    "T" {$cceTfsUrl = ""}
    "P" {$cceTfsUrl = ""}
} #end switch

$cceAgentPool = $null
switch($FunctionalArea){
    "CMNSVC" {
        $cceAgentPool = "CMNSVC"
        $Application = "CMNSVC"
    }
    "SHDSVC" {
        $cceAgentPool = "CMNSVC"
        $Application = "CMNSVC"
    }
    default {
        if($Application){$cceAgentPool = "$($FunctionalArea)-$($Application)"}
        else{throw "[FAIL]::No Mission Application Name Specified!!!"}
    }
} #end switch

$cceHosts = @()
for($i=1;$i -le $NumberOfAgents;$i++){
    $cceHosts += "TFA$($i)$($Application)$($Environment)$($Region)"
} #end for

#region CONFIGURE AGENT
$session = $null
try{
    Write-Output "INFO:: Getting Automation Credential..."
    $credential = Get-AutomationPSCredential -Name $AutomationCredentialName
    $ccePassword = $credential.GetNetworkCredential()
    Write-Output "INFO:: Automation Credential Retrieved."
    Write-Output "INFO:: Creating PSSession..."
    foreach($h in $cceHosts){
        #region Execute ScriptBlock on Agent
        $session = New-PSSession -ComputerName $h -Credential $credential
        Write-Output "INFO:: PSSession Created."
        Write-Output "INFO:: Executing ScriptBlock..."
        Invoke-Command -Session $session -ScriptBlock{
            Set-Location "C:\agent"
            #region REMOVE AGENT CONFIG
            $cmd = ".\config.cmd remove --auth negotiate --userName $($using:credential.UserName) --password $($using:ccePassword.Password)"
            Invoke-Expression $cmd | Write-Verbose
            #endregion REMOVE AGENT CONFIG
        
            #region RECONFIG AGENT
            $cmd = ".\config.cmd --unattended --runAsService --work _work --url $($using:cceTfsUrl) --auth negotiate --userName $($using:credential.UserName) --password $($using:ccePassword.Password) --pool $($using:cceAgentPool) --agent $($using:h) --gituseschannel"
            Invoke-Expression $cmd | Write-Verbose
            #endregion RECONFIG AGENT
        } #end Invoke-Command
        #endregion Execute ScriptBlock on Agent
    } #end foreach
}
catch{
    throw $_.Exception.Message
}
#endregion CONFIGURE AGENT