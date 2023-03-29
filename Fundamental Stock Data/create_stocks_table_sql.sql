Use stocks;

CREATE TABLE sharadar_sf1_feb22 (
[ticker] varchar(max), 
[dimension] varchar(max),
[calendardate] varchar(max),
[datekey] varchar(max),
[reportperiod] varchar(max), 
[lastupdated] varchar(max),
[accoci] bigint DEFAULT NULL,
[assets] bigint DEFAULT NULL,
[assetsavg] bigint DEFAULT NULL,
[assetsc] bigint DEFAULT NULL,
[assetsnc] bigint DEFAULT NULL,
[assetturnover] float DEFAULT NULL,
[bvps] float DEFAULT NULL,
[capex] bigint DEFAULT NULL,
[cashneq] bigint DEFAULT NULL,
[cashnequsd] bigint DEFAULT NULL,
[cor] float DEFAULT NULL, 
[consolinc] bigint DEFAULT NULL,
[currentratio] float DEFAULT NULL,
[de] float DEFAULT NULL,
[debt] bigint DEFAULT NULL,
[debtc] bigint DEFAULT NULL,
[debtnc] bigint DEFAULT NULL,
[debtusd] bigint DEFAULT NULL,
[deferredrev] bigint DEFAULT NULL,
[depamor] bigint DEFAULT NULL,
[deposits] bigint DEFAULT NULL,
[divyield] float DEFAULT NULL, 
[dps] float DEFAULT NULL, 
[ebit] bigint DEFAULT NULL,
[ebitda] bigint DEFAULT NULL,
[ebitdamargin] float DEFAULT NULL,
[ebitdausd] bigint DEFAULT NULL,
[ebitusd] bigint DEFAULT NULL,
[ebt] bigint DEFAULT NULL,
[eps] float DEFAULT NULL,
[epsdil] float DEFAULT NULL,
[epsusd] float DEFAULT NULL, 
[equity] bigint DEFAULT NULL,
[equityavg] bigint DEFAULT NULL,
[equityusd] float DEFAULT NULL,
[ev] bigint DEFAULT NULL,
[evebit] float DEFAULT NULL,
[evebitda] float DEFAULT NULL,
[fcf] bigint DEFAULT NULL,
[fcfps] float DEFAULT NULL, 
[fxusd] bigint DEFAULT NULL,
[gp] bigint DEFAULT NULL,
[grossmargin] float DEFAULT NULL,
[intangibles] bigint DEFAULT NULL,
[intexp] bigint DEFAULT NULL,
[invcap] bigint DEFAULT NULL,
[invcapavg] bigint DEFAULT NULL, 
[inventory] bigint DEFAULT NULL,
[investments] bigint DEFAULT NULL,
[investmentsc] bigint DEFAULT NULL,
[investmentsnc] bigint DEFAULT NULL,
[liabilities] bigint DEFAULT NULL,
[liabilitiesc] bigint DEFAULT NULL,
[liabilitiesnc] bigint DEFAULT NULL,
[marketcap] bigint DEFAULT NULL,
[ncf] bigint DEFAULT NULL,
[ncfbus] bigint DEFAULT NULL,
[ncfcommon] bigint DEFAULT NULL,
[ncfdebt] bigint DEFAULT NULL,
[ncfdiv] bigint DEFAULT NULL,
[ncff] bigint DEFAULT NULL,
[ncfi] bigint DEFAULT NULL,
[ncfinv] bigint DEFAULT NULL,
[ncfo] bigint DEFAULT NULL,
[ncfx] bigint DEFAULT NULL,
[netinc] bigint DEFAULT NULL,
[netinccmn] bigint DEFAULT NULL,
[netinccmnusd] bigint DEFAULT NULL,
[netincdis] bigint DEFAULT NULL,
[netincnci] bigint DEFAULT NULL,
[netmargin] float DEFAULT NULL,
[opex] bigint DEFAULT NULL,
[opinc] bigint DEFAULT NULL,
[payables] bigint DEFAULT NULL,
[payoutratio] float DEFAULT NULL,
[pb] float DEFAULT NULL,
[pe] float DEFAULT NULL,
[pe1] float DEFAULT NULL,
[ppnenet] bigint DEFAULT NULL,
[prefdivis] bigint DEFAULT NULL,
[price] float DEFAULT NULL,  
[ps] float DEFAULT NULL,
[ps1] float DEFAULT NULL, 
[receivables] bigint DEFAULT NULL,
[retearn] bigint DEFAULT NULL,
[revenue] bigint DEFAULT NULL,
[revenueusd] bigint DEFAULT NULL,
[rnd] bigint DEFAULT NULL,
[roa] float DEFAULT NULL, 
[roe] float DEFAULT NULL,
[roic] float DEFAULT NULL,
[ros] float DEFAULT NULL,
[sbcomp] bigint DEFAULT NULL,
[sgna] bigint DEFAULT NULL,
[sharefactor] bigint DEFAULT NULL,
[sharesbas] bigint DEFAULT NULL,
[shareswa] bigint DEFAULT NULL,
[shareswadil] bigint DEFAULT NULL,
[sps] float DEFAULT NULL, 
[tangibles] bigint DEFAULT NULL,
[taxassets] bigint DEFAULT NULL,
[taxexp] bigint DEFAULT NULL,
[taxliabilities] bigint DEFAULT NULL,
[tbvps] float DEFAULT NULL,
[workingcapital] bigint DEFAULT NULL
) ;