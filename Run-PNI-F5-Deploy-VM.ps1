workflow Run-F5-VM
{

########################################################
#
#   Script determine the number of F5 instances to deploy
#	it also creates a random password for the Admin user 
#	and stores it on KeyVault. Calls Build-F5-VM script
#
#
#   Parameters:
#   $Key - GitHub token to access private repository
#   $numberOfInstances - number of F5 instances to deploy
#   $Environment - PG, PR or QA
#	$Retailer - SPL, COS, FDX, SAM or TES
#	$Country - C, K or U
#   $resourceGroupName - Existing Resource Group Name where to deploy F5s
#   $vnetName - Existing VNET Name
#   $Location
#   $licenseKey1 - License key to use with VM 01 - if not to be created no need to provide it
#   $licenseKey2 - License key to use with VM 02 - if not to be created no need to provide it
#   $licenseKey3 - License key to use with VM 03 - if not to be created no need to provide it
#   $licenseKey4 - License key to use with VM 04 - if not to be created no need to provide it
#  
#
########################################################


param(

	[Parameter(Mandatory=$True)]
    [string]
	$Key,

    [Parameter(Mandatory=$True)]
    [string]
	$Subscription,
	
	[Parameter(Mandatory=$True)]
    [int]
	$numberOfInstances,
   
    [Parameter(Mandatory=$True)]
    [string]
    $Environment,

	[Parameter(Mandatory=$False)]
    [string]
    $Retailer,

	[Parameter(Mandatory=$False)]
    [string]
    $Country,

    [Parameter(Mandatory=$True)]
    [string]
    $resourceGroupName,

	[Parameter(Mandatory=$True)]
    [string]
    $vnetName,

	[Parameter(Mandatory=$True)]
    [string]
    $location,

   	[Parameter(Mandatory=$False)]
    [string]
    $licenseKey1 = "111",

	[Parameter(Mandatory=$False)]
    [string]
    $licenseKey2 = "222",

	[Parameter(Mandatory=$False)]
    [string]
    $licenseKey3 = "3333",

	[Parameter(Mandatory=$False)]
    [string]
    $licenseKey4 = "4444"

)

    #Connect to Azure, right now it is only interactive login
    #Log into Azure
    Write-Output "Logging into Azure using SPN and Certificate"
    #Establish Automation Account identity.
    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    $azSub = (Select-AzureRmSubscription -SubscriptionName $Subscription)
    
    
    $templateURI = "https://github-key.azurewebsites.net/content/" + $Key + "/master/iWorkflow/iWorkflow/AzureTemplates/PNI-f5-vm-deploy-v1.2-noPIP.json"
    
	
	#Initialize variables
    $numberOfExistingF5s = 0
	$copyindex = 0

	#Create F5 Objetcs Prefix
    $VMPrefix = $Environment + $Retailer + $Country
	Write-Output "VM Prefix: $VMPrefix"

	#Calculate the Number of Instances to deploy
    #Verify the Number of already deployed instances and set the appropriate number of instances to create
    for ($i=1; $i -le $numberOfInstances; $i++) {

		$VMname = $VMPrefix + "lb" + $i
        $VMExist = Get-AzureRmVM -name $VMname -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
	    
		if ($VMExist) {

			$numberOfExistingF5s++
		}
	}

    if ( $numberOfInstances -le $numberOfExistingF5s) 
    {    
        Write-Output "Instances already Exist, no new Delpoyments required"
   
     }

    else
    {
        
        #Set Admin Username for all F5 Instances
	    $adminUsername = "PNIF5Admin" + $VMPrefix
		
        #If new deployment create KeyVault entry
		$PNIAzureF5KeyVault = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $adminUsername)
		
		#Check if User/Password for the current Environment already exists, if not create it and store the values on KeyVault
		if ($PNIAzureF5KeyVault) {
			
			$Adminpwd = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $adminUsername).SecretValueText
            
			$SecureAdminpwd = ConvertTo-SecureString -String $Adminpwd -AsPlainText -Force
			
		} else {
		
		#Function to Generate Random Passwords - with only numbers and letters - Special characters causes issues when sending it on POSTs as JSON body 
		Function Get-GeneratedCustomPassword ($length = 24)
        {
    
            $punc = 46..46
            $digits = 48..57
            $letters = 65..90 + 97..122

            $TempPassword = get-random -count $length `
                -input ($punc + $digits + $letters) |
                 % -begin { $aa = $null } `
                    -process {$aa += [char]$_} `
                    -end {$aa}

            return $TempPassword
        }
		

	    #Generate Random Password
	    $Adminpwd = Get-GeneratedCustomPassword –length 24
       
		$SecureAdminpwd = ConvertTo-SecureString -String $Adminpwd -AsPlainText -Force

		#Save Username/Password to Keyvault
		$kv = Set-AzureKeyVaultSecret -VaultName "PNIAzureF5" -Name $adminUsername -SecretValue $SecureAdminpwd
        $Adminpwd = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $adminUsername).SecretValueText

	    
		}
				
        #Set Subnet Name
        $subnetName = $Environment + $Retailer + "lbf" + $Country
        
        #Real Number of Instances to Create
        $numberOfInstances = $numberOfInstances - $numberOfExistingF5s

        Write-Output "Number of Instances to Deploy"
        $numberOfInstances

        #Offset to be passed on to copyindex() based on the amount of instances to create
        $copyindex = 1 + $NumberofExistingF5s

        $totalInstances = $numberOfInstances + $NumberofExistingF5s


        $params = @{
		"Key" = $key;
        "numberOfInstances" = $numberOfInstances;
        "resourceGroupName" = $resourceGroupName;
        "vnetName" = $vnetName;
        "licenseKey1" =  $licenseKey1;
        "licenseKey2" = $licenseKey2;
        "licenseKey3" = $licenseKey3;
        "licenseKey4" = $licenseKey4;
        "Environment" = $Environment;
        "Retailer" = $Retailer;
        "Country" =  $Country;
        "location" = $location;
        "templateURI" = $templateURI;
        "adminUsername" = $adminUsername;
        "Adminpwd" = $Adminpwd;
        "VMPrefix" = $VMPrefix;
        "subnetName" = $subnetName;
        "copyindex" = $copyindex;
        "Subscription" = $Subscription;
		
	}


       # for ($copyindex; $copyindex -le $totalInstances; $copyindex++){
		
			Write-Output ("Deployment in Progress...")
           # $instances = 1

            $ReturnStatus = @{ status = $true }
		        try {
			        Start-AzureRmAutomationRunbook -Name "Build-F5-VM" -Parameters $Using:params -ResourceGroupName "pniglobal" -AutomationAccountName "pniglobalautoacct" -Wait
                 sleep -Seconds 5
		        } catch {
			        Write-Warning $_.Exception.Message
			        $ReturnStatus = @{ status = $false }
		        }

		           
			
		#}
        
 return $ReturnStatus

}
}