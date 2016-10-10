#------------------------------------------------------------------------------  #  # Copyright © 2016 Microsoft Corporation.  All rights reserved.  #  # THIS CODE AND ANY ASSOCIATED INFORMATION ARE PROVIDED “AS IS” WITHOUT  # WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT # LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS  # FOR A PARTICULAR PURPOSE. THE ENTIRE RISK OF USE, INABILITY TO USE, OR   # RESULTS FROM THE USE OF THIS CODE REMAINS WITH THE USER.  #  #------------------------------------------------------------------------------  #  # PowerShell Module Source Code  #  # NAME:  #    AzureIsolatedStorageAccount.psm1  #  # VERSION:  #    1.2# # TESTED:#    with AzurePowershell v1.6.0 #------------------------------------------------------------------------------  

<# 
.PRIVATE FUNCTION
.SYNOPSIS 
   Gets a random char or number on demand
.DESCRIPTION 
   This function generates a random number within the size boundaries of a char. This can therefore be used for number and character generation. 
.EXAMPLE 
   Get-RandomCharOrNumber
.INPUTS 
   None 
.OUTPUTS 
   The number in char format
#> 
function Get-RandomCharOrNumber{
    $rnd = Get-Random -Minimum 0 -Maximum 35
    $rnd += if($rnd -le 9){48}else{87}
    
    $ch = [char] $rnd
    return $ch
}

<# 
.PRIVATE FUNCTION
.SYNOPSIS 
   Generates a random string
.DESCRIPTION 
   This function uses the private function Get-RandomCharOrNumber to generate a string with the specified length.
   This string is then returned at the end of this function's execution
   If no length is sepcified, a string with the length of 3 is generated.
.EXAMPLE 
   New-RandomString(5)
   New-RandomString
.INPUTS 
   (optional|int) Length of the required string.
.OUTPUTS 
   A random string with a length that matches the input parameter
#> 
function New-RandomString{
    param([int]$len=3)

    $outputString = ""

    for($i=0;$i-lt $len;$i++){

        # for each letter in the string, generate a random char and add it to the output string
        $outputString += Get-RandomCharOrNumber

    }
    return $outputString
}

<# 
.PRIVATE FUNCTION
.SYNOPSIS 
   Takes a name suffix and adds a random 3 letter prefix for use with as an Azure Storage Account name.
.DESCRIPTION 
   This function uses the private function New-RandomString to generate a random prefix for a given storage account suffix. 
   The name is then tested for validity and availability. 
   If the name is available it is returned. 
   If the name is invalid or three attempts fail to generate a valid name an exception is thrown and the process is aborted.
.THROWS
    System.Exception
.EXAMPLE 
   Get-StorageAccountNameWithRandomPrefix(mystorage)
.INPUTS 
   (String) the storage account suffix (e.g. 'mystorage')
.OUTPUTS 
   A String consisting of a random prefix and the specified suffix
#> 
function Get-StorageAccountNameWithRandomPrefix($StorageAccountSuffix) {
    $IsAvailable = $false
    $maxAttempts = 3
    $attempt = 0
    $storageaccountname = "failed"
    
    do{
        $attempt ++
        
        # generate a new random name
        $storageaccountname = (New-RandomString) + $StorageAccountSuffix
        Write-Host "Create new storage account : $storageaccountname  ..." -NoNewline
        
        # check if name is available
        $IsAvailable = (Get-AzureRmStorageAccountNameAvailability -Name $storageaccountname ).NameAvailable
        if(!$IsAvailable)
        {
            # check if max num of retries is reached.          
            if($attempt -lt $maxAttempts){
                write-host "KO! Storage account name already in use or invalid. Generating new name and retry" -ForegroundColor Yellow
            }else{
                
                Write-Host "KO!" -ForegroundColor Red
                throw [System.Exception] " Storage account name already in use or invalid. Max num of retries reached ($maxAttempts). Abort"
                return
            }
        }
    }
    while(!$IsAvailable)

    return $storageaccountname
}

<# 
.PRIVATE FUNCTION
.SYNOPSIS 
   Checks if a resource group is available in the current subscription and creates it if necessary.
   Returns the resource group.
