# Fake failover cluster for the Hyper-V cluster agent plug-ins

Runs `hyperv_cluster.ps1` and `hyperv_host_csv_io.ps1` on a normal Windows computer
that is not part of a failover cluster. `fake-cluster.ps1` replaces the failover
cluster cmdlets with test data:

- the cluster `HVCLUSTER` with the nodes `<this computer>` and `HV02`
- two cluster networks, four cluster disks, two cluster shared volumes (CSV) and
  three clustered VMs
- both CSVs point to the real system disk of this computer, so the disk IO counters
  of `hyperv_host_csv_io.ps1` are real; put load on the disk to see them change

This does not replace a test on a real cluster: the real cmdlets may return other
formats, and there is no real failover.

## Run manually

Copy these files into one folder:

- `fake-cluster.ps1`, `run-fake-cluster.ps1` from this folder
- `hyperv_cluster.ps1`, `hyperv_host_csv_io.ps1` from `cmk_plugins/hyperv_cluster/agents`

Then, in PowerShell in that folder:

```powershell
.\run-fake-cluster.ps1 -LabDirectory .
.\run-fake-cluster.ps1 -LabDirectory . -Scenario node-down, disk-offline, vm-failed
```

If scripts are blocked, start PowerShell with `-ExecutionPolicy Bypass`.

To compare the computed IO counters with the ones of Windows, run this while
copying a large file:

```powershell
Get-Counter '\PhysicalDisk(*)\Avg. Disk sec/Read', '\PhysicalDisk(*)\Disk Reads/sec' -SampleInterval 1 -MaxSamples 5
```

## Run as Checkmk agent plug-in

1. Install the Checkmk agent on the computer.
2. Copy the four files to `C:\ProgramData\checkmk\agent\fake_cluster`. Do not put the
   two Hyper-V plug-ins into the agent's `plugins` folder.
3. Copy `run-fake-cluster.ps1` to `C:\ProgramData\checkmk\agent\plugins`.
4. Write the scenarios, one per line, into
   `C:\ProgramData\checkmk\agent\fake_cluster\scenario.txt`. An empty or missing file
   means everything is OK.
5. In Checkmk, run a service discovery of the host. The Checkmk site must reach the
   computer on port 6556.

## Scenarios

| Scenario | Changes |
|---|---|
| `node-down`, `node-paused`, `node-joining` | state of node HV02 |
| `node-isolated`, `node-quarantined` | status information of node HV02 |
| `network-partitioned`, `network-down`, `network-unavailable` | state of "Cluster Network 2" |
| `disk-offline`, `disk-failed`, `disk-pending`, `disk-initializing`, `disk-onlinepending`, `disk-offlinepending` | state of "Cluster Disk 3" |
| `vm-offline`, `vm-failed`, `vm-partialonline`, `vm-pending` | state of VM "TestVM02" |
| `csv-remote` | "Cluster Disk 2" is owned by HV02 instead of this computer |
| `csv-no-size` | no size information for "Cluster Disk 2" |
| `node-majority` | quorum without witness |
| `multi-subnet` | a second cluster IP address |
| `not-a-cluster` | the computer is not part of a cluster, the plug-ins print no cluster data |

Scenarios can be combined.
