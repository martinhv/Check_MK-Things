# License: GNU General Public License v2

# Replaces the failover cluster cmdlets with test data, so that the agent plug-ins
# hyperv_cluster.ps1 and hyperv_host_csv_io.ps1 can run on a Windows computer that is
# not part of a cluster. PowerShell prefers functions to cmdlets of the same name.
#
# This computer plays the cluster node HV01 under its own name, a second node HV02
# exists only in the test data. The cluster shared volumes point to the real system
# disk of this computer, so the disk IO counters of hyperv_host_csv_io.ps1 are real.
#
# Set $FakeClusterScenario before dot-sourcing this file to change the test data,
# see README.md for the scenarios. Without a scenario, everything is OK.

if ($null -eq $FakeClusterScenario) {
    $FakeClusterScenario = @()
}

function Test-FakeScenario([string]$Name) {
    return $FakeClusterScenario -contains $Name
}

# Cluster objects that the plug-ins print directly show their name, like the real ones
class FakeClusterObject {
    [string]$Name
    [hashtable]$Parameters = @{}
    [object]$ResourceType
    [object]$GroupType
    [object]$State
    [object]$OwnerNode
    [object]$OwnerGroup
    [object]$SharedVolumeInfo
    FakeClusterObject([string]$name) { $this.Name = $name }
    [string] ToString() { return $this.Name }
}

function New-FakeClusterObject([string]$Name, [hashtable]$Properties = @{}) {
    $object = [FakeClusterObject]::new($Name)
    foreach ($key in $Properties.Keys) {
        $object.$key = $Properties[$key]
    }
    return $object
}

$FakeLocalNode = [FakeClusterObject]::new($env:COMPUTERNAME)
$FakeOtherNode = [FakeClusterObject]::new("HV02")

$FakeSystemDisk = Get-Disk | Where-Object IsSystem | Select-Object -First 1
if ($null -eq $FakeSystemDisk.Guid) {
    [Console]::Error.WriteLine("fake-cluster: the system disk has no GUID (MBR disk), the CSV IO counters stay empty")
}
$FakeSystemVolume = Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':')

# --- Cluster and cluster group ----------------------------------------------------------

$FakeCluster = [FakeClusterObject]::new("HVCLUSTER")
$FakeClusterGroup = New-FakeClusterObject "Cluster Group" @{ GroupType = "Cluster"; State = "Online"; OwnerNode = $FakeLocalNode }
$FakeAvailableStorage = [FakeClusterObject]::new("Available Storage")
$FakeCsvGroup = [FakeClusterObject]::new("Cluster Shared Volume")

function Get-Cluster {
    [CmdletBinding()]
    param()
    if (Test-FakeScenario "not-a-cluster") {
        return
    }
    $FakeCluster
}

function Get-ClusterQuorum {
    [CmdletBinding()]
    param($Cluster)
    if (Test-FakeScenario "node-majority") {
        return [pscustomobject]@{ QuorumResource = $null; QuorumType = "NodeMajority" }
    }
    [pscustomobject]@{
        QuorumResource = [FakeClusterObject]::new("Cluster Disk 1")
        QuorumType     = "NodeAndDiskMajority"
    }
}

# --- Nodes -----------------------------------------------------------------------------

function Get-ClusterNode {
    [CmdletBinding()]
    param($Cluster)
    if (Test-FakeScenario "not-a-cluster") {
        return
    }
    $otherState = "Up"
    foreach ($state in "Down", "Paused", "Joining") {
        if (Test-FakeScenario "node-$($state.ToLower())") { $otherState = $state }
    }
    $otherInfo = "Normal"
    foreach ($info in "Isolated", "Quarantined") {
        if (Test-FakeScenario "node-$($info.ToLower())") { $otherInfo = $info }
    }
    [pscustomobject]@{
        Name = $FakeLocalNode.Name; ID = 1; State = "Up"; StatusInformation = "Normal"; NodeWeight = 1
        Manufacturer = "Fake"; Model = "Test node"; SerialNumber = "FAKE0001"
    }
    [pscustomobject]@{
        Name = $FakeOtherNode.Name; ID = 2; State = $otherState; StatusInformation = $otherInfo; NodeWeight = 1
        Manufacturer = "Fake"; Model = "Test node"; SerialNumber = "FAKE0002"
    }
}

# --- Networks --------------------------------------------------------------------------

function Get-ClusterNetwork {
    [CmdletBinding()]
    param($Cluster)
    if (Test-FakeScenario "not-a-cluster") {
        return
    }
    $secondState = "Up"
    foreach ($state in "Partitioned", "Down", "Unavailable") {
        if (Test-FakeScenario "network-$($state.ToLower())") { $secondState = $state }
    }
    [pscustomobject]@{
        Name = "Cluster Network 1"; Role = "ClusterAndClient"; State = "Up"
        Address = "10.10.0.0"; AddressMask = "255.255.255.0"
        Ipv4Addresses = @("10.10.0.0"); Ipv6Addresses = @()
    }
    [pscustomobject]@{
        Name = "Cluster Network 2"; Role = "Cluster"; State = $secondState
        Address = "10.20.0.0"; AddressMask = "255.255.255.0"
        Ipv4Addresses = @("10.20.0.0"); Ipv6Addresses = @()
    }
}

