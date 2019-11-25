# This script takes as hardcoded parameter the desired order of boot
# devices set in the UEFI firmware. These devices are specified using
# their descriptor. Any other devices are appended after the specified
# devices in their original order
# 
# This is needed because Windows likes to place its boot mgr first in
# the UEFI list, at least after a reimage of our systems. We need to
# keep PXE boot on top.

#-------------------------
# parameters:
# hardcode which must be first, second, etc
$desiredOrder = @("IBA GE Slot 0200 v1573","Windows Boot Manager")

#-------------------------
# helper functions
function getBCDOutput
{
    [cmdletbinding()]  
    Param(
        [Parameter(Mandatory=$true)]
        [String[]]$store
    )
    return ([string[]] (cmd /c bcdedit /enum $store)).Where({$_ -ne ""}) # array of strings, empties removed
}

function BCDOutputToDict {
    [cmdletbinding()]  
    Param(
        [Parameter(ValueFromPipeline)]
        [String[]]$bcdOutput
    )
    $dict = @{}

    # skip first two and iterate
    $iter = -1
    $currentKey = ""
    ForEach ($line in $bcdOutput[2..$bcdOutput.Length])
    {
        $lineBits = $line.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)
        if ($line[0] -ne " ")
        {
            $iter += 1
            $currentKey = $lineBits[0]
            $dict.Add($currentKey,@())
        }
        $dict[$currentKey] += ($lineBits[1..($lineBits.Length -1)] -join " ") # reconstitute string
    }

    return $dict
}


#-------------------------
# start actual code

# if not elevated, then elevate
If (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
  # Relaunch as an elevated process:
  Start-Process powershell.exe "-File",('"{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
  exit
}

#-------------------------
# get whats currently the order of boot options

# first get UEFI store, its displayorder provides info about the boot order
$bcdOutput = getBCDOutput "{fwbootmgr}"
$bcdDict = BCDOutputToDict $bcdOutput

# for each item in display order, get info (keep order)
$bootDict = [ordered]@{}
$iter = 0
ForEach ($item in $bcdDict["displayorder"])
{
    #echo $item
    $temp = getBCDOutput $item
    $bcdOutput = BCDOutputToDict $temp
    $bootDict.Add($iter,$bcdOutput)
    $iter += 1
}

# get labels
$currentOrder = @(ForEach($item in $bootDict.Values) {echo $item["description"]})
echo "Current boot order:"
echo $currentOrder
echo `n

#-------------------------
# determine new order for boot menu

# first, check desired items exist
ForEach ($item in $desiredOrder)
{
    if (-Not $currentOrder.Contains($item))
    {
        throw "Item """ + $item + """ not found in current boot order"
    }
}

# new order starts with hardcoded, add to it the other items not listed
$newOrder = $desiredOrder
ForEach ($item in $currentOrder)
{
    if (-Not $newOrder.Contains($item))
    {
        $newOrder += $item
    }
}


#-------------------------
# put boot menu into new order, if different from current
If (-Not @(Compare-Object $currentOrder $newOrder -SyncWindow 0).Length -eq 0)
{
    echo "New boot order:"
    echo $newOrder
    echo `n
    
    # first, get identifiers corresponding to labels
    $newIdentifiers = ForEach ($item in $newOrder)
    {
        $bootDict.Values | % { if($_["description"] -eq $item){$_["identifier"]}}
    }
    echo "corresponding identifiers:"
    echo $newIdentifiers
    echo `n

    # build command
    $cmd = 'cmd /c bcdedit /set "{fwbootmgr}" displayorder "' + ($newIdentifiers -join """ """) + """"
    echo "will execute:" $cmd

    # execute
    Invoke-Expression $cmd
}
Else
{
    echo "current order is fine, nothing to do"
}