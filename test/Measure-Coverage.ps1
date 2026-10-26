<#
.SYNOPSIS
    Builds the extension and its test app, publishes them to a Business Central online sandbox, runs the tests there and
    reports the code coverage of the extension. No Docker needed.

.DESCRIPTION
    1. Signs in through the Azure CLI (az login) and gets a token for the Business Central API.
    2. Downloads the symbol packages from the sandbox and compiles the extension (app.json, AU/NZ build) and the test app.
       The test app is compiled with the TESTAPP symbol; the extension build never sees the test code.
    3. Publishes both apps to the sandbox through the developer endpoint (the same request VS Code makes on F5).
    4. Starts a test run through the test app's API (opmetrix/testing/v1.0) and turns on coverage tracking for all sessions.
       It then calls the extension's own OData endpoints (customer payment journals, sales headers, sales invoice lines) so the
       page triggers that only run over OData are counted, and finally runs every test of the test app with Microsoft's test
       runner inside the sandbox. Coverage is tracked for the extension objects 50100 to 50149.
    5. Reads the results back, prints coverage per object and writes a report to the output folder:
         coverage-summary.md, coverage-report.json, uncovered-lines.csv, test-results.csv
    6. Exits with 1 when a test fails or the coverage is below -MinimumCoverage.

    Needs: Azure CLI (az) signed in with a user that can use the sandbox, and the AL Language extension for VS Code
    (for alc.exe) unless -SkipBuild is used.

    The tests create sales orders, customers and similar demo data in the sandbox and commit it. Use a sandbox you can throw away.

.PARAMETER Environment
    Business Central environment name. Default: Sandbox (the NZ sandbox in the Opmetrix tenant).

.PARAMETER TenantId
    Azure AD tenant id of the environment. Default: the Opmetrix tenant.

.PARAMETER MinimumCoverage
    Minimum line coverage in percent. Default 100. Use 0 to only report.

.PARAMETER SkipBuild
    Do not compile; publish the apps given by -MainApp and -TestApp.

.PARAMETER SkipPublish
    Do not publish; only run the tests that are already in the sandbox and report.

.PARAMETER MainApp
    Path of the compiled extension .app (used with -SkipBuild).

.PARAMETER TestApp
    Path of the compiled test .app (used with -SkipBuild).

.PARAMETER SkipApiExercise
    Do not call the extension's OData endpoints during the run. Without those calls the page triggers that only run when a page is
    served over OData (OnOpenPage, OnNewRecord, OnModifyRecord and the sales invoice line part) stay uncovered.

.PARAMETER SkipPostedInvoice
    In the API exercise, do not post a sales invoice (posting leaves a posted invoice in the sandbox). The posted-invoice branch of
    the sales invoice line part then stays uncovered.

.PARAMETER RefreshSymbols
    Download the symbol packages again even when they are already in the output folder.

.PARAMETER OutputPath
    Folder for the compiled apps, symbols and reports. Default: output-coverage (in the repository root).

.EXAMPLE
    .\test\Measure-Coverage.ps1

.EXAMPLE
    .\test\Measure-Coverage.ps1 -MinimumCoverage 80 -Environment Sandbox
#>
[CmdletBinding()]
param(
    [string]$Environment = 'Sandbox',
    [string]$TenantId = '43e728f5-a0d9-484d-9971-db0137ca2c70',
    [double]$MinimumCoverage = 100,
    [switch]$SkipBuild,
    [switch]$SkipPublish,
    [string]$MainApp = '',
    [string]$TestApp = '',
    [string]$CompanyId = '',
    [string]$OutputPath = '',
    [switch]$RefreshSymbols,
    [switch]$SkipApiExercise,
    [switch]$SkipPostedInvoice
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 sometimes rejects valid responses with "protocol violation ... ResponseStatusLine"
try {
    $netAssembly = [System.Reflection.Assembly]::GetAssembly([System.Net.Configuration.SettingsSection])
    $settingsType = $netAssembly.GetType('System.Net.Configuration.SettingsSectionInternal')
    $settingsInstance = $settingsType.InvokeMember('Section', 'Static,GetProperty,NonPublic', $null, $null, @())
    $settingsType.GetField('useUnsafeHeaderParsing', 'NonPublic,Instance').SetValue($settingsInstance, $true)
} catch { }
[System.Net.ServicePointManager]::Expect100Continue = $false
# The progress bar makes Invoke-WebRequest downloads very slow in Windows PowerShell 5.1
$ProgressPreference = 'SilentlyContinue'
$testFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $testFolder
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'output-coverage' }
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$OutputPath = (Resolve-Path $OutputPath).Path
$symbolsPath = Join-Path $OutputPath 'symbols'
New-Item -ItemType Directory -Force -Path $symbolsPath | Out-Null

