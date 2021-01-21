[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/hpc-guest-diagnostics-test?branchName=master)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=6&branchName=master)

VM Size|OS Version|Status Badge|
|------|----------|------------|
|HB60  |CentOS 8.1|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=HB60rs_CentOS_HPC_8_1)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|HB60  |CentOS 7.6|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=HB60rs_CentOS_HPC_7_7)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|HB60  |CentOS 7.7|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=HB60rs_CentOS_HPC_7_7)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|HC44rs  |CentOS 7.7|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=HC44rs_CentOS_HPC_7_7)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|H16r  |CentOS 7.4|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=H16r_CentOS_HPC_7_4)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|NC24rs_v3|Ubuntu 18.04|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=NC24rs_v3_UbuntuServer_18_04_lts_gen2)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|NC24rs_v3|CentOS 8.1|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=NC24rs_v3_CentOS_HPC_8_1)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|
|ND40rs_v2|Ubuntu 18.04|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_apis/build/status/Build%20Status?branchName=master&stageName=NC24rs_v3_UbuntuServer_18_04_lts_gen2)](https://dev.azure.com/hpc-platform-team/hpc-guest-diagnostics-test/_build/latest?definitionId=15&branchName=master)|


# Overview
This repo holds a script that, when run on an Azure VM, gathers a variety of diagnostic information for the purposes of diagnosing common HPC, Infiniband, and GPU problems. It runs a suite of diagnostic tools ranging from built-in Linux tools like lscpu to vendor-specific CLI's like nvidia-smi. The resulting information is packaged up into a tarball, so that it can be shared with support engineers to speed up the troubleshooting process.

If you are reading this, you are likely troubleshooting problems on an Azure HPC VM, in which case we suggest you contact support if you have not already and run this tool on your VM so that you can provide the output to support engineers when prompted.

If you have special privacy requirements concerning logs leaving your VM, make sure to open up the tarball and redact any sensitive information before re-tarring it and handing it off to support engineers.

# Warning

This tool is meant for diagnosing inactive systems. It runs benchmarks that stress various system devices such as memory, GPU, and Infiniband. It will cause performance degradation for or otherwise interfere with other active processes that use these resources. It is not advised to use this tool on systems where other jobs are currenlty running.

To stop the tool while it is running, interrupt the process (i.e. ctrl-c) to force it to reset system state and terminate.

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
|  | --gpu-level | 1 (default), 2, or 3 | GPU diagnostics run-level | --gpu-level=3 | Sets dcgmi run-level to 3 |
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
|   -- journald.txt|syslog|messages
|-- CPU
|   -- lscpu.txt
|-- Memory
|   -- stream.txt
|-- Infiniband
|   -- ib-vmext.log
|   -- ibstat.txt
|   -- ibv_devinfo.txt
|   -- pkeys/*
|-- Nvidia
    -- nvidia-vmext.log
    -- nvidia-smi.txt (human-readable)
    -- nvidia-debugdump.zip (only Nvidia can read)
    -- dcgm-diag-2.log
    -- dcgm-diag-3.log
    -- nvvs.log
    -- stats_*.json
```


## Diagnostic Tools Table

| Tool | Command | Output File(s) | Description | EULA |
| :--- | :-----: | :------------: | :---------: | :--: |
| dmesg | dmesg | VM/dmesg.log | Dump of kernel ring buffer | |
| rsyslog | cp syslog&#124;messages | VM/syslog&#124;messages | Dump of system log | |
| journald | journalctl | VM/journald.txt | Dump of system log | |
| Azure IMDS | curl http://169.254.169.254/metadata/...| VM/metadata.json | VM Metadata (ID,Region,OS Image, etc) | |
| Azure VM Agent | cp /var/log/waagent.log | waagent.log | Logs from the Azure VM Agent | |
| lspci | lspci | VM/lspci.txt | Info on installed PCI devices | |
| lsvmbus | lsvmbus | VM/lsvmbus.log | Displays devices attached to the Hyper-V VMBus | |
| ipconfig | ipconfig | VM/ipconfig.txt | Checking TCP/IP configuration | |
| sysctl | sysctl | VM/sysctl.txt | Checking kernel parameters | |
| uname | uname | VM/uname.txt | Checking system information | |
| dmidecode | dmidecode | VM/dmidecode.txt | DMI table dump (info on hardware components) | |
| lscpu | lscpu | CPU/lscpu.txt | Information about the system CPU architecture | |
| stream | stream_zen_double | Memory/stream.txt | The stream benchmark suite (AMD Only) | [Steam License](http://www.cs.virginia.edu/stream/FTP/Code/LICENSE.txt)
| ibstat | ibstat | Infiniband/ibstat.txt | Mellanox OFED command for checking Infiniband status | [MOFED End-User Agreement](https://www.mellanox.com/page/mlnx_ofed_eula#:~:text=11%20Mellanox%20OFED%20Software%3A%20Third%20Party%20Free%20Software,2-clause%20FreeBSD%20License%20%2018%20more%20rows%20) |
| ibv_devinfo | ibv_devinfo | Infiniband/ibv_devinfo.txt | Mellanox OFED commnd for checking Infiniband Device info | [MOFED End-User Agreement](https://www.mellanox.com/page/mlnx_ofed_eula#:~:text=11%20Mellanox%20OFED%20Software%3A%20Third%20Party%20Free%20Software,2-clause%20FreeBSD%20License%20%2018%20more%20rows%20) |
| Partition Key | cp /sys/class/infiniband/.../pkeys/... | Infiniband/.../pkeys/... | Checks the configured Infinband Partition Keys |
| Infiniband Driver Extension Logs | cp /var/log/azure/ib-vmext-status | Infiniband/ib-vmext-status | Logs from the Infiniband Driver Extension |
| NVIDIA System Management Interface | nvidia-smi | Nvidia/nvidia-smi.txt | Checks GPU health and configuration | [CUDA EULA](https://docs.nvidia.com/cuda/pdf/EULA.pdf) [GRID EULA](https://images.nvidia.com/content/pdf/grid/support/enterprise-eula-grid-and-amgx-supplements.pdf) |
| NVIDIA Debug Dump | nvidia-debugbump | Nvidia/nvidia-debugdump.zip | Generates a binary blob for use with Nvidia internal engineering tools | [CUDA EULA](https://docs.nvidia.com/cuda/pdf/EULA.pdf) [GRID EULA](https://images.nvidia.com/content/pdf/grid/support/enterprise-eula-grid-and-amgx-supplements.pdf) |
| NVIDIA Data Center GPU Manager | dcgmi | Nvidia/dcgm-diag-2.log Nvidia/dcgm-diag-3.log Nvidia/nvvs.log Nvidia/stats_*.json | Health monitoring for GPUs in cluster environments | [DCGM EULA](https://developer.download.nvidia.com/compute/DCGM/docs/EULA.pdf) |
| GPU Driver Extension Logs | cp /var/log/azure/nvidia-vmext-status | Nvidia/nvidia-vmext-status | Logs from the GPU Driver Extension | |


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