.DESCRIPTION 
   If the specified resource group is available in the specified location, it will be returned.
   If the specified resource group is not available in the specified location, a creation attempt will be made.
   If this attempt is successful, the new resource group will be returned.
.EXAMPLE 
   Set-AzureResourceGroup("myRG", "North Europe")
.INPUTS 
   (String) the resource group name
   (String) the azure location
.OUTPUTS 
   The Resource Group as a PSObject representation. 
#> 
function Set-AzureResourceGroup($ResourceGroupName, $location){
    write-host "Get Resource Group..." -NoNewline

    # get refrence of RG at destination
    $rg = Get-AzureRmResourceGroup -Name $ResourceGroupName -Location $location -ErrorAction SilentlyContinue

    # check if the RG already exists at destination
    if($rg  -eq $null){ 
    
        Write-Host "KO!" -ForegroundColor Yellow
    
        write-host "Creating the destination resource group..." -NoNewline
    
        # create RG at destination
        $rg = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $location -WarningAction SilentlyContinue 
    }

    write-host "OK" -ForegroundColor Green
    return $rg
}

<# 
.SYNOPSIS 
   Checks if a resource group has got storage accounts on the same storage cluster.
.DESCRIPTION 
   This method queries all cluster assignments for all storage acccounts in a specified Azure ARM resource group.
   If a cluster assignment is not unique in the resource group a warning will be displayed. 
.EXAMPLE 
   Get-AzureRmStorageAccountInSameCluster -ResourceGroupName "myRG"
.INPUTS 
   ResourceGroupName | Name of the resource group being queried
.OUTPUTS 
   An array of duplicates with the rows "StorageAccountName" and "ClusterName"
#> 
function Get-AzureRmStorageAccountInSameCluster
{
    param(
        [Parameter(Mandatory=$False)]
        [string]$ResourceGroupName
    )
    write-host "Validating existing storage accounts in the ResourceGroup ..." -NoNewline
    
    try{
        $accountArray = @()
        $sas = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName
        $sas | % {
            # get the actual cluster name
            $cluster = Get-AzureRmStorageAccountCluster -ResourceGroupName $ResourceGroupName -StorageAccountName $_.StorageAccountName
            $accountArray += New-Object psobject -Property @{
                StorageAccountName = $cluster.StorageAccountName
                ClusterName = $cluster.ClusterName
            }
        }
            
        $duplicates = (($accountArray | Group-Object ClusterName) | Where-Object {$_.Count -gt 1}) | % {$_.Group }

        if($duplicates -ne $null){

            Write-Host "KO! Found more than 1 storage accounts on same cluster" -ForegroundColor Yellow

        }else{
       
            Write-Host "OK" -ForegroundColor Green
        }
    
    }catch{
            Write-Host "KO!" -ForegroundColor Red
            throw $_
    }

    return $duplicates
}

<# 
.SYNOPSIS 
   Depending on the parameters specified, this method will show all ARM storage cluster assignments for a resource group, a subscription, or a single account.
.DESCRIPTION 
   This function performs a DNS lookup on the specified set of ARM storage accounts (either all in a resource group, all in a subscription, or just a single account) 
   to produce their storage cluster assignments.
   These are then returned as an array. 
.EXAMPLE 
   Get-AzureRmStorageAccountCluster -ResourceGroupName "myRG"
   Get-AzureRmStorageAccountCluster -ResourceGroupName "myRG" -StorageAccountName "myacc"
   Get-AzureRmStorageAccountCluster
.INPUTS 
   (optional) ResourceGroupName | Name of the resource group being queried
   (optional) StorageAccountName | Name of the storage account being queried
.OUTPUTS 
   An array of assignments with the rows "StorageAccountName" and "ClusterName"
