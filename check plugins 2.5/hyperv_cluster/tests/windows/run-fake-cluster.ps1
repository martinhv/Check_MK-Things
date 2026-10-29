# License: GNU General Public License v2

# Runs the agent plug-ins hyperv_cluster.ps1 and hyperv_host_csv_io.ps1 against the fake
# failover cluster of fake-cluster.ps1 and prints their agent output.
#
# Manually:  .\run-fake-cluster.ps1 -LabDirectory . -Scenario node-down, disk-offline
# As agent plug-in: copy this file to C:\ProgramData\checkmk\agent\plugins. Without
# -Scenario, the scenarios are read from scenario.txt in the lab directory.
#
# Each plug-in runs in its own PowerShell process, so it starts with a clean session
# and an "exit" in a plug-in does not end this script.

[CmdletBinding()]
param(
    [string[]]$Scenario,
    [string]$LabDirectory = (Join-Path $env:ProgramData "checkmk\agent\fake_cluster")
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$LabDirectory = (Resolve-Path $LabDirectory).Path

if (-not $Scenario) {
    $scenarioFile = Join-Path $LabDirectory "scenario.txt"
    $Scenario = @()
    if (Test-Path $scenarioFile) {
        $Scenario = @(Get-Content $scenarioFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
    }
}

$scenarioList = ($Scenario | ForEach-Object { "'$_'" }) -join ", "
$fakeCluster = Join-Path $LabDirectory "fake-cluster.ps1"

foreach ($plugin in "hyperv_cluster.ps1", "hyperv_host_csv_io.ps1") {
    $command = "`$FakeClusterScenario = @($scenarioList); . '$fakeCluster'; . '$(Join-Path $LabDirectory $plugin)'"
    # Drop a byte order mark, it would break the first section header
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command |
        ForEach-Object { $_.TrimStart([char]0xFEFF) }
}
