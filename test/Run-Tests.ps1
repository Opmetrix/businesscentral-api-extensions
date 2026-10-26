<#
.SYNOPSIS
    Builds the extension and its test app in a Business Central container, runs the tests and measures code coverage.

.DESCRIPTION
    1. Creates (or reuses) a Business Central sandbox container for the AU country.
    2. Compiles the extension (AU/NZ build, apppp.json) and the test app (test/app.json).
    3. Publishes both apps, runs every test in the test app with code coverage tracking.
    4. Writes the JUnit/XUnit result and the coverage output to $OutputPath and fails the script when a test fails or
       coverage is below $MinimumCoverage.

    Requires Docker (Windows containers) and the BcContainerHelper PowerShell module.
    The tests commit data, so always run them on a disposable container (this script creates one).

.PARAMETER ContainerName
    Name of the container. Default: opmetrix-tests

.PARAMETER Artifact
    BC artifact URL. Default: the latest AU sandbox artifact.

.PARAMETER MinimumCoverage
    Minimum line coverage (percent) of the extension's executable lines. Default: 100

.PARAMETER KeepContainer
    Do not remove the container at the end.

.NOTES
    This script has not been executed yet: the development machine it was written on has no Docker. The first run on a build
    agent may need parameter-name adjustments for the installed BcContainerHelper version.
#>
[CmdletBinding()]
param(
    [string]$ContainerName = 'opmetrix-tests',
    [string]$Artifact = '',
    [double]$MinimumCoverage = 100,
    [string]$OutputPath = '',
    [switch]$KeepContainer
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutputPath) { $OutputPath = Join-Path $scriptRoot '..\output-tests' }
$repoRoot = Resolve-Path (Join-Path $scriptRoot '..')
$mainAppFolder = Join-Path $repoRoot.Path 'app'
$testAppFolder = $scriptRoot
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$OutputPath = (Resolve-Path $OutputPath).Path

if (-not (Get-Module -ListAvailable BcContainerHelper)) {
    Install-Module BcContainerHelper -Force -Scope CurrentUser
}
Import-Module BcContainerHelper

if (-not $Artifact) {
    $Artifact = Get-BcArtifactUrl -type Sandbox -country au -select Latest
}

$credential = New-Object pscredential 'admin', (ConvertTo-SecureString 'P@ssw0rd-Opmetrix-1' -AsPlainText -Force)

try {
    New-BcContainer -accept_eula -containerName $ContainerName -artifactUrl $Artifact -auth UserPassword `
        -credential $credential -includeTestToolkit -includeTestLibrariesOnly -updateHosts `
        -shortcuts None -isolation hyperv

    $appOutput = Join-Path $OutputPath 'apps'
    New-Item -ItemType Directory -Force -Path $appOutput | Out-Null

    # The extension must be compiled with the same preprocessor symbols as the AU/NZ release (app.json).
    $mainApp = Compile-AppInBcContainer -containerName $ContainerName -credential $credential `
        -appProjectFolder $mainAppFolder -appOutputFolder $appOutput
    Publish-BcContainerApp -containerName $ContainerName -appFile $mainApp -skipVerification -sync -install -credential $credential

    $testApp = Compile-AppInBcContainer -containerName $ContainerName -credential $credential `
        -appProjectFolder $testAppFolder -appOutputFolder $appOutput
    Publish-BcContainerApp -containerName $ContainerName -appFile $testApp -skipVerification -sync -install -credential $credential

    $testAppId = (Get-Content (Join-Path $testAppFolder 'app.json') -Raw | ConvertFrom-Json).id
    $coverageFolder = Join-Path $OutputPath 'coverage'
    New-Item -ItemType Directory -Force -Path $coverageFolder | Out-Null

    $testsPassed = Run-TestsInBcContainer -containerName $ContainerName -credential $credential `
        -extensionId $testAppId `
        -XUnitResultFileName (Join-Path $OutputPath 'results.xml') `
        -codeCoverageTrackingType PerRun `
        -produceCodeCoverageMap PerCodeunit `
        -codeCoverageOutputPath $coverageFolder `
        -returnTrueIfAllPassed

    # Coverage: the AL test tool writes a Cobertura file; compare line-rate of the extension's objects with the minimum.
    $coverageFile = Get-ChildItem $coverageFolder -Filter '*.xml' -Recurse | Select-Object -First 1
    $coverage = $null
    if ($coverageFile) {
        [xml]$cobertura = Get-Content $coverageFile.FullName
        $coverage = [math]::Round([double]$cobertura.coverage.'line-rate' * 100, 2)
        Write-Host "Line coverage: $coverage % (minimum $MinimumCoverage %)"
    } else {
        Write-Warning "No coverage file found in $coverageFolder"
    }

    if (-not $testsPassed) { throw 'One or more tests failed.' }
    if ($null -eq $coverage) { throw 'Coverage could not be measured.' }
    if ($coverage -lt $MinimumCoverage) { throw "Coverage $coverage % is below the required $MinimumCoverage %." }
}
finally {
    if (-not $KeepContainer) {
        Remove-BcContainer -containerName $ContainerName -ErrorAction SilentlyContinue
    }
}