#> 
function Get-AzureRmStorageAccountCluster
{
    param(
        [Parameter(Mandatory=$False)]
        [string]$ResourceGroupName = "",

        [Parameter(Mandatory=$False)]
        [string]$StorageAccountName = ""
    )
    
    try{
        $accountArray = @()
        $sas = @()

        if($ResourceGroupName -eq "") {

            if($StorageAccountName -eq "") {
                write-host "Getting clusters for all ARM storage accounts ..." -NoNewline
                $sas = Get-AzureRmStorageAccount
            } else {
                throw [System.Exception] " Resource Group Name needs to be specified when using the Storage Account Name parameter. Abort!"
            }
            
        } else {
            
            if($StorageAccountName -eq "") {
                write-host "Getting clusters for ARM storage accounts in the ResourceGroup ..." -NoNewline
                $sas = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName
            } else {
                write-host "Getting cluster for storage account $StorageAccountName in the ResourceGroup ..." -NoNewline
                $sas = Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName 
            }
        }

        if($sas.Length -lt 1) {
            throw [System.Exception] " No storage accounts discovered..."
        }
        
        $sas | % {
            # get the actual cluster name

            if($_.Context.BlobEndPoint -ne $null) {
                $saDnsName = $_.Context.BlobEndPoint.Split("/")[2]
                $saClusterDnsName = (Resolve-DnsName -Name $saDnsName).NameHost.split(".")[1]
                $accountArray += New-Object psobject -Property @{
                    StorageAccountName = $_.StorageAccountName
                    ClusterName = $saClusterDnsName
                }
            }
        }

        Write-Host "OK" -ForegroundColor Green
    
    }catch{
            Write-Host "KO!" -ForegroundColor Red
            throw $_
    }

    return $accountArray
}

<# 
.SYNOPSIS 
   Depending on the parameters specified, this method will show all Classic storage cluster assignments for a subscription, or for a single account.
.DESCRIPTION 
   This function performs a DNS lookup on the specified set of Classic storage accounts (either all in a subscription, or just a single account) 
   to produce their storage cluster assignments.
   These are then returned as an array. 
.EXAMPLE 
   Get-AzureStorageAccountCluster -StorageAccountName "myacc"
   Get-AzureStorageAccountCluster
.INPUTS 
   (optional) StorageAccountName | Name of the storage account being queried
.OUTPUTS 
   An array of assignments with the rows "StorageAccountName" and "ClusterName"
#> 
function Get-AzureStorageAccountCluster
{
    param(
        [Parameter(Mandatory=$False)]
        [string]$StorageAccountName = ""
    )
    
    try{
        $accountArray = @()
        $sas = @()

        if($StorageAccountName -eq "") {
            write-host "Getting clusters for all Classic storage accounts ..." -NoNewline
            $sas = Get-AzureStorageAccount
        } else {
            write-host "Getting cluster for $StorageAccountName ..." -NoNewline
            $sas = Get-AzureStorageAccount -StorageAccountName $StorageAccountName
        }
        
        $sas | % {
            # get the actual cluster name
            $saDnsName = $_.Context.BlobEndPoint.Split("/")[2]
            $saClusterDnsName = (Resolve-DnsName -Name $saDnsName).NameHost.split(".")[1]
            $accountArray += New-Object psobject -Property @{
                StorageAccountName = $_.StorageAccountName
                ClusterName = $saClusterDnsName
            }
        }

        Write-Host "OK" -ForegroundColor Green
    
    }catch{
            Write-Host "KO!" -ForegroundColor Red
            throw $_
    }

    return $accountArray
}

<# 
.SYNOPSIS 
   This function will create an ARM storage account with a unique prefix. The function offers the option to avoid a specified list of storage clusters in a region.
.DESCRIPTION 
   The function first creates a storage account with a random prefix.
   It then creates a new ARM storage account.
   After the creation its cluster is queried.
   If the storage account has landed on a cluster that is among the list of excluded cluster the creation will be reattempted with a different account name up to 3 times, before the method fails over.
.EXAMPLE 
   New-AzureRmIsolatedStorageAccount -StorageAccountSuffix "storage" -ResourceGroupName "myRG" -Location "north europe" -SkuName Standard_LRS -kind Storage -ExcludeClusters db6prdstr02a,db5prdstr04a
   New-AzureRmIsolatedStorageAccount -StorageAccountSuffix "storage" -ResourceGroupName "myRG" -Location "north europe"
.INPUTS 
   StorageAccountSuffix | The second half of the resulting storage account name; for the purpose of this function the first half needs to be auto-generated
   ResourceGroupName | The resource group, where the storage account will be placed
   Location | The Azure region, where the storage account should be created
   (optional) SkuName | one of the following: "Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS"
   (optional) Kind | one of the following: "Storage" (hot storage), "BlobStorage" (cool storage)
   (optional | array) ExcludedClusters | a list of excluded cluster names (e.g. "db6prdstr02a,db5prdstr04a")
