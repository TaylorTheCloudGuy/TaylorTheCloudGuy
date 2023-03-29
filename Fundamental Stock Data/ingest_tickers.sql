LOAD DATA infile 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/SHARADAR_TICKERS_feb22.csv'
INTO TABLE stocks.sharadar_tickers_feb22
fields terminated BY ','
lines terminated BY '\n'
IGNORE 1 ROWS
(@atable, @permaticker, @ticker, @cname, @cexchange, @isdelisted, @category, @cusips, @siccode, @sicsector, @sicindustry, @famasector, @famaindustry, @sector, @industry, @scalemarketcap, @scalerevenue, @relatedtickers, @currency, @location, @lastupdated, @firstadded, @firstpricedate, @lastpricedate, @firstquarter, @lastquarter, @secfilings, @companysite)
SET
atable = NULLIF(@atable,''),
permaticker = NULLIF(@permaticker,''),
ticker = NULLIF(@ticker,''),
cname = NULLIF(@cname,''),
cexchange = NULLIF(@cexchange,''),
isdelisted = NULLIF(@isdelisted,''),
category = NULLIF(@category,''),
cusips = NULLIF(@cusips,''),
siccode = NULLIF(@siccode,''),
sicsector = NULLIF(@sicsector,''),
sicindustry = NULLIF(@sicindustry,''),
famasector = NULLIF(@famasector,''),
famaindustry = NULLIF(@famaindustry,''),
sector = NULLIF(@sector,''),
industry = NULLIF(@industry,''),
scalemarketcap = NULLIF(@scalemarketcap,''),
scalerevenue = NULLIF(@scalerevenue,''),
relatedtickers = NULLIF(@relatedtickers,''),
currency = NULLIF(@currency,''),
location = NULLIF(@location,''),
lastupdated = NULLIF(@lastupdated,''),
firstadded = NULLIF(@firstadded,''),
firstpricedate = NULLIF(@firstpricedate,''),
lastpricedate = NULLIF(@lastpricedate,''),
firstquarter = NULLIF(@firstquarter,''),
lastquarter = NULLIF(@lastquarter,''),
secfilings = NULLIF(@secfilings,''),
companysite = NULLIF(@companysite,'')
;