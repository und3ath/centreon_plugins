
Param(
    [parameter(Mandatory=$true)]
    [alias("a")]$mailboxAlias,
    [parameter(Mandatory=$true)]
    [alias("w")]$warnThresold,
    [parameter(Mandatory=$true)]
    [alias("c")]$critThreshold)


if((Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction SilentlyContinue) -eq $null) {
    Add-PsSnapin Microsoft.Exchange.Management.PowerShell.E2010
}

$targetFolderStat = Get-MailboxFolderStatistics -Identity $mailboxAlias | Where-Object { $_.Name -eq "Boîte de réception" }
$itemcountInFolder = $targetFolderStat.ItemsInFolder

$returnCode = 0 # 0 OK | 1 WARNING | 2 CRITICAL | 3 UNKNOWN

if($itemcountInFolder -ge $critThreshold) {
    $returnCode = 2
} elseif($itemcountInFolder -ge $warnThresold) { 
    $returnCode = 1
}

 Write-Host "Item in folder : $itemcountInFolder"
 exit $returnCode