.OUTPUTS 
   The newly created storage account
#>
function New-AzureRmIsolatedStorageAccount
{
 param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$StorageAccountSuffix,

    [Parameter(Mandatory=$True,Position=2)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$True)]
    [string]$Location,

    [Parameter(Mandatory=$False)]
    [ValidateSet("Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS")]
    [string]$SkuName="Standard_LRS",
    
    [Parameter(Mandatory=$False)]
    [ValidateSet("Storage", "BlobStorage")]
    [string]$kind="Storage",

    # access tier cannot currently be set (Storage/BlobStorage determines the access tier)
    # [ValidateSet("Hot","Cool")]
    # [string]$accessTier,

    [Parameter(Mandatory=$False)]
    [array]$ExcludeClusters=@()

 )

    # get-or-create resource group 
    $rg = Set-AzureResourceGroup -ResourceGroupName $ResourceGroupName -location $Location

    # generate a storage account name with a random prefix
    $storageAccountName = Get-StorageAccountNameWithRandomPrefix($StorageAccountSuffix)

    # creating the storage account 
    $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageaccountname -Location $location -SkuName $skuName -Kind $kind -WarningAction SilentlyContinue

    # do we need to check for excluded clusters
    if ($ExcludeClusters.Length -gt 0) {
        
        $maxAttempts = 3
        $creationAttempt = 0

        for($i = 0; $i -lt $ExcludeClusters.Length; $i++) {
            $ExcludeClusters[$i] = $ExcludeClusters[$i].ToString().ToLower().Trim()
        }
        
        $isValid = $false

        do {
            $creationAttempt++

            if($creationAttempt -gt $maxAttempts) {
                write-host "KO! Reached max. number of attempts $maxAttempts " -ForegroundColor Red
                return;
            }

            # get resulting cluster 
            $cluster = (Get-AzureRmStorageAccountCluster -ResourceGroupName $ResourceGroupName -StorageAccountName $storageaccountname)[0].ClusterName
            Write-Host " Account is on cluster $cluster"

            # have we landed on a forbidden cluster
            if($ExcludeClusters.Contains($cluster.ToString().ToLower().Trim())) {
                write-host "KO! Storage account is on cluster $cluster, which is part of the excluded clusters. Removing account..." -ForegroundColor Yellow
                Remove-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageaccountname -WarningAction SilentlyContinue

                if($creationAttempt -lt $maxAttempts) {
                    
                    write-host "Attempting recreation... " -ForegroundColor Cyan
                    $storageAccountName = Get-StorageAccountNameWithRandomPrefix($StorageAccountSuffix)

                    # re-creating the storage account 
                    $storageAccount = New-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName -Name $storageaccountname -Location $location -SkuName $skuName -Kind $kind -WarningAction SilentlyContinue
                
                }
            } else {
                $isValid = $true
            }

        } while (!$isValid)
    }

    Write-Host "OK" -ForegroundColor Green

    return $storageAccount
}

<# 
.SYNOPSIS 
   This function creates a series (3 by default) of storage accounts with different prefixes in a resource group.
   It will aim to place all of these storage accounts on different clusters.
   If this is impossible, a maximum of 3 retries will be executed per storage account.
.DESCRIPTION 
   The function takes in a storage account suffix, a resource group name and a location.
   If the resource group does not exist it will be created.
   There is a switch that allows the user to check if there are already storage accounts with the same cluster assignment in the deployment resource group.
   If there are such storage accounts in the resource group the deployment will be aborted.
   There is a switch that allows the user to exclude clusters from the deployment that were previously used in the same resource group.
   By default the function will try to create a series of three storage accounts on different clusters.
   If a storage account lands on a cluster that has been used previously, the creation will be re-attempted up to three times. 
.EXAMPLE 
   New-AzureRmIsolatedStorageAccountList -StorageAccountSuffix "storage" -ResourceGroupName "myRG" -Location "north europe" -SkuName Standard_LRS -kind Storage -NumberOfAccounts 4 -ValidateExistingStorageAccounts -DoNotCreateOnPreviouslyUsedClusters 
   New-AzureRmIsolatedStorageAccountList -StorageAccountSuffix "storage" -ResourceGroupName "myRG" -Location "north europe" 