$apiHost = 'https://api.businesscentral.dynamics.com'
$devUrl = "$apiHost/v2.0/$Environment/dev"
$testingApi = "$apiHost/v2.0/$Environment/api/opmetrix/testing/v1.0"
$automationApi = "$apiHost/v2.0/$Environment/api/microsoft/automation/v2.0"

function Write-Step([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }

# ---------------------------------------------------------------- sign in
function Get-BcToken {
    $azCommand = Get-Command az -ErrorAction SilentlyContinue
    if (-not $azCommand) { throw 'Azure CLI (az) was not found. Install it and run: az login' }
    $token = (& az account get-access-token --resource $apiHost --tenant $TenantId --query accessToken -o tsv)
    if ($LASTEXITCODE -ne 0 -or -not $token) {
        throw "Could not get a token. Run: az login --tenant $TenantId"
    }
    return $token.Trim()
}

$script:token = Get-BcToken
function Get-Headers { @{ Authorization = "Bearer $($script:token)"; Accept = 'application/json' } }

function Invoke-BcCurl {
    # Windows PowerShell 5.1 sometimes cannot parse a valid response ("protocol violation"); curl.exe (Windows 10 and later) can
    param([string]$Method, [string]$Url, $Body)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) { throw 'curl.exe not found for the fallback request' }
    $arguments = @('-s', '-S', '-X', $Method.ToUpper(), '-H', "Authorization: Bearer $($script:token)", '-H', 'Accept: application/json', '-H', 'If-Match: *', '--max-time', '600')
    $bodyFile = $null
    if ($null -ne $Body) {
        $bodyFile = [System.IO.Path]::GetTempFileName()
        [System.IO.File]::WriteAllText($bodyFile, ($Body | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding($false)))
        $arguments += @('-H', 'Content-Type: application/json', '--data-binary', "@$bodyFile")
    }
    $arguments += $Url
    try {
        $text = (& $curl.Source @arguments) -join "`n"
    } finally {
        if ($bodyFile) { Remove-Item $bodyFile -ErrorAction SilentlyContinue }
    }
    if (-not $text) { return $null }
    $parsed = $text | ConvertFrom-Json
    if ($parsed.error) { throw "$Method $Url failed: $($parsed.error.message)" }
    return $parsed
}

function Invoke-Bc {
    param([string]$Method, [string]$Url, $Body = $null, [int]$TimeoutSec = 900, [int]$Attempts = 8)
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $headers = Get-Headers
        $headers['If-Match'] = '*'
        $arguments = @{ Method = $Method; Uri = $Url; Headers = $headers; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
        if ($null -ne $Body) {
            $arguments.Body = ($Body | ConvertTo-Json -Compress)
            $arguments.ContentType = 'application/json'
        }
        try {
            return Invoke-RestMethod @arguments
        } catch {
            $details = ''
            if ($_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $details = $reader.ReadToEnd()
                } catch { }
            }
            # Right after publishing, the service can briefly fail while its app metadata cache catches up
            if ($_.Exception.Message -match 'protocol violation') {
                return (Invoke-BcCurl -Method $Method -Url $Url -Body $Body)
            }
            $transient = ($details -match 'metadata cache|package blob|temporarily|try again') -or ($_.Exception.Message -match 'timed out|503|502|504')
            if ($transient -and $attempt -lt $Attempts -and $Method -eq 'Get') {
                Write-Host "   waiting for the service (attempt $attempt of $Attempts)..." -ForegroundColor DarkYellow
                Start-Sleep -Seconds 15
                continue
            }
            throw "$Method $Url failed: $($_.Exception.Message) $details"
        }
    }
}

