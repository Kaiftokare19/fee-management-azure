# Calls the Function App directly (before API Management is set up).
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File tests\test-functions-direct.ps1
# You'll be asked for the Function App's host key (portal: Function App > Functions > App keys > default).
# Nothing here changes data: the only PUT is an invalid amount that the API must reject.

$base = "https://func-feemgmt-kaif-c7dkgqddd6dudpd0.centralindia-01.azurewebsites.net/api"
$key = Read-Host "Paste the Function App 'default' host key"
$headers = @{ "x-functions-key" = $key }

function Show($label, [scriptblock]$call) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    try {
        $result = & $call
        $result | ConvertTo-Json -Depth 5
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        $body = ""
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $body = $reader.ReadToEnd()
        }
        Write-Host "HTTP $status $body" -ForegroundColor Yellow
    }
}

Show "1001 (expect Paid)"           { Invoke-RestMethod "$base/students/1001/fee" -Headers $headers }
Show "1002 (expect Overdue)"        { Invoke-RestMethod "$base/students/1002/fee" -Headers $headers }
Show "1003 (expect Partially Paid)" { Invoke-RestMethod "$base/students/1003/fee" -Headers $headers }
Show "9999 (expect 404)"            { Invoke-RestMethod "$base/students/9999/fee" -Headers $headers }
Show "Overdue list (expect 7)"      { Invoke-RestMethod "$base/manage/students?status=Overdue" -Headers $headers }
Show "Bad status (expect 400)"      { Invoke-RestMethod "$base/manage/students?status=Late" -Headers $headers }
Show "Pay more than total (expect 400)" {
    Invoke-RestMethod -Method Put "$base/manage/students/1003/fee" -Headers $headers `
        -ContentType "application/json" -Body '{"paidAmount": 999999}'
}
Show "No key (expect 401)"          { Invoke-RestMethod "$base/students/1002/fee" }
