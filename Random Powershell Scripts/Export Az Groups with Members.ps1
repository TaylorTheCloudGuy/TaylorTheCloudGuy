#Stole this from Stack Overflow and made modifications to fit the request for exporting excel doc that contains AAD Groups and Members. Run on the Cloud Shell. 

Connect-AzureAD
$groups=Get-AzureADGroup -All $true
$resultsarray =@()
ForEach ($group in $groups){
    $members = Get-AzureADGroupMember -ObjectId $group.ObjectId -All $true 
    ForEach ($member in $members){
       $UserObject = new-object PSObject
       $UserObject | add-member  -membertype NoteProperty -name "Group Name" -Value $group.DisplayName
       $UserObject | add-member  -membertype NoteProperty -name "UserPrinicpalName" -Value $member.UserPrincipalName
       $resultsarray += $UserObject
    }
}
$resultsarray | Export-Csv -Encoding UTF8  -Delimiter "," -Path "./output.csv" -NoTypeInformation 