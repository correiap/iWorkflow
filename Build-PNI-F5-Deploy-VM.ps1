workflow Build-F5-VM
{
########################################################
#
#   Script to deploy n instances (up to 4) of F5
#   This script also calls Build-F5-Mgmg-NATRules script
#	and Build-iWorkflow-Integration script
#
#
#   Parameters:
#   All Parameters will come from Run-F5-VM Runbook
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

	[Parameter(Mandatory=$True)]
    [string]
    $Retailer,

	[Parameter(Mandatory=$True)]
    [string]
    $Country,

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
    $licenseKey4 = "4444",
   
    [Parameter(Mandatory=$True)]
    [string]
    $ResourceGroupName,

	[Parameter(Mandatory=$True)]
    [string]
    $vnetName,

	[Parameter(Mandatory=$True)]
    [string]
    $location,

    [Parameter(Mandatory=$True)]
    [string]
    $templateURI,

    [Parameter(Mandatory=$True)]
    [string]
    $adminUsername,

    [Parameter(Mandatory=$True)]
    [string]
    $Adminpwd,

    [Parameter(Mandatory=$True)]
    [string]
    $VMPrefix,

    [Parameter(Mandatory=$True)]
    [string]
    $subnetName,

    [Parameter(Mandatory=$True)]
    [int]
    $copyindex

)

    #Connect to Azure, right now it is only interactive login
    #Log into Azure
    Write-Output "Logging into Azure using SPN and Certificate"
    #Establish Automation Account identity.
    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    $azSub = (Select-AzureRmSubscription -SubscriptionName $Subscription)
    
    $pwd = ConvertTo-SecureString -String $Adminpwd -AsPlainText -Force
   

        Write-Output ("Build Runbook - Deployment in Progress...")

       #$ReturnStatus = @{ status = $true } 
		#try {
			$deployment = New-AzureRmResourceGroupDeployment -Verbose  -ResourceGroupName $ResourceGroupName -TemplateUri $templateURI  -adminUsername "$adminUsername" -adminPassword $pwd -dnsLabel "$VMPrefix" -numberOfInstances "$numberOfInstances" -domainName "pniazure.local" -existingResourceGroupName $ResourceGroupName -existingVnetName "$vnetName" -existingSubnetName "$subnetName" -licenseKey1 "$licenseKey1" -licenseKey2 "$licenseKey2" -licenseKey3 "$licenseKey3" -licenseKey4 "$licenseKey4" -indexCopy $copyindex -environment $Environment -retailer $Retailer -country $Country

          
        
       # }catch {
			#Write-Output $_.Exception.Message
			#$ReturnStatus = @{ status = $false }
		#}

		

    #$deployment
	#return $ReturnStatus        
    
    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    $azSub = (Select-AzureRmSubscription -SubscriptionName "PNI Azure Enterprise")


    $params = @{
		"Key" = $key;
        "resourceGroupName" = $resourceGroupName;
        "Environment" = $Environment;
        "Retailer" = $Retailer;
        "Country" =  $Country;
        "numberOfInstances" = $numberOfInstances;
        "Location" = $Location;
        "Subscription" = $Subscription;
    }

    Write-Output "ALB and NAT Inbound Rules Creation"
    Start-AzureRmAutomationRunbook -Name "Build-F5-Mgmt-NATRules" -Parameters $Using:params -ResourceGroupName "pniglobal" -AutomationAccountName "pniglobalautoacct" -Wait



$connection = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    $azSub = (Select-AzureRmSubscription -SubscriptionName "PNI Azure Enterprise")

    $params = @{
		"Key" = $key;
        "resourceGroupName" = $resourceGroupName;
       "Environment" = $Environment;
        "Retailer" = $Retailer;
        "Country" =  $Country;
        "Subscription" = $Subscription;
    }

        Write-Output "iWorkflow Integration"
        Start-AzureRmAutomationRunbook -Name "Build-iWorkflow-Integration" -Parameters $Using:params -ResourceGroupName "pniglobal" -AutomationAccountName "pniglobalautoacct" -Wait
               
 return 

}
