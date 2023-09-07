use [WideWorldImportersDW-Standard]
go


alter procedure [sp_CustomerRevenue]
(
    -- Decalring input variables with default values
    @FromYear INT = NULL
    ,@ToYear INT = NULL
    ,@Period VARCHAR(8) = 'Year'
    ,@CustomerID INT = NULL
)
as
begin
  
  -- Creating temp table with customer sales aggregated data
  if object_id('TempDB..#CustomerSales') is not null drop table #CustomerSales
  select
    CustomerID = s.[Customer Key]
    ,CustomerName = c.Customer
    ,[Period] = s.[Invoice Date Key]
    ,Revenue = sum( s.Quantity * s.[Unit Price] )  
  into #CustomerSales
  from [Fact].[Sale] s
  left join [Dimension].[Customer] c on c.[Customer Key] = s.[Customer Key]
  group by s.[Customer Key], c.Customer, s.[Invoice Date Key]

  -- Set @FromYear to the earliest available year if no input
  if @FromYear is null
  begin
      select @FromYear = min( year( [Period] )) from #CustomerSales
  end

  -- Set @ToYear to the latest available year if no input
  if @ToYear is null
  begin
      select @ToYear = max( year( [Period] )) from #CustomerSales
  end


  -- Declaring variables for dynamic table name 
  declare @Table nvarchar(100)
  declare @CustomerName nvarchar(50)
  select @CustomerName = CustomerName from #CustomerSales

  -- Creating dynamic table name
  set @Table = case
                  when @CustomerID is null then 'All'
                  else convert( nvarchar(10), @CustomerID ) + '_' + convert( nvarchar(50), @CustomerName )
               end  + '_'  
               + case 
                    when @FromYear = @ToYear then convert( nvarchar(4), @FromYear) 
                    else convert( nvarchar(4), @FromYear) + '_' + convert( nvarchar(4), @ToYear)
               end + '_' + @Period

  -- Declaring dynamic SQL variable, calculate CustomerRevenue and insert into the table
  declare @SQL nvarchar(MAX)
  set @SQL = N'
      select
          isnull( CustomerID, 0 ) as [CustomerID],
          isnull( CustomerName, ''Unknown'' ) as [CustomerName],
          case
                when ''' + @Period + ''' = ''Month'' or ''' + @Period + ''' = ''M'' then left( datename( month, [Period]), 3) + '' '' + convert( nvarchar(4), year([Period]) )
                when ''' + @Period + ''' = ''Quarter'' OR ''' + @Period + ''' = ''Q'' then ''Q'' + cast( datepart( quarter, [Period]) as nvarchar(1)) + '' '' + convert( nvarchar(4), year([Period]) )
                when ''' + @Period + ''' = ''Year'' OR ''' + @Period + ''' = ''Y'' then convert( nvarchar(4), year([Period]) )
            end as [Period],
          Revenue = SUM( Revenue )
      into ' + quotename(@Table) + '
      from #CustomerSales
      where ( year([Period]) between @FromYear and @ToYear )
          and ( isnull( @CustomerID, 0 ) = 0 or CustomerID = @CustomerID )
      group by CustomerID, CustomerName, [Period]'
    
  exec sp_executesql @SQL, N'@FromYear INT, @ToYear INT, @CustomerID INT', @FromYear, @ToYear, @CustomerID

  -- Dropping temp table
  if object_id('TempDB..#CustomerSales') is not null drop table #CustomerSales
end