function Get-AllPages([string]$Url) {
    $result = @()
    while ($Url) {
        $page = Invoke-Bc -Method Get -Url $Url
        if ($page.value) { $result += $page.value }
        $Url = $page.'@odata.nextLink'
    }
    return $result
}

# ---------------------------------------------------------------- build
function Get-AlCompiler {
    $extensionRoots = @("$env:USERPROFILE\.vscode\extensions", "$env:USERPROFILE\.vscode-insiders\extensions")
    foreach ($root in $extensionRoots) {
        if (-not (Test-Path $root)) { continue }
        $folder = Get-ChildItem $root -Filter 'ms-dynamics-smb.al-*' -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($folder) {
            $compiler = Join-Path $folder.FullName 'bin\win32\alc.exe'
            if (-not (Test-Path $compiler)) { $compiler = Join-Path $folder.FullName 'bin\alc.exe' }
            if (Test-Path $compiler) { return $compiler }
        }
    }
    throw 'alc.exe not found. Install the AL Language extension for VS Code, or use -SkipBuild with -MainApp and -TestApp.'
}

function Get-Symbols {
    # id, name, version. The sandbox returns the package of the installed version.
    $packages = @(
        @('8874ed3a-0643-4247-9ced-7a7002f7135d', 'System', '29.0.0.0'),
        @('c1335042-3002-4257-bf8a-75c898ccb1b8', 'Application', '29.0.0.0'),
        @('437dbf0e-84ff-417a-965d-ed2bb9650972', 'Base Application', '29.0.0.0'),
        @('f3552374-a1f2-4356-848e-196002525837', 'Business Foundation', '29.0.0.0'),
        @('63ca2fa4-4f03-4f2b-a480-172fef340d3f', 'System Application', '29.0.0.0'),
        @('e7320ebb-08b3-4406-b1ec-b4927d3e280b', 'Any', '29.0.0.0'),
        @('dd0be2ea-f733-4d65-bb34-a28f4624fb14', 'Library Assert', '29.0.0.0'),
        @('23de40a6-dfe8-4f80-80db-d70f83ce8caf', 'Test Runner', '29.0.0.0')
    )
    foreach ($package in $packages) {
        $file = Join-Path $symbolsPath ("Microsoft_{0}.app" -f $package[1])
        if ((Test-Path $file) -and -not $RefreshSymbols) {
            Write-Host ("   symbols: {0} (already downloaded)" -f $package[1])
            continue
        }
        $url = "$devUrl/packages?publisher=Microsoft&appName=$([uri]::EscapeDataString($package[1]))&versionText=$($package[2])&appId=$($package[0])&tenant=$TenantId"
        Invoke-WebRequest -Uri $url -Headers (Get-Headers) -OutFile $file -UseBasicParsing -TimeoutSec 900 | Out-Null
        Write-Host ("   symbols: {0} ({1:N0} KB)" -f $package[1], ((Get-Item $file).Length / 1KB))
    }
}

