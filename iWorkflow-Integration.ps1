

##############################################################
# iWorkflow_Integration.ps1
#
#	This Script does the F5/iWorkflow Initial config
#	It will create (when needed): CloudConnectors, Discover F5 Devices,
#	Add Devices to Appropriate CloudConnector, Import Master iApp Template,
#	Create User to deploy iApps, Create HTTP, HTTPS and Non-Standard Service Catalog
#   Templates. It will also create all DATA-Groups and HTTP Profiles
#
##############################################################
param(

    
    [Parameter(Mandatory=$True)]
    [string]
    $Subscription,

    [Parameter(Mandatory=$True)]
    [string]
    $Environment,

	[Parameter(Mandatory=$True)]
    [string]
    $Retailer,

	[Parameter(Mandatory=$True)]
	[string]
	$Country,

	[Parameter(Mandatory=$True)]
	[string]
	$resourceGroupName
)



    # Connect to Azure, right now it is only interactive login
try {
    Write-Host "Checking if already logged in!"
    Get-AzureRmSubscription -SubscriptionName $Subscription
    Write-Host "Already logged in, continuing..."
    }
    Catch {
    Write-Host "Not logged in, please login..."
    Login-AzureRmAccount -SubscriptionName $Subscription
    }


    Import-Module -Name C:\Users\pedro_000\Source\Repos\Tunable-SSL-Validator\TunableSSLValidator.psm1



$iworkflowMgmt = "192.168.50.15"

$iAppServiceName = $resourceGroupName
$CustomerEnvironment = $iAppServiceName

#Assign Username and Password for iWorkflow Admin User
#$iWorkUserName = "PNIiWorkflowAdmin"
$iWorkUserName = "admin"
#$iWorkPassword = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $iWorkUserName).SecretValue
$iWorkPass = "admin"
$iWorkPassword = ConvertTo-SecureString -String $iWorkPass -AsPlainText -Force
$credential = New-Object -TypeName System.Management.automation.PSCredential -ArgumentList $iWorkUserName, $iWorkPassword

#Assign Username and Password for F5 Admin User
#$F5UserName = "PNIF5Admin" + $iAppServiceName
#$F5Password = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $F5UserName).SecretValueText

$F5UserName = "F5autAdmin"
$F5Password = "Scalar2017!!"


#Assign Username and Password for iWorkflow Service User
$iAppUser = "user"
$iAppUserpass = "user"
$pwd = ConvertTo-SecureString -String $iAppUserpass -AsPlainText -Force


# Discover/Add BIG-IPs
#POST to https://iworkflow.pnimedia.com/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/

