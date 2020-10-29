[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)

VM Size|OS Version|Status Badge|
|------|----------|------------|
|HB60  |CentOS 8.1|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20HB60_centos81)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|
|HB60  |CentOS 7.6|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20HB60_centos76)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|
|HB60  |CentOS 7.7|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20HB60_centos77)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|
|H16r  |CentOS 7.4|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20H16r)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|
|NC24rs_v3|Ubuntu 18.04|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20NC)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|
|ND40rs_v2|Ubuntu 18.04|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20ND)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|
|NV48s_v3|Ubuntu 18.04|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master&jobName=ValidateVirtualMachine&configuration=ValidateVirtualMachine%20NV)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)|

# Overview
This repo holds a script that, when run on an Azure VM, gathers a variety of diagnostic information for the purposes of diagnosing common HPC, Infiniband, and GPU problems. It runs a suite of diagnostic tools ranging from built-in Linux tools like lscpu to vendor-specific CLI's like nvidia-smi. The resulting information is packaged up into a tarball, so that it can be shared with support engineers to speed up the troubleshooting process.

If you are reading this, you are likely troubleshooting problems on an Azure HPC VM, in which case we suggest you contact support if you have not already and run this tool on your VM so that you can provide the output to support engineers when prompted.

If you have special privacy requirements concerning logs leaving your VM, make sure to open up the tarball and redact any sensitive information before re-tarring it and handing it off to support engineers.

# Install and Run
After cloning this repo, no further installation is required.
To run the script, run the following command, replacing {repo-root} with the name of this repo's directory on your VM:
```
sudo bash {repo-root}/Linux/src/gather_azhpc_vm_diagnostics.sh
```

# Usage
This section describes the output of the script and the configuration options available.
## Options

| Option (Short) | Option (Long) | Parameters | Description | Example | Example Description |
| :------------- | :-----------: | :--------: | :---------: | :-----: | ------: |
| -d | --dir | Directory Name | Specify custom output location | --dir=. | Put the tarball in the current directory |
| -V | --version |  | display version information and exit | --version | Outputs 0.0.1 |
| -h | --help |  | display help text | -h | Outputs the help message |
| -v | --verbose |  | verbose output | --verbose | Enables more verbose terminal output |
|  | --gpu-level | 2 (default) or 3 | GPU diagnostics run-level | --gpu-level=3 | Sets dcgmi run-level to 3 |
|  | --mem-level | 0 (default) or 1 | Memory diagnostics run-level | --mem-level=1 | Enables stream benchmark test |

## Tarball Structure
Note that not all these files will be generated on all runs. What appears below is union of all files that could be generated, which depends on script parameters and VM size:
```
{vm-id}.{timestamp}.tar.gz
|-- general.log (logs for the tool itself)
|-- VM
|   -- dmesg.log
|   -- metadata.json
|   -- waagent.log
|   -- lspci.txt
|   -- lsvmbus.log
|   -- ipconfig.txt
|   -- sysctl.txt
|   -- uname.txt
|   -- dmidecode.txt
|   -- syslog
|-- CPU
|   -- lscpu.txt
|-- Memory
|   -- stream.txt
|-- Infiniband
    -- ib-vmext.log
|   -- ibstat.txt
|   -- ibv_devinfo.txt
|   -- pkey0.txt
|   -- pkey1.txt
|-- Nvidia
    -- nvidia-vmext.log
    -- nvidia-smi.txt (human-readable)
    -- dump.zip (only Nvidia can read)
    -- dcgm-diag-2.log
    -- dcgm-diag-3.log
    -- nvvs.log
    -- stats_*.json
```


## Diagnostic Tools Table

| Tool | Command | Output File(s) | Description |
| :--- | :-----: | :------------: | :---------: |
| dmesg | dmesg | VM/dmesg.log | Dump of kernel ring buffer |
| syslog | syslog | VM/syslog | Dump of system log |
| Azure IMDS | curl http://169.254.169.254/metadata/...| VM/metadata.json | VM Metadata (ID,Region,OS Image, etc) |
| Azure VM Agent | cp /var/log/waagent.log | waagent.log | Logs from the Azure VM Agent |
| lspci | lspci | VM/lspci.txt | Info on installed PCI devices |
| lsvmbus | lsvmbus | VM/lsvmbus.log | Displays devices attached to the Hyper-V VMBus |
| ipconfig | ipconfig | VM/ipconfig.txt | Checking TCP/IP configuration |
| sysctl | sysctl | VM/sysctl.txt | Checking kernel parameters |
| uname | uname | VM/uname.txt | Checking system information |
| dmidecode | dmidecode | VM/dmidecode.txt | DMI table dump (info on hardware components) |
| lscpu | lscpu | CPU/lscpu.txt | Information about the system CPU architecture |
| stream | stream_zen_double | Memory/stream.txt | The stream benchmark suite (AMD Only) |
| ibstat | ibstat | Infiniband/ibstat.txt | Mellanox OFED command for checking Infiniband status |
| ibv_devinfo | ibv_devinfo | Infiniband/ibv_devinfo.txt | Mellanox OFED commnd for checking Infiniband Device info |
| Partition Key | cp /sys/.../pkeys/... | Infiniband/pkey0.txt Infiniband/pkey1.txt | Checks the configured Infinband Partition Key |
| Infiniband Driver Extension Logs | /var/log/azure/ib-vmext-status | Infiniband/ib-vmext-status | Logs from the Infiniband Driver Extension |
| NVIDIA System Management Interface | nvidia-smi | Nvidia/nvidia-smi.txt | Checks GPU health and configuration |
| NVIDIA Debug Dump | nvidia-debugbump | Nvidia/dump.zip | Generates a binary blob for use with Nvidia internal engineering tools |
| NVIDIA Data Center GPU Manager | dcgmi | Nvidia/dcgm-diag-2.log Nvidia/dcgm-diag-3.log Nvidia/nvvs.log Nvidia/stats_*.json | Health monitoring for GPUs in cluster envirmonments
| GPU Driver Extension Logs | /var/log/azure/nvidia-vmext-status | Nvidia/nvidia-vmext-status | Logs from the GPU Driver Extension |




# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