.INPUTS 
   StorageAccountSuffix | The second half of the resulting storage account names; for the purpose of this function the first half needs to be auto-generated
   ResourceGroupName | The destination resource group
   Location | The Azure region, where the storage account should be created
   (optional) SkuName | one of the following: "Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS"
   (optional) Kind | one of the following: "Storage" (hot storage), "BlobStorage" (cool storage)
   (optional) Number of Accounts | 3 by default
   (switch) ValidateExistingStorageAccounts | will validate the resource group for existing storage accounts that share a storage cluster and abort the operation if it finds any storage accounts of this kind
   (switch) DoNotCreateOnPreviouslyUsedClusters | will take into account storage account clusters that have previously been used in the same resource group, when creating new storage accounts through this method
.OUTPUTS 
   An array containing the newly created storage account names and their respective cluster assignments. 
#>
function New-AzureRmIsolatedStorageAccountList
{
    param(

    [Parameter(Mandatory = $true,Position=1)]
    [string]$StorageAccountSuffix,
    
    [Parameter(Mandatory = $true,Position=2)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$Location,

    [ValidateSet("Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS")]
    [string]$SkuName="Standard_LRS",
    
    [ValidateSet("Storage", "BlobStorage")]
    [string]$kind="Storage",
    
    # access tier cannot currently be set (Storage/BlobStorage determines the access tier)
    #[ValidateSet("Hot","Cool")]
    #[string]$accessTier,
    [int]$NumberOfAccounts = 3,
    [switch]$ValidateExistingStorageAccounts=$false,
    [switch]$DoNotCreateOnPreviouslyUsedClusters=$false
    )

    try{
        Write-Host "Starting job. Creating $NumberOfAccounts storage accounts in $location for Resource Group $ResourceGroupName.`n"


        # get-or-create resource group 
        $rg = Set-AzureResourceGroup -ResourceGroupName $ResourceGroupName -location $location

        $maxAttempts = 3
        $accountArray = @()
        $excludedClusters = @()

        if($ValidateExistingStorageAccounts){

            $duplicates = Get-AzureRmStorageAccountInSameCluster -ResourceGroupName $ResourceGroupName
            if($duplicates -ne $null){
                $message = "Found storage accounts that share the same cluster:`n{0}`n`nAbort" -f ($duplicates)
                
                throw [System.Exception] $message
            }
        }

        if($DoNotCreateOnPreviouslyUsedClusters) {
            $clustersInResourceGroup = Get-AzureRmStorageAccountCluster -ResourceGroupName $ResourceGroupName

            foreach($cluster in $clustersInResourceGroup) {
                $excludedClusters += $cluster.ClusterName
            }

            Write-Host "The following clusters are already in use in the resource group. The job will try to avoid creating storage accounts on these clusters" -ForegroundColor Cyan
            Write-Host $excludedClusters -ForegroundColor Cyan
        }
    
        for($j=0;$j-lt $NumberOfAccounts;$j++)
        {
            Write-Host ""
            Write-Host "*** Trying to create account #"($j+1)"of $NumberOfAccounts ***"
            
            # refresh list of excluded clusters
            foreach($account in $accountArray) {
                if($excludeClusters -notcontains $account.ClusterName) {
                    $excludedClusters += $account.ClusterName
                }
            }

            $sa = $null

            # create a new storage account
            $sa = New-AzureRmIsolatedStorageAccount -ExcludeClusters $excludedClusters -SkuName $SkuName -kind $kind -StorageAccountSuffix $StorageAccountSuffix -ResourceGroupName $ResourceGroupName -Location $Location

            if($sa -eq $null) {
                continue
            }

            # get the actual cluster name
            $saClusterDnsName = (Get-AzureRmStorageAccountCluster -StorageAccountName $sa.StorageAccountName -ResourceGroupName $ResourceGroupName)[0].ClusterName

            # add current cluster to the list
            $accountArray += New-Object psobject -Property @{
                StorageAccountName = $sa.StorageAccountName
                ClusterName = $saClusterDnsName
            }
            
            write-host "OK" -ForegroundColor Green
            Write-Host "Adding cluster $saClusterDnsName to list of excluded clusters..."
    
        }

        Write-host "`nJob completed."
    
    }catch{
        Write-Host $_.Exception.ToString() -ForegroundColor Red
        return
    }

    return $accountArray

}

<# 
.SYNOPSIS 
   This function will create a Classic storage account with a unique prefix. The function offers the option to avoid a specified list of storage clusters in a region.
.DESCRIPTION 
   The function first creates a storage account with a random prefix.
   It then creates a new Classic storage account.
   After the creation its cluster is queried.
   If the storage account has landed on a cluster that is among the list of excluded cluster the creation will be reattempted with a different account name up to 3 times, before the method fails over.
.EXAMPLE 
   New-AzureRmIsolatedStorageAccount -StorageAccountSuffix "storage" -Location "north europe" -SkuName Standard_LRS -ExcludeClusters db6prdstr02a,db5prdstr04a
   New-AzureRmIsolatedStorageAccount -StorageAccountSuffix "storage" -Location "north europe"
.INPUTS 
   StorageAccountSuffix | The second half of the resulting storage account name; for the purpose of this function the first half needs to be auto-generated
   Location | The Azure region, where the storage account should be created
   (optional) SkuName | one of the following: "Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS"
   (optional | array) ExcludedClusters | a list of excluded cluster names (e.g. "db6prdstr02a,db5prdstr04a")
.OUTPUTS 
   The newly created storage account
#>
function New-AzureIsolatedStorageAccount
{
 param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$StorageAccountSuffix,

    [Parameter(Mandatory=$True)]
    [string]$Location,

    [ValidateSet("Standard_LRS", "Standard_ZRS", "Standard_GRS", "Standard_RAGRS", "Premium_LRS")]
    [string]$SkuName="Standard_LRS",

    [array]$ExcludeClusters=@()

 )

    $storageAccountName = Get-StorageAccountNameWithRandomPrefix($StorageAccountSuffix)

    # creating the storage account 
    $storageAccount = New-AzureStorageAccount -StorageAccountName $storageaccountname -Location $location -Type $skuName -WarningAction SilentlyContinue

    # do we need to check for excluded clusters
    if ($ExcludeClusters.Length -gt 0) {
        
        $maxAttempts = 3
        $creationAttempt = 0

        for($i = 0; $i -lt $ExcludeClusters.Length; $i++) {
            $ExcludeClusters[$i] = $ExcludeClusters[$i].ToString().ToLower().Trim()
        }
        
        $isValid = $false

        do {
            $creationAttempt++

            if($creationAttempt -gt $maxAttempts) {
                write-host "KO! Reached max. number of attempts $maxAttempts " -ForegroundColor Red
                return;
            }

            # get resulting cluster 
            $cluster = (Get-AzureStorageAccountCluster -StorageAccountName $storageaccountname)[0].ClusterName
            Write-Host " Account is on cluster $cluster"

            # have we landed on a forbidden cluster
            if($ExcludeClusters.Contains($cluster.ToString().ToLower().Trim())) {
                write-host "KO! Storage account is on cluster $cluster, which is part of the excluded clusters. Removing account..." -ForegroundColor Yellow
                Remove-AzureStorageAccount -StorageAccountName $storageAccountName -WarningAction SilentlyContinue

                if($creationAttempt -lt $maxAttempts) {
                    
                    write-host "Attempting recreation... " -ForegroundColor Cyan
                    $storageAccountName = Get-StorageAccountNameWithRandomPrefix($StorageAccountSuffix)

                    # re-creating the storage account 
                    $storageAccount = New-AzureStorageAccount -StorageAccountName $storageaccountname -Location $location -Type $skuName -WarningAction SilentlyContinue
                
                }
            } else {
                $isValid = $true
            }

        } while (!$isValid)
    }

    Write-Host "OK" -ForegroundColor Green

    return $storageAccount
}


Export-ModuleMember Get-AzureRmStorageAccountInSameCluster, Get-AzureRmStorageAccountCluster, New-AzureRmIsolatedStorageAccount, New-AzureRmIsolatedStorageAccountList, Get-AzureStorageAccountCluster, New-AzureIsolatedStorageAccount