function Invoke-Compile([string]$ProjectFolder, [string]$OutFile) {
    $compiler = Get-AlCompiler
    $output = & $compiler "/project:$ProjectFolder" "/packagecachepath:$symbolsPath" "/out:$OutFile" 2>&1
    $output | Where-Object { $_ -match 'error ' } | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $OutFile)) {
        throw "Compilation of $ProjectFolder failed. Full output:`n$($output -join "`n")"
    }
    Write-Host ("   built: {0} ({1:N0} KB)" -f (Split-Path $OutFile -Leaf), ((Get-Item $OutFile).Length / 1KB))
}

if (-not $SkipBuild -and -not $SkipPublish) {
    Write-Step 'Downloading symbols'
    Get-Symbols

    Write-Step 'Compiling the extension (AU/NZ build) and the test app'
    $mainConfig = Get-Content (Join-Path $repoRoot 'app.json') -Raw | ConvertFrom-Json
    $MainApp = Join-Path $symbolsPath ("{0}_{1}_{2}.app" -f $mainConfig.publisher, $mainConfig.name, $mainConfig.version)
    Invoke-Compile -ProjectFolder $repoRoot -OutFile $MainApp
    $testConfig = Get-Content (Join-Path $testFolder 'app.json') -Raw | ConvertFrom-Json
    $TestApp = Join-Path $OutputPath ("{0}_{1}_{2}.app" -f $testConfig.publisher, $testConfig.name, $testConfig.version)
    Invoke-Compile -ProjectFolder $testFolder -OutFile $TestApp
}

# ---------------------------------------------------------------- publish
function Publish-App([string]$AppFile) {
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromMinutes(15)
    $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $script:token)
    $content = New-Object System.Net.Http.MultipartFormDataContent
    $stream = [System.IO.File]::OpenRead($AppFile)
    try {
        $fileContent = New-Object System.Net.Http.StreamContent($stream)
        $fileContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue('application/octet-stream')
        $content.Add($fileContent, 'file', (Split-Path $AppFile -Leaf))
        $url = "$devUrl/apps?tenant=$TenantId&SchemaUpdateMode=synchronize&DependencyPublishingOption=default"
        $response = $client.PostAsync($url, $content).Result
        $text = $response.Content.ReadAsStringAsync().Result
        if (-not $response.IsSuccessStatusCode) {
            throw "Publishing $(Split-Path $AppFile -Leaf) failed: HTTP $([int]$response.StatusCode) $text"
        }
        Write-Host ("   published: {0}" -f (Split-Path $AppFile -Leaf))
    } finally {
        $stream.Dispose()
        $client.Dispose()
    }
}

if (-not $SkipPublish) {
    if (-not $MainApp -or -not (Test-Path $MainApp)) { throw "Extension app not found: '$MainApp' (use -MainApp)" }
    if (-not $TestApp -or -not (Test-Path $TestApp)) { throw "Test app not found: '$TestApp' (use -TestApp)" }
    Write-Step "Publishing to $Environment"
    Publish-App $MainApp
    Publish-App $TestApp
}

# ---------------------------------------------------------------- run
if (-not $CompanyId) {
    $companies = (Invoke-Bc -Method Get -Url "$automationApi/companies").value
    $company = $companies | Where-Object { $_.name -like '*CRONUS*' } | Select-Object -First 1
    if (-not $company) { $company = $companies | Select-Object -First 1 }
    $CompanyId = $company.id
    Write-Host "Company: $($company.name)"
}
$companyApi = "$testingApi/companies($CompanyId)"

function Invoke-Tolerant([scriptblock]$Action, [string]$Description) {
    # The API exercise only needs the extension code to run; an error response is fine (and expected for the negative cases)
    try {
        & $Action | Out-Null
        Write-Host "   ok: $Description"
    } catch {
        Write-Host "   (error response, expected or ignored) ${Description}: $($_.Exception.Message.Split("`n")[0])" -ForegroundColor DarkGray
    }
}