#Initialize Variable to count number of already exsiting F5 VM Instances
$ExistingVMs = 0	
for ($i = 1; $i -le 4; $i++) {
	
		#Create a variable with the F5 VM name based on PNI naming convention
		$VMname = $iAppServiceName + "lb" + $i
		#Verify if VM name has been already deployed
		$VMexist = Get-AzureRmVM -name $VMname -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        if ($VMExist) {


			#if F5 VM already deployed, verify if it has already been discovered by iWorkflow - If not add device
			#Increase number or already deployed F5 VMs
			$ExistingVMs++
			#Get Public IP Address of F5s, based on PNI naming convention
			$PublicIP = $iAppServiceName + "le" + "vx" + "mgmt" + $i
           

            #Get and Assign, to a variable, F5s management Public IP Address
            $F5MgmtIP = (Get-AzureRmResource -ResourceName $PublicIP -ResourceType Microsoft.Network/publicIPAddresses -ResourceGroupName $resourceGroupName).Properties.ipAddress			
            Write-Output "MGMT IP: "
            $F5MgmtIP
            			
			#Get list of already discovered devices on iWorkflow
			$ExistingDevices = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/" -Method GET -ContentType "application/json" -Credential $credential -Insecure
			
			#Get the Tags associated with each F5 VM - UUID tag will tell if device has already been added to iWorkflow or not
			$iworkflowIDTag = (Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
			$uuid = $iworkflowIDTag.uuid
        
        
        #if ($uuid -eq "na"){
		if (!$uuid){		
                    $JSONBody = @"
                    {
                        "address": $F5MgmtIP,
                        "userName": $F5UserName,
                        "password": $F5Password,
                        "automaticallyUpdateFramework": true,
                        "properties": {
                        "dmaConfigPathScope": "basic",
                        "isSoapProxyEnabled": true,
                        "isTmshProxyEnabled": false,
                        "isRestProxyEnabled": true
                                        }
                        
                    }
"@
	
				
                #Discover device on iWorkflow
				$DiscoverDevice = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure
				
                #Wait until Discovery is concluded
                #sleep -Seconds 30

                
				#Grab UUID generated for just added device
				$DeviceUUID = $DiscoverDevice.uuid
				$uuid = $DeviceUUID

                Write-Output "Verify if Device was Discovered Successfully"
                do {

					
					#Wait a few seconds before getting the device State
					Write-Output "Wait 30 seconds for Device Discovery Status"
					sleep -Seconds 30

					#Discover Device Status
					$DiscoverDeviceStatus = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/$uuid" -Method GET -ContentType "application/json" -Credential $credential -Insecure
					Write-Output "Device Discovery Status for $uuid is: "
					$DiscoverDeviceStatus.state
					$DeviceState = $DiscoverDeviceStatus.state

					if ($DeviceState -ieq "FAILED") {

						Write-Output "Device Discovery Failed, remove it and discover it again"

						#Remove Device and add it again
						$RemoveDevice = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/$uuid" -Method DELETE -ContentType "application/json" -Credential $credential -Insecure
						$ReDiscoverDevice = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure
						$uuid = $ReDiscoverDevice.uuid
						Write-Output "New uuid is: $uuid"
						

				}


				}
				until ($DeviceState -ieq "ACTIVE")

				

				#Update UUID tag for F5 VM just added
				$iworkflowIDTag += @{uuid="$uuid"}
				

				#Update Tags
				$UpdateTags = Set-AzureRmResource -ResourceName $VMname -Tag $iworkflowIDTag -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachines -Force
				(Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
				
        }       
        
    }
}
# Create Cloud Connector
    #POST to https://iworkflow.onimedia.com/mgmt/cm/cloud/connectors/local

    #Create/Get Existing CloudConnectors
    for ($i=1; $i -le $ExistingVMs; $i++ ) {
        
        Write-Output "Cloud Connector Name"
        $CloudConnectorName = $CustomerEnvironment + 'CC' + $i
        $CloudConnectorName

        Write-Output "F5 Name"
        $VMname = $iAppServiceName + "lb" + $i
        $VMname      

        $CloudConnector = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/connectors/local" -Method GET -ContentType "application/json" -Credential $credential -Insecure
        
        #Get UUID for device to add to Cloud Connector
        $iworkflowIDTag = (Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
		$uuid = $iworkflowIDTag.uuid
        $uuIdLink = "https://localhost/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/" + $uuid

    #Verify if CloudConnecotr for CustomerEnvironment exists, if not create one 
        if ($CloudConnector.items.name -notcontains $CloudConnectorName) {

            $JSONBody = @"
            {
                "name": "$CloudConnectorName",
                "description": "$CloudConnectorName",
                "deviceReferences": [ {"link": "$uuIdLink"} ]
    
            }
"@

            $CloudConnector = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/connectors/local" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure

            $ConnectorID = $CloudConnector.connectorid
            $iworkflowIDTag += @{connectorid="$ConnectorID"}
		    $UpdateTags = Set-AzureRmResource -ResourceName $VMname -Tag $iworkflowIDTag -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachines -Force
	
            #Wait until Cloud Connector is created
            sleep -Seconds 5
        }
    }

# Create Users, Tenants and assign Roles
# POST to https://iworkflow.pnimedia.com/mgmt/shared/authz/users

# Create user to deploy iApps

$VerifyUser = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/authz/users" -Method GET -ContentType "application/json" -Credential $credential -Insecure

#Verify if User has been created already, if not create an User, Tenant and Asign role to User to deploy the iApps
if ($VerifyUser.items.name -notcontains $iAppUser) {

$JSONBody = @"
 {
    "displayName": $iAppUser,
    "password": $iAppUserPass,
    "name": $iAppUser
}
"@

$CreateUser = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/authz/users" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure

#Create Varibale with Tenant Name
$TenantName = $iAppServiceName + "Tenant"

$ConnectortoAdd = @()

for ($i=1; $i -le $ExistingVMs; $i++ ) {
    $VMname = $iAppServiceName + "lb" + $i
    
        Write-Output "Create new Tenant for: "
        $TenantName

        $iworkflowIDTag = (Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
	    $ConnectorID = $iworkflowIDTag.connectorid
        Write-Output "Connector ID"
        $ConnectorID
        $TenantLink = "https://localhost/mgmt/cm/cloud/connectors/local/" + $ConnectorID
        
        $ConnectortoAdd += @{link="$TenantLink"}
}
        
        
    $JSONBody = @{name=$TenantName;cloudConnectorReferences=$ConnectortoAdd} | ConvertTo-Json

    $MyTenant = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/tenants" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure
    
	#Assign Role
	#PUT to https://{{iworkflow_mgmt}}/mgmt/shared/authz/roles/

	$RoleLink = "https://localhost/mgmt/shared/authz/users/" + $iAppUser

	$Path = "CloudTenantAdministrator_" + $TenantName

	$MyTenantRoles = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/authz/roles/$Path" -ContentType "application/json" -Credential $credential -Insecure

 
	#Assigne User to Role
	#PUT to https://iworkflow.pnimedia.com/mgmt/shared/authz/roles

	$RoleResources = $MyTenantRoles.resources | ConvertTo-Json


	$JSONBody = @"
	{
	"name": "$Path",
	"displayName": "$TenantName",
	"userReferences": [
		{
		"link": "$RoleLink"
		}
	],
	"resources": $RoleResources,
	"kind": "shared:authz:roles:rolesworkerstate"
 
}
"@



	$RoleUser = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/shared/authz/roles" -Method PUT -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure


}

# Import iApp Services Template and Create Service Catalog

# Verify if exists then Import iApp Template - 
# POST to https://iworkflow.pnimedia.com/mgmt/cm/cloud/templates/iapp
	$iAppTemplate = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/templates/iapp" -Method GET -ContentType "application/json" -Credential $credential -Insecure


	if ($iAppTemplate.items.name -notcontains "appsvcs_integration_v2.0.004") {


		$URI = "https://raw.githubusercontent.com/correiap/iWorkflow/master/iApp-Integration_json/iWorkflow_appsvcs_integration_v2.0.004.json"
		$JSONBody = (Invoke-WebRequest -Uri "$URI" -UseBasicParsing).Content
		$iAppTemplate = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/templates/iapp" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure
	}



	# Verify if Template/Catalog exists then crete it for HTTP and HTTPS - POST to https://{{iworkflow_mgmt}}/mgmt/cm/cloud/provider/templates/iapp

	$iAppServiceTemplate = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/provider/templates/iapp" -Method GET -ContentType "application/json" -Credential $credential -Insecure

	$CustomerEnvironmentHTTP = $CustomerEnvironment + "-HTTP"

	if ($iAppServiceTemplate.items.templatename -notcontains $CustomerEnvironmentHTTP) {

		#HTTP Template
		$CustomerEnvironmentHTTP = $CustomerEnvironment + "-HTTP"
		$TemplateURI = "https://raw.githubusercontent.com/correiap/iWorkflow/master/Catalogs_json/HTTP-PNI_catalog_multiCC_v2.0.004.json"
		$JSONBody = (Invoke-WebRequest -Uri "$TemplateURI" -UseBasicParsing).Content
		$JSONBody = $JSONBody -replace "appsvcs_templatename", $CustomerEnvironmentHTTP
		$iAppServiceTemplate = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/provider/templates/iapp" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure


		#HTTPS Template
		$CustomerEnvironmentHTTPS = $CustomerEnvironment + "-HTTPS"
		$TemplateURI = "https://raw.githubusercontent.com/correiap/iWorkflow/master/Catalogs_json/HTTPS-PNI_catalog_multiCC_v2.0.004.json"
		$JSONBody = (Invoke-WebRequest -Uri "$TemplateURI" -UseBasicParsing).Content
		$JSONBody = $JSONBody -replace "appsvcs_templatename", $CustomerEnvironmentHTTPS
		$iAppServiceTemplate = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/provider/templates/iapp" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure

		#Non-Standard Template
		$CustomerEnvironmentNS = $CustomerEnvironment + "-NS"
		$TemplateURI = "https://raw.githubusercontent.com/correiap/iWorkflow/master/Catalogs_json/Non-Standard-PNI_catalog_multiCC_v2.0.004.json"
		$JSONBody = (Invoke-WebRequest -Uri "$TemplateURI" -UseBasicParsing).Content
		$JSONBody = $JSONBody -replace "appsvcs_templatename", $CustomerEnvironmentNS
		$iAppServiceTemplate = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/provider/templates/iapp" -Method POST -Body $JSONBody -ContentType "application/json" -Credential $credential -Insecure


}


# Create Data-Groups

# Function to push Data Group Configuration to F5s
	function ConfigureDataGroup ($DataGroupName)
{

    $URI = "https://raw.githubusercontent.com/correiap/iWorkflow/master/data-groups/" + $DataGroupName + ".json"
    $JSONBody = Invoke-RestMethod -Uri "$URI"  | ConvertTo-Json
    $URI = "https://" + $iworkflowMgmt + "/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/" + $DGuuid + "/rest-proxy/mgmt/tm/ltm/dataGroup/internal/"
    $DataGroupPost = Invoke-RestMethod -Uri "$URI" -Method Post -Body $JSONBody -ContentType "application/json" -Credential $Credential -Insecure

}



for ($i = 1; $i -le 4; $i++) {
	
			#Create a variable with the F5 VM name based on PNI naming convention
			$VMname = $iAppServiceName + "lb" + $i
			#Verify if VM name has been already deployed
			$VMexist = Get-AzureRmVM -name $VMname -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
		
Write-Output "DG LOOP: $i"
$VMname
        
			if ($VMExist) {
				#Verify if Data-Group has already been created
				#Get the Tags associated with each F5 VM - Data-Group indicates if DG were created or not
				$VMTags = (Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
                      

				$DGTag = $VMTags.DataGroup
               
				if (!$DGTag){
                    
                    Write-Output "Creating Data-Groups for: "
				    $VMname
					#Create Data-Groups - Use the uuid Tag to do a POST through iWorkflow

					$DGuuid = $VMTags.uuid

					ConfigureDataGroup -DataGroupName test-DG
					
                
					#Update DataGroup Tag
					$DGTag = "True"
				
					$VMTags += @{DataGroup="$DGTag"}

					#Update Tags
					$UpdateTags = Set-AzureRmResource -ResourceName $VMname -Tag $VMTags -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachines -Force
				

            
				}
			}
		}


#Create HTTP Profiles
# Function to push HTTP Profile Configuration to F5s
	function ConfigureHTTPProfile ($HTTPProfileName)
	{
		$URI = "https://raw.githubusercontent.com/correiap/iWorkflow/master/HTTP-Profiles/" + $HTTPProfileName + ".json"
    	$JSONBody = Invoke-RestMethod -Uri "$URI" | ConvertTo-Json
    	$URI = "https://" + $iworkflowMgmt + "/mgmt/shared/resolver/device-groups/cm-cloud-managed-devices/devices/" + $HPuuid + "/rest-proxy/mgmt/tm/ltm/profile/http"
    	$HPPost = Invoke-RestMethod -Uri "$URI" -Method Post -Body $JSONBody -ContentType "application/json" -Credential $Credential -Insecure
		
	}
	for ($i = 1; $i -le 4; $i++) {
	
			#Create a variable with the F5 VM name based on PNI naming convention
			$VMname = $iAppServiceName + "lb" + $i
			#Verify if VM name has been already deployed
			$VMexist = Get-AzureRmVM -name $VMname -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
		 
        

			if ($VMExist) {
				#Verify if HTTP Profiles have already been created
				

				#Get the Tags associated with each F5 VM - HTTPProfile indicates if it were created or not
				$VMTags = (Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
            
				$HPTag = $VMTags.HTTPProfile

				if (!$HPTag){

                    Write-Output "Creating HTTP Profiles for: "
				    $VMname 
            
					#Create HTTP Profiles - Use the uuid Tag to do a POST through iWorkflow
					$HPuuid = $VMTags.uuid
                  
                
					ConfigureHTTPProfile -HTTPProfileName profile-http-pni
					ConfigureHTTPProfile -HTTPProfileName profile-http-pni-secure
                
					#Update Tag
					$HPTag = "True"

					$VMTags += @{HTTPProfile=$HPTag}
				
					#Update Tags
					$UpdateTags = Set-AzureRmResource -ResourceName $VMname -Tag $VMTags -ResourceGroupName $resourceGroupName -ResourceType Microsoft.Compute/virtualMachines -Force
				

            
				}
			}



	}

  Write-Output "Integration with iWorkflow Completed Successfully"