# --- Resources: IP addresses and disks -------------------------------------------------

function Get-ClusterResource {
    [CmdletBinding()]
    param($Cluster)
    if (Test-FakeScenario "not-a-cluster") {
        return
    }
    $addresses = @("10.10.0.50")
    if (Test-FakeScenario "multi-subnet") {
        $addresses += "10.20.0.50"
    }
    foreach ($address in $addresses) {
        New-FakeClusterObject "Cluster IP Address $address" @{
            ResourceType = "IP Address"; OwnerGroup = $FakeClusterGroup; OwnerNode = $FakeLocalNode; State = "Online"
            Parameters = @{ Address = $address; SubnetMask = "255.255.255.0" }
        }
    }

    $dataDiskState = "Online"
    foreach ($state in "Offline", "Failed", "Pending", "Initializing", "OnlinePending", "OfflinePending") {
        if (Test-FakeScenario "disk-$($state.ToLower())") { $dataDiskState = $state }
    }
    foreach ($disk in @(
            @{ Name = "Cluster Disk 1"; Group = $FakeClusterGroup; Node = $FakeLocalNode; State = "Online" },
            @{ Name = "Cluster Disk 2"; Group = $FakeCsvGroup; Node = $FakeLocalNode; State = "Online" },
            @{ Name = "Cluster Disk 3"; Group = $FakeAvailableStorage; Node = $FakeOtherNode; State = $dataDiskState },
            @{ Name = "Cluster Disk 4"; Group = $FakeCsvGroup; Node = $FakeOtherNode; State = "Online" }
        )) {
        New-FakeClusterObject $disk.Name @{
            ResourceType = "Physical Disk"; OwnerGroup = $disk.Group; OwnerNode = $disk.Node; State = $disk.State
        }
    }
}

function Get-ClusterParameter {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Name,
        [Parameter(ValueFromPipeline = $true)]$InputObject
    )
    process {
        [pscustomobject]@{ Name = $Name; Value = $InputObject.Parameters[$Name] }
    }
}

# --- Cluster shared volumes ------------------------------------------------------------

function New-FakeClusterSharedVolume([string]$Name, [string]$Number, $Owner) {
    $partition = [pscustomobject]@{
        Size      = $FakeSystemVolume.Size
        FreeSpace = $FakeSystemVolume.SizeRemaining
        UsedSpace = $FakeSystemVolume.Size - $FakeSystemVolume.SizeRemaining
    }
    $volumeInfo = @([pscustomobject]@{ FriendlyVolumeName = "C:\ClusterStorage\Volume$Number"; Partition = $partition })
    if (($Name -eq "Cluster Disk 2") -and (Test-FakeScenario "csv-no-size")) {
        $volumeInfo = @()
    }
    return New-FakeClusterObject $Name @{
        OwnerNode = $Owner; SharedVolumeInfo = $volumeInfo; State = "Online"
        Parameters = @{ DiskIdGuid = $FakeSystemDisk.Guid }
    }
}

function Get-ClusterSharedVolume {
    [CmdletBinding()]
    param($Cluster)
    if (Test-FakeScenario "not-a-cluster") {
        return
    }
    $owner = if (Test-FakeScenario "csv-remote") { $FakeOtherNode } else { $FakeLocalNode }
    New-FakeClusterSharedVolume "Cluster Disk 2" "1" $owner
    New-FakeClusterSharedVolume "Cluster Disk 4" "2" $FakeOtherNode
}

# --- Groups: the cluster group and the clustered virtual machines ----------------------

function Get-ClusterGroup {
    [CmdletBinding()]
    param($Cluster)
    if (Test-FakeScenario "not-a-cluster") {
        return
    }
    $FakeClusterGroup

    $vmState = "Online"
    foreach ($state in "Offline", "Failed", "PartialOnline", "Pending") {
        if (Test-FakeScenario "vm-$($state.ToLower())") { $vmState = $state }
    }
    foreach ($vm in @(
            @{ Name = "TestVM01"; State = "Online"; Owner = $FakeLocalNode },
            @{ Name = "TestVM02"; State = $vmState; Owner = $FakeOtherNode },
            @{ Name = "TestVM03"; State = "Offline"; Owner = $FakeOtherNode }
        )) {
        New-FakeClusterObject $vm.Name @{ GroupType = "VirtualMachine"; State = $vm.State; OwnerNode = $vm.Owner }
    }
}