function Invoke-ApiExercise {
    $opmetrix = "$apiHost/v2.0/$Environment/api/opmetrix/opmetrix/v1.0/companies($CompanyId)"
    $standard = "$apiHost/v2.0/$Environment/api/v2.0/companies($CompanyId)"

    # Customer payment journals: GET runs OnOpenPage, POST runs OnNewRecord, the post action runs the page's post procedure
    Invoke-Tolerant { Invoke-Bc -Method Get -Url "$opmetrix/customerPaymentJournals" } 'list customer payment journals (OnOpenPage)'
    $batchId = $null
    try {
        $batch = Invoke-Bc -Method Post -Url "$opmetrix/customerPaymentJournals" -Body @{ code = 'OPMAPI'; displayName = 'Opmetrix API exercise' }
        $batchId = $batch.id
        Write-Host '   ok: create customer payment journal (OnNewRecord)'
    } catch {
        Write-Host "   (journal create failed: $($_.Exception.Message.Split("`n")[0]))" -ForegroundColor DarkGray
    }
    if ($batchId) {
        Invoke-Tolerant { Invoke-Bc -Method Post -Url "$opmetrix/customerPaymentJournals($batchId)/Microsoft.NAV.post" -Body @{} } 'post an empty journal (nothing to post)'
        Invoke-Tolerant { Invoke-Bc -Method Delete -Url "$opmetrix/customerPaymentJournals($batchId)" } 'delete the journal again'
    }

    $customer = (Invoke-Bc -Method Get -Url ("$standard/customers?`$filter=" + [uri]::EscapeDataString("number eq '10000'"))).value | Select-Object -First 1
    $item = (Invoke-Bc -Method Get -Url ("$standard/items?`$filter=" + [uri]::EscapeDataString("number eq '1896-S'"))).value | Select-Object -First 1
    if (-not $customer -or -not $item) {
        Write-Host '   (demo customer 10000 or item 1896-S not found: skipping the sales header and invoice calls)' -ForegroundColor Yellow
        return
    }

    # Sales header: PATCH runs OnModifyRecord (valid change and the "number cannot be changed" error)
    $order = Invoke-Bc -Method Post -Url "$standard/salesOrders" -Body @{ customerId = $customer.id }
    Invoke-Tolerant { Invoke-Bc -Method Get -Url "$opmetrix/salesHeaders($($order.id))" } 'get sales header'
    Invoke-Tolerant { Invoke-Bc -Method Patch -Url "$opmetrix/salesHeaders($($order.id))" -Body @{ yourReference = 'Opmetrix API exercise' } } 'patch your reference (OnModifyRecord)'
    Invoke-Tolerant { Invoke-Bc -Method Patch -Url "$opmetrix/salesHeaders($($order.id))" -Body @{ number = 'CHANGED' } } 'patch number (error expected)'
    Invoke-Tolerant { Invoke-Bc -Method Delete -Url "$standard/salesOrders($($order.id))" } 'delete the exercise order'

    # Sales invoice lines (page 50138 through page 50137): unposted invoice, then the posted one
    try {
        $invoice = Invoke-Bc -Method Post -Url "$standard/salesInvoices" -Body @{ customerId = $customer.id }
        Invoke-Bc -Method Post -Url "$standard/salesInvoices($($invoice.id))/salesInvoiceLines" -Body @{ lineType = 'Item'; itemId = $item.id; quantity = 1 } | Out-Null
        Invoke-Tolerant { Invoke-Bc -Method Get -Url "$opmetrix/salesInvoices($($invoice.id))/salesInvoiceLines" } 'sales invoice lines of an unposted invoice'
        # a single line by its id runs the id filter branch of the line part
        $lineList = Invoke-Bc -Method Get -Url "$opmetrix/salesInvoices($($invoice.id))/salesInvoiceLines"
        if ($lineList.value -and $lineList.value[0].id) {
            $lineId = $lineList.value[0].id
            Invoke-Tolerant { Invoke-Bc -Method Get -Url "$opmetrix/salesInvoices($($invoice.id))/salesInvoiceLines($lineId)" } 'one sales invoice line by id'
        }
        # an invoice without lines
        $emptyInvoice = Invoke-Bc -Method Post -Url "$standard/salesInvoices" -Body @{ customerId = $customer.id }
        Invoke-Tolerant { Invoke-Bc -Method Get -Url "$opmetrix/salesInvoices($($emptyInvoice.id))/salesInvoiceLines" } 'sales invoice lines of an invoice without lines'
        Invoke-Tolerant { Invoke-Bc -Method Delete -Url "$standard/salesInvoices($($emptyInvoice.id))" } 'delete the empty exercise invoice'
        if ($SkipPostedInvoice) {
            Invoke-Tolerant { Invoke-Bc -Method Delete -Url "$standard/salesInvoices($($invoice.id))" } 'delete the exercise invoice'
        } else {
            Invoke-Tolerant { Invoke-Bc -Method Post -Url "$standard/salesInvoices($($invoice.id))/Microsoft.NAV.post" -Body @{} } 'post the exercise invoice'
            Invoke-Tolerant { Invoke-Bc -Method Get -Url "$opmetrix/salesInvoices($($invoice.id))/salesInvoiceLines" } 'sales invoice lines of the posted invoice'
        }
    } catch {
        Write-Host "   (sales invoice part of the exercise failed: $($_.Exception.Message.Split("`n")[0]))" -ForegroundColor Yellow
    }
}

Write-Step 'Running the tests in the sandbox (this can take several minutes)'
$waitForExercise = -not $SkipApiExercise
$run = Invoke-Bc -Method Post -Url "$companyApi/testRuns" -Body @{ message = "coverage run $(Get-Date -Format s)"; waitForExercise = [bool]$waitForExercise }
$runUrl = "$companyApi/testRuns($($run.id))"
if ($waitForExercise) {
    # The run action starts tracking all sessions and then waits for "exerciseDone", so it is started without waiting for it
    Add-Type -AssemblyName System.Net.Http
    $runClient = New-Object System.Net.Http.HttpClient
    $runClient.Timeout = [TimeSpan]::FromMinutes(40)
    $runClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $script:token)
    $runClient.DefaultRequestHeaders.Add('If-Match', '*')
    $runContent = New-Object System.Net.Http.StringContent('{}', [System.Text.Encoding]::UTF8, 'application/json')
    $runTask = $runClient.PostAsync("$runUrl/Microsoft.NAV.run", $runContent)
    # wait until the run reports that tracking is on
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 2
        $state = Invoke-Bc -Method Get -Url $runUrl
        if ($state.status -eq 'Waiting') { break }
    }
    if ($state.status -ne 'Waiting') { throw "The run did not start tracking (status: $($state.status) $($state.message))" }
    Write-Host 'Coverage tracking started for all sessions; calling the extension OData endpoints:'
    try {
        Invoke-ApiExercise
    } catch {
        Write-Host "   (API exercise stopped early: $($_.Exception.Message.Split("`n")[0]))" -ForegroundColor Yellow
    } finally {
        Invoke-Bc -Method Post -Url "$runUrl/Microsoft.NAV.exerciseDone" -Body @{} | Out-Null
    }
    Write-Host 'Waiting for the tests to finish...'
    $response = $runTask.Result
    if (-not $response.IsSuccessStatusCode) {
        throw "The run action failed: HTTP $([int]$response.StatusCode) $($response.Content.ReadAsStringAsync().Result)"
    }
    $runClient.Dispose()
} else {
    Invoke-Bc -Method Post -Url "$runUrl/Microsoft.NAV.run" -Body @{} | Out-Null
}
$run = Invoke-Bc -Method Get -Url $runUrl
Write-Host ("Status: {0}; tests {1}, passed {2}, failed {3}" -f $run.status, $run.testsTotal, $run.testsPassed, $run.testsFailed)
if ($run.status -ne 'Finished') { throw "The test run did not finish: $($run.status) $($run.message)" }

# ---------------------------------------------------------------- results
Write-Step 'Reading results'
$entry = $run.entryNo
$results = Get-AllPages ("$companyApi/testResults?`$filter=" + [uri]::EscapeDataString("runEntryNo eq $entry"))
$lines = Get-AllPages ("$companyApi/coverageLines?`$filter=" + [uri]::EscapeDataString("runEntryNo eq $entry"))

# Object names from the source files
$objectNames = @{}
Get-ChildItem $repoRoot -Filter '*.al' -File | ForEach-Object {
    $head = Get-Content $_.FullName -TotalCount 12
    foreach ($text in $head) {
        if ($text -match '^\s*(codeunit|page|query)\s+(\d+)\s+"?([^"{]+?)"?\s*$') {
            $objectNames["$($Matches[1].ToLower())$($Matches[2])"] = $Matches[3]
            break
        }
    }
}

$byObject = $lines | Group-Object { "$($_.objectType)|$($_.objectId)" } | ForEach-Object {
    $first = $_.Group[0]
    $total = $_.Count
    $covered = @($_.Group | Where-Object { $_.hits -gt 0 }).Count
    [pscustomobject]@{
        Type    = $first.objectType
        Id      = [int]$first.objectId
        Name    = $objectNames["$($first.objectType.ToLower())$($first.objectId)"]
        Lines   = $total
        Covered = $covered
        Pct     = [math]::Round(100.0 * $covered / $total, 1)
    }
} | Sort-Object Id

$totalLines = @($lines).Count
$coveredLines = @($lines | Where-Object { $_.hits -gt 0 }).Count
$coverage = if ($totalLines -gt 0) { [math]::Round(100.0 * $coveredLines / $totalLines, 2) } else { 0 }
$failed = @($results | Where-Object { $_.result -ne 'Success' })

# Reports
$results | Select-Object codeunitId, codeunitName, functionName, result, errorMessage |
    Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath 'test-results.csv')
