﻿function Set-AzureVMOSDiskSize
{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param
    (
        [Parameter(ValueFromPipeline=$true, Mandatory=$true)]
        [Microsoft.WindowsAzure.Commands.ServiceManagement.Model.ServiceOperationContext] $VM,

        [Parameter(Mandatory=$true, Position=0)]
        [int] $SizeInGb
    )

    $disk = Get-AzureOSDisk -VM $VM.VM

    $disk.MediaLink -match "https:\/\/(?<account>[^.]*)" | Out-Null
    $storageAccount = $Matches['account']
    
    Set-AzureSubscription -SubscriptionId (Get-AzureSubscription -Current).SubscriptionId -CurrentStorageAccountName $storageAccount

    $currentDiskSize = (Get-AzureDisk -DiskName $disk.DiskName).DiskSizeInGB
    if($currentDiskSize -gt $SizeInGb)
    {
        $ConfirmPreference = 'Low'
        if (!$PSCmdlet.ShouldContinue('Are you sure that you want to shrink the OS disk (and lose data)?',"You're shrinking the disk!")) {
                Write-Warning 'You were trying to shrink the disk but decided to abort'
                Write-Warning 'No changes have been made'
                return
        }
    }

    # Stop and Deallocate VM prior to resizing data disk
    Stop-AzureVM -VM $VM.VM -ServiceName $VM.ServiceName -Force -Verbose

    Start-Sleep -Seconds 120 -Verbose

    # Cope with disks that were created without a Label and in this case label them with the disk name
    if([string]::IsNullOrEmpty($disk.DiskLabel)) {
        $diskLabel = $disk.DiskName
    }
    else {
        $diskLabel = $disk.DiskLabel
    }

    # Resize Data Disk to Larger Size
    Update-AzureDisk -Label $diskLabel -DiskName $disk.DiskName -ResizedSizeInGB $SizeInGb -Verbose

    # Start VM
    Start-AzureVM -VM $VM.VM -ServiceName $VM.ServiceName -Verbose
}
