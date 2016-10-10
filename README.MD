How to load the module:
=======================

	Import-Module "C:\modules\AzureIsolatedStorageAccount.psm1"

Features:
=========

• Discover storage cluster associations

  - per storage account
  - per resource group *ARM-only*
  - for the whole subscription

• Create a storage account avoiding one or more specified clusters

• Create a specified number of storage accounts in a resource group, all on different clusters *ARM-only*

• Create a specified number of storage accounts in a resource group, all on clusters that have not yet been used in said resource group *ARM-only*

• Create a specified number of storage accounts in a resource group, all on different clusters, but only if no other storage account pair in the resource group already shares a cluster *ARM-only*

Available commands:
===================

**Get-AzureRmStorageAccountCluster**
**Get-AzureStorageAccountCluster**

Displays the current storage account cluster allocation for 

• the whole subscription (if no parameters are specified)

• a specified resource group (if the parameter is specified)

• a specific storage account (if specified)

Usage:
	
	Get-AzureRmStorageAccountCluster -ResourceGroupName $ResourceGroupName
	Get-AzureStorageAccountCluster -StorageAccountName $StorageAccountName

Sample Output:
	
	Get-AzureStorageAccountCluster
	Getting clusters for all Classic storage accounts ...OK
	
	ClusterName  StorageAccountName
	-----------  ------------------
	hknprdstr09a 0kaeaacc          
	sn4prdstr02a antifabdiag       
	sn4prdstr03a antifabstor2      
	sn4prdstr02a antifabstore      
	bl5prdstr04a clinstor          
	hk2prdstr02a eaglobal          
	hk2prdstr06a ealocal           
	hk2prdstr02a earagrs           
	sn4prdstr03a mymachscent  

**New-AzureRmIsolatedStorageAccount**
**New-AzureIsolatedStorageAccount**

Creates a single storage account. The user can specify cluster names that should be avoided during creation. 
Storage account name is created with a 3-alphanumeric random prefix and a given suffix.
The command verifies if the randomly created name is globally available and, if not, it generates a new name.

If a storage account lands on an excluded cluster, the creation will be retried three times. 

Usage:
	
	New-AzureRmIsolatedStorageAccount -StorageAccountSuffix $StorageAccountSuffix -ResourceGroupName $ResourceGroupName `
		-Location $Location -SkuName $SkuName `
		-kind BlobStorage -ExcludeClusters $ExcludedCluster1,$ExcludedCluster2
		
	New-AzureIsolatedStorageAccount -StorageAccountSuffix $StorageAccountSuffix -Location $Location `
		-SkuName Standard_LRS -ExcludeClusters $ExcludedCluster1,$ExcludedCluster2 
	
Sample Output:
	
	New-AzureIsolatedStorageAccount -StorageAccountSuffix "eaacc" -Location "East Asia" -SkuName Standard_LRS -ExcludeClusters hk2prdstr06a,hk2prdstr02a,hknprdstr09a 
	Create new storage account : ejueaacc  ...Getting cluster for ejueaacc ...OK
	 Account is on cluster hk2prdstr06a
	KO! Storage account is on cluster hk2prdstr06a, which is part of the excluded clusters. Removing account...
	
	Attempting recreation... 
	Create new storage account : rxveaacc  ...Getting cluster for rxveaacc ...OK
	 Account is on cluster hknprdstr08a
	OK


**New-AzureRmIsolatedStorageAccountList**

Creates a given number of storage account in the provided location and resource group.
Storage account name is created with a 3-alphanumeric random prefix and a given suffix.
The command verifies if the randomly created name is globally available and, if not, it generates a new name.

The RG is also created, if it does not already exist.

(optional) The command can analyse the provided ResourceGroup in search for storage accounts located on same storage clusters. 
(optional) The command can exclude all clusters that were previously (during previous deployments) used in the resource group when creating new accounts. 

*This cmdlet is ARM-only* - RDFE users should use a combination of Get-AzureStorageAccountCluster and New-AzureIsolatedStorageAccount

Usage:

	New-AzureRmIsolatedStorageAccountList -Location $location `
	    -ResourceGroupName $ResourceGroupName `
	    -StorageAccountSuffix $storageAccountSuffix `
	    -NumberOfAccounts 6 -kind BlobStorage -SkuName Standard_LRS `
	    -ValidateExistingStorageAccounts -DoNotCreateOnPreviouslyUsedClusters

Sample Output for successful creation:

	New-AzureRmIsolatedStorageAccountList -ResourceGroupName "RG-STorTest" -Location "North Europe" -StorageAccountSuffix "north" -DoNotCreateOnPreviouslyUsedClusters
	Starting job. Creating 3 storage accounts in North Europe for Resource Group RG-STorTest.
	
	Get Resource Group...OK
	Getting clusters for ARM storage accounts in the ResourceGroup ...OK
	The following clusters are already in use in the resource group. The job will try to avoid creating storage accounts on these clusters
	cq2prdstr01a cq2prdstr01a cq1prdstr01a am5prdstr07a am5prdstr12a am5prdstr02a
	
	*** Trying to create account # 1 of 3 ***
	Create new storage account : 95onorth  ...Getting cluster for storage account 95onorth in the ResourceGroup ...OK
	 Account is on cluster db3prdstr07a
	OK
	Getting cluster for storage account 95onorth in the ResourceGroup ...OK
	OK
	Adding cluster db3prdstr07a to list of excluded clusters...
	
	*** Trying to create account # 2 of 3 ***
	Create new storage account : k3rnorth  ...Getting cluster for storage account k3rnorth in the ResourceGroup ...OK
	 Account is on cluster db5prdstr04a
	OK
	Getting cluster for storage account k3rnorth in the ResourceGroup ...OK
	OK
	Adding cluster db5prdstr04a to list of excluded clusters...
	
	*** Trying to create account # 3 of 3 ***
	Create new storage account : rbxnorth  ...Getting cluster for storage account rbxnorth in the ResourceGroup ...OK
	 Account is on cluster db3prdstr05a
	OK
	Getting cluster for storage account rbxnorth in the ResourceGroup ...OK
	OK
	Adding cluster db3prdstr05a to list of excluded clusters...
	
	Job completed.
	
	ClusterName  StorageAccountName
	-----------  ------------------
	db3prdstr07a 95onorth          
	db5prdstr04a k3rnorth          
	db3prdstr05a rbxnorth          

**Get-AzureRmStorageAccountInSameCluster**

Analyze the provided ResourceGroup in search for storage accounts located on same sotrage clusters. 
If duplicates are found, the list is returned.

*This cmdlet is ARM-only*

Usage:

	Get-AzureRmStorageAccountInSameCluster -ResourceGroupName $ResourceGroupName

Sample Output (successful validation):

	Validating existing storage accounts in the ResourceGroup ...OK

Sample Output (failed validation):

	Validating existing storage accounts in the ResourceGroup ...KO! Found more than 1 storage accounts on same cluster:
	
	ClusterName  StorageAccountName
	-----------  ------------------
	db5prdstr03a 3nsrvtest         
	db5prdstr03a kfkrvtest         
	db4prdstr04a va3rvtest         
	db4prdstr04a vusrvtest         


