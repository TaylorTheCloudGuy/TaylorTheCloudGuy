$a = Import-Csv 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_sf1_feb22_1.csv'
$b = Import-Csv 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_TICKERS_feb22_islisted.csv'
$c = @()
$lastChecked = @()
$isMatched = 0

foreach($rowa in $a){

    Write-Output "$($rowa.ticker) is being checked."    

    if($lastChecked.ticker -ne $rowa.ticker){

        $isMatched = 0
        $lastChecked = $rowa

        foreach($rowb in $b){
    
            if($rowb.ticker -eq $rowa.ticker){
                $c += $rowa
                $isMatched = 1
            }
        }
    } elseif ($lastChecked.ticker -eq $rowa.ticker && $isMatched){
        $c += $rowa
    } elseif ($lastChecked.ticker -eq $rowa.ticker && !$isMatched){
        continue;
    }
}

$c | convertto-csv -NoTypeInformation -Delimiter "," | % {$_ -replace '"',''} | Out-File 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_sf1_feb22_1_isListed_v2.csv'