$lines | Where-Object { $_.hits -eq 0 } | Sort-Object objectId, lineNo |
    Select-Object objectType, objectId, lineNo, lineText |
    Export-Csv -NoTypeInformation -Path (Join-Path $OutputPath 'uncovered-lines.csv')
[pscustomobject]@{
    environment   = $Environment
    runEntryNo    = $entry
    testsTotal    = $run.testsTotal
    testsPassed   = $run.testsPassed
    testsFailed   = $run.testsFailed
    linesTotal    = $totalLines
    linesCovered  = $coveredLines
    coveragePct   = $coverage
    objects       = $byObject
} | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $OutputPath 'coverage-report.json') -Encoding UTF8

$markdown = New-Object System.Collections.Generic.List[string]
$markdown.Add('# Code coverage')
$markdown.Add('')
$markdown.Add("* Environment: $Environment")
$markdown.Add("* Tests: $($run.testsPassed) passed, $($run.testsFailed) failed, $($run.testsTotal) total")
$markdown.Add("* **Line coverage: $coverage %** ($coveredLines of $totalLines executable lines)")
$markdown.Add('')
$markdown.Add('| Object | Name | Lines | Covered | % |')
$markdown.Add('|---|---|---:|---:|---:|')
foreach ($object in $byObject) {
    $markdown.Add("| $($object.Type) $($object.Id) | $($object.Name) | $($object.Lines) | $($object.Covered) | $($object.Pct) |")
}
$markdown | Set-Content -Path (Join-Path $OutputPath 'coverage-summary.md') -Encoding UTF8

Write-Host ""
$byObject | Format-Table Type, Id, Name, Lines, Covered, Pct -AutoSize | Out-String | Write-Host
Write-Host ("Tests: {0} passed, {1} failed, {2} total" -f $run.testsPassed, $run.testsFailed, $run.testsTotal)
foreach ($test in $failed) {
    Write-Host ("  FAILED {0}.{1}: {2}" -f $test.codeunitName, $test.functionName, $test.errorMessage) -ForegroundColor Red
}
Write-Host ("Line coverage: {0} % ({1} of {2} executable lines)" -f $coverage, $coveredLines, $totalLines) -ForegroundColor Green
Write-Host "Reports written to $OutputPath"

if ($failed.Count -gt 0) { Write-Host 'One or more tests failed.' -ForegroundColor Red; exit 1 }
if ($coverage -lt $MinimumCoverage) {
    Write-Host "Coverage $coverage % is below the required $MinimumCoverage %." -ForegroundColor Red
    exit 1
}
exit 0
