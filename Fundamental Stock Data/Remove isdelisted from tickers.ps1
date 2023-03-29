##Import Sharadar tickers to remove isdelisted
#$allTickersData = Import-Csv 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_TICKERS_feb22.csv'
#$listedTickers = @()
#
#foreach ($row in $allTickersData){
#
#    if($row.isdelisted -eq 'N'){
#        $listedTickers += $row
#    }    
#}
#
#$listedTickers | convertto-csv -NoTypeInformation -Delimiter "," | % {$_ -replace '"',''} | Out-File 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_TICKERS_feb22_islisted.csv'

#Use sharadar 'islisted' tickers to remove delisted from sharadar_sf1 file
$sf1Data = Import-Csv 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_sf1_feb22.csv'

$tickerList = $listedTickers.ticker

Write-Output $tickerList