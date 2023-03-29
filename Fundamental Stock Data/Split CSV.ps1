# variable used to store the path of the source CSV file
$sourceCSV = 'C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_sf1_feb22.csv' ;

# variable used to advance the number of the row from which the export starts
$startrow = 0 ;

# counter used in names of resulting CSV files
$counter = 1 ;

# setting the while loop to continue as long as the value of the $startrow variable is smaller than the number of rows in your source CSV file
while ($startrow -lt 2650793)
{

# import of however many rows you want the resulting CSV to contain starting from the $startrow position and export of the imported content to a new file
Import-CSV $sourceCSV | select-object -skip $startrow -first 500000 | Export-CSV "C:\Users\feder\OneDrive\Documents\Stocks Database Project\SHARADAR_sf1_feb22_$($counter).csv" -NoClobber -UseQuotes Never;

# advancing the number of the row from which the export starts
$startrow += 500000 ;

# incrementing the $counter variable
$counter++ ;

}
