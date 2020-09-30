# Create a temp directory
$DIAG_DIR = [System.IO.Path]::GetRandomFileName()
New-Item -Path $DIAG_DIR -ItemType Directory;
Set-Location -PAth $DIAG_DIR -PassThru

# Information about compute
$Uri = "http://169.254.169.254/metadata/instance?api-version=2017-12-01";
$Headers = @{'Metadata' = 'true'};
$Metadata = (Invoke-RestMethod -Method GET -Uri $Uri -Headers $Headers).compute
$Metadata | Out-File metadata.txt;
$VM_Size = $Metadata.vmSize;

# Collect OS Information
$OS_Info = (Get-WmiObject Win32_OperatingSystem)
$OS_Type = (Get-WmiObject Win32_OperatingSystem).Caption
$OS_Info, $OS_Type | Out-File os-release.txt


# lspci output equivalent for Windows
(gwmi Win32_Bus -Filter 'DeviceID like "PCI%"').GetRelated('Win32_PnPEntity').GetDeviceProperties('DEVPKEY_Device_LocationInfo').deviceProperties | Out-File lspci.txt;


# Get Information on the basis of the VM Size
switch -Regex ($VM_Size)
{
    '^.*_N.*$'
    {
        # Get Nvidia GPU and Driver Infromation
        $Nvidia_Dev = Get-CimInstance -ClassName Win32_PnPEntity -Filter 'Manufacturer LIKE "Nvidia%"';
        if($Nvidia_Dev -ne $null -or $Nvidia_Dev -ne "")
        {
            $Nvidia_Dev | Out-File nvidia-info.txt;

            $Nvidia_SMI = & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe";
            $Nvidia_SMI | Out-File nvidia-smi.txt;

            $Nvidia_SMI_Q = & "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe" -q;
            $Nvidia_SMI_Q | Out-File nvidia-smi_q.txt;
        }
        else 
        {
            Write-Output "No Nvidia Devices Found";
        }
        Break;
    }

    '^.*_H.*$'
    {
        # Get InfiniBand Information
        $Mellanox_Dev = Get-CimInstance -ClassName Win32_PnPEntity -Filter 'Manufacturer LIKE "Mellanox%"';
        $Mellanox_Dev | Out-File mellanox-info.txt;
        Break;
    }

    Default
    {
        # No N or H size Compute found, Tool is invalid
        Write-Error "No standard HPC compute found";
        Break;
    }
}

# Cleanup
Set-Location -Path .. -PassThru;
$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
$SAVE_DIR = 'Azure_HPC_Diagnostics_Information' + '-' + $timestamp + '.zip';
Compress-Archive -LiteralPath $DIAG_DIR -DestinationPath $SAVE_DIR;
Remove-Item $DIAG_DIR -Recurse;