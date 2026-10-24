# Exports the needed Access tables to JSON (read-only; the .accdb is never modified).
# Usage: powershell -File tool\export_access.ps1 -Accdb D:\file.accdb -Out out.json
param([Parameter(Mandatory)][string]$Accdb, [Parameter(Mandatory)][string]$Out)
$ErrorActionPreference = 'Stop'
$copy = Join-Path $env:TEMP ("export_" + [guid]::NewGuid().ToString('N') + '.accdb')
Copy-Item $Accdb $copy
$c = New-Object System.Data.OleDb.OleDbConnection "Provider=Microsoft.ACE.OLEDB.16.0;Data Source=$copy;Mode=Read"
$c.Open()
function Q($sql) {
  $dt = New-Object System.Data.DataTable
  (New-Object System.Data.OleDb.OleDbDataAdapter $sql, $c).Fill($dt) | Out-Null
  $dt.Rows
}
function S($v) { if ($v -is [DBNull] -or $null -eq $v) { '' } else { "$v".Trim() } }
function D($v) { if ($v -is [DBNull] -or $null -eq $v) { $null } else { ([datetime]$v).ToString('yyyy-MM-ddTHH:mm:ss') } }

$data = [ordered]@{
  projects = @(Q 'SELECT ProjectID, ProjectName FROM Projects ORDER BY ProjectID' | % {
    [ordered]@{ id = [int]$_.ProjectID; name = (S $_.ProjectName) } })
  incomes = @(Q 'SELECT CertificateID, ProjectID, samavatAmount FROM ProjectIncome ORDER BY CertificateID' | % {
    [ordered]@{ id = [int]$_.CertificateID; projectId = [int]$_.ProjectID; amount = [double]$_.samavatAmount } })
  costs = @(Q 'SELECT CostID, ProjectID, dyear, dmonth, dday, Amount, Payto, Description, Selected, InsertDate, Okdate FROM ProjectCosts ORDER BY CostID' | % {
    [ordered]@{ id = [int]$_.CostID; projectId = [int]$_.ProjectID
      dyear = (S $_.dyear); dmonth = (S $_.dmonth); dday = (S $_.dday)
      amount = [double]$_.Amount; payto = (S $_.Payto); description = (S $_.Description)
      selected = [bool]$_.Selected; insertDate = (D $_.InsertDate); okdate = (D $_.Okdate) } })
}
$c.Close(); $c.Dispose()
[IO.File]::WriteAllText($Out, ($data | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
"Exported: $($data.projects.Count) projects, $($data.incomes.Count) incomes, $($data.costs.Count) costs -> $Out"
[GC]::Collect(); [GC]::WaitForPendingFinalizers()
Remove-Item $copy -ErrorAction SilentlyContinue   # best effort; it is only a temp copy
