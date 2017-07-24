##############################################################
# iWorkflow_Service_Deployment.ps1
#
#	This script scans all Availability Sets on a Resource Groupe
#	and as soon as the "IsApp" flag is set to "True", and an App ALB
#	exists for the App, it creates a new FrontEnd IP configuration
#	and new ALB rule for both External and Internal ALBs. Finally 
#	it deploys an iApp, through iWorkflow, from the Service Catalog
#	onto the F5s based on the customer environment
#
##############################################################

param(


	[Parameter(Mandatory=$True)]
    [string]
	$Key,

    [Parameter(Mandatory=$True)]
    [string]
	$Subscription,

    [Parameter(Mandatory=$True)]
    [string]
	$resourceGroupName,
   
    [Parameter(Mandatory=$True)]
    [string]
    $Environment,

	#[Parameter(Mandatory=$True)]
    #[string]
    #$Retailer,

	#[Parameter(Mandatory=$True)]
    #[string]
    #$Country,

	[Parameter(Mandatory=$True)]
    [string]
    $Location


	
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

#Transform all Parameters to Lowercase - All settings on the F5 are Case Sensitive
$resourceGroupName = $resourceGroupName.ToLower()



$CustomerCloudEnvironment = $resourceGroupName
$CustomerEnvironment = $CustomerCloudEnvironment
$iAppServiceName = $CustomerCloudEnvironment + "Service"

Write-Output "Service Name"
$iAppServiceName

Write-Output "Cloud"
$CustomerEnvironment

#Assign Username and Password for iWorkflow Admin User
#$iWorkUserName ="PNIiWorkflowAdmin"
#$iWorkPassword = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $iWorkUserName).SecretValueText
$iWorkUserName = "admin"
$iWorkPassword = "admin"

#Assign Username and Password for F5 Admin User
#$F5UserName = "PNIF5Admin"
#$F5Password = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $F5UserName).SecretValueText
$F5UserName = "F5autAdmin"
$F5Password = "Scalar2017!!"


#Assign Username and Password for iWorkflow Service User
#$iAppUser = "PNIiWorkflowUser" + $CustomerCloudEnvironment
#$iAppUserpass = (Get-AzureKeyVaultSecret -VaultName PNIAzureF5 -Name $iAppUser).SecretValueText
$iAppUser = "user"
$iAppUserpass = "user"

$passwordsecure = ConvertTo-SecureString $iWorkPassword -AsPlainText -Force
$credential = New-Object -TypeName System.Management.automation.PSCredential -ArgumentList $iWorkUserName, $passwordsecure

$iAppUserPassSecur = ConvertTo-SecureString $iAppUserPass -AsPlainText -Force
$iAppUserCred = New-Object -TypeName System.Management.automation.PSCredential -ArgumentList $iAppUser, $iAppUserPassSecur


#Function to get the Number of F5 VMs deployed
			function GetF5VMCount () {
			$ExistingVMs = 0
			for ($i = 1; $i -le 4; $i++) {
			$VMname = $CustomerCloudEnvironment + "lb" + $i
			#Verify if VM name has been already deployed
			$VMexist = Get-AzureRmVM -name $VMname -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
					if ($VMExist) {


						#if F5 VM already deployed, verify if it has already been discovered by iWorkflow - If not add device
						#Oncrease number or already deployed F5 VMs
						$ExistingVMs++
						}
				}
				return $ExistingVMs
			}



#Function to Deploy iApp Service Through iWorkflow
function DeployiAppService ($iAppName, $iAppIP, $iAppPort, $iAppPoolIP) {

                $iworkflowMgmt = "192.168.50.15"
                $ExistingVMs = GetF5VMCount

                for ($k = 1; $k -le $ExistingVMs; $k++ ) {	

                #Create a variable with the F5 VM name based on PNI naming convention
				$VMname = $CustomerCloudEnvironment + "lb" + $k
				Write-Output "VM Name"
				$VMname
				#Verify if VM name exists
				$VMexist = Get-AzureRmVM -name $VMname -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
        
				if ($VMExist) {

					Write-Output "VM Name Exists"
            
					$CloudConnectorIDTags = (Get-AzureRmResource -ResourceName $VMname -ResourceGroupName $resourceGroupName).Tags
					$CloudConnectorID = $CloudConnectorIDTags.connectorid
					Write-Output "Connector ID"
					$CloudConnectorID

					$iAppNameCloud = $iAppName + $k 
					#$iAppNameCloud

					if ($iAppPort -eq 80) {
    
						Write-Output "Deploy iApp for Port 80 - HTTP Service"
						$TemplateURI = "https://github-key.azurewebsites.net/content/" + $Key + "/master/iWorkflow/iWorkflow/service_json/HTTP_service_v2.0.004.json"
						$JSONBody = (Invoke-WebRequest -Uri "$TemplateURI" -UseBasicParsing).Content
                        
                        $iRuleArray = $iRuleArray
						For ($j=0; $j -le 9; $j++) {
    
							$iRule = $iRuleArray[$j]
							$iRuleLink = "irule:urloptional=https://raw.githubusercontent.com/correiap/iWorklow-Test/master/" + $iRule + ".irule"
							$JSONBody = $JSONBody -replace "irule:urloptional=appsvcs_irule$j", $iRuleLink

							}

						$CustomerEnvironmentTemplate = $CustomerEnvironment + "-HTTP"
						
							Write-Output "CLOUD CONNECTOR ID: " $CloudConnectorID

						$JSONBody = $JSONBody -replace "appsvcs_name", $iAppNameCloud
						$JSONBody = $JSONBody -replace "appsvcs_template", $CustomerEnvironmentTemplate
						$JSONBody = $JSONBody -replace "appsvcs_vip_addr", $iAppIP
						$JSONBody = $JSONBody -replace "appsvcs_vip_port", $iAppPort
						$JSONBody = $JSONBody -replace "appsvcs_member1_addr", $iAppPoolIP
						$JSONBody = $JSONBody -replace "iwf_connector_uuid", $CloudConnectorID


        
					} elseif ($iAppPort -eq 443) {
            
						Write-Output "Deploy iApp for Port443 - HTTPS Service"
                        $TemplateURI = "https://github-key.azurewebsites.net/content/" + $Key + "/master/iWorkflow/iWorkflow/service_json/HTTPS_service_v2.0.004.json"
						$JSONBody = (Invoke-WebRequest -Uri "$TemplateURI" -UseBasicParsing).Content
	
    
						$iRuleArray = $iRuleArray
						For ($j=0; $j -le 9; $j++) {
    
							$iRule = $iRuleArray[$j]
							$iRuleLink = "irule:urloptional=https://raw.githubusercontent.com/correiap/iWorklow-Test/master/" + $iRule + ".irule"
							$JSONBody = $JSONBody -replace "irule:urloptional=appsvcs_irule$j", $iRuleLink
    
							}

                       

						$CustomerEnvironmentTemplate = $CustomerEnvironment + "-HTTPS"
					#Write-Output " TEMPLATE"
					#$CustomerEnvironmentTemplate

					$JSONBody = $JSONBody -replace "appsvcs_name", $iAppNameCloud
					$JSONBody = $JSONBody -replace "appsvcs_template", $CustomerEnvironmentTemplate
					$JSONBody = $JSONBody -replace "appsvcs_vip_addr", $iAppIP
					$JSONBody = $JSONBody -replace "appsvcs_vip_port", $iAppPort
					$JSONBody = $JSONBody -replace "appsvcs_clientssl_cert", $ClientSSLCert
					$JSONBody = $JSONBody -replace "appsvcs_clientssl_key", $ClientSSLKey
					$JSONBody = $JSONBody -replace "appsvcs_clientssl_chain", $ClientSSLCert
					$JSONBody = $JSONBody -replace "appsvcs_member1_addr", $iAppPoolIP
					$JSONBody = $JSONBody -replace "iwf_connector_uuid", $CloudConnectorID

				}

				else {

					Write-Output "Deploy iApp for Port $iAppPort - Non-Standard Service"
                    $TemplateURI = "https://github-key.azurewebsites.net/content/" + $Key + "/master/iWorkflow/iWorkflow/service_json/Non-Standard_service_v2.0.004.json"
					$JSONBody = (Invoke-WebRequest -Uri "$TemplateURI" -UseBasicParsing).Content
	
    
						$iRuleArray = $iRuleArray
						For ($j=0; $j -le 9; $j++) {
    
						$iRule = $iRuleArray[$j]
						$iRuleLink = "irule:urloptional=https://raw.githubusercontent.com/correiap/iWorklow-Test/master/" + $iRule + ".irule"
						$JSONBody = $JSONBody -replace "irule:urloptional=appsvcs_irule$j", $iRuleLink
    
						}

					$CustomerEnvironmentTemplate = $CustomerEnvironment + "-NS"
					#Write-Output " TEMPLATE"
					#$CustomerEnvironmentTemplate

					$JSONBody = $JSONBody -replace "appsvcs_name", $iAppNameCloud
					$JSONBody = $JSONBody -replace "appsvcs_template", $CustomerEnvironmentTemplate
					$JSONBody = $JSONBody -replace "appsvcs_vip_addr", $iAppIP
					$JSONBody = $JSONBody -replace "appsvcs_vip_port", $iAppPort
					$JSONBody = $JSONBody -replace "appsvcs_member1_addr", $iAppPoolIP
					$JSONBody = $JSONBody -replace "appsvcs_member1_port", $iAppPort
					$JSONBody = $JSONBody -replace "iwf_connector_uuid", $CloudConnectorID



				}
        }
        $Tenant = $CustomerCloudEnvironment + "Tenant"
       
        
        $iAppService = Invoke-RestMethod -Uri "https://$iworkflowMgmt/mgmt/cm/cloud/tenants/$Tenant/services/iapp" -Method Post -Body $JSONBody -ContentType "application/json" -Credential $iAppUserCred -Insecure

    }


    }

	
#======================================================
	#AVset operations to scan and get tags of them all

	#get all AVSets belonging to a Resource Group
	$avset = Get-AzureRmAvailabilitySet -ResourceGroupName $resourceGroupName

	$numberOfAVSet = $avset.Count

    Write-Output "Number of AVSets with to Scan"
    $numberOfAVSet

	for ($i=0; $i -lt $numberOfAVSet; $i++) {

		#Assign iRules to an Array to replace it on the JSON Body for posting
		$iRuleArray = @()

		#Get the tags of all av sets to see which ones have the iApp=True tag
		#$AVSetName = $avset.name[$i]
        #TEMP
        $AVSetName = $avset.name[$i]

		$AVSetTags = (Get-AzureRmAvailabilitySet -Name $AVSetName -ResourceGroupName $resourceGroupName).Tags

		$isApp = $AVSetTags.IsApp
        
			if ($isApp -ieq "true") {
                        
				Write-Output "Deploy iApp for: " $AVSetName
				#Start deployment process
				#Grab all info required. Port, SSL Certificate and iRule
            
				#Get ALB name - Then Pool Member IP
				$ALBName = $AVSetName
                $basename = $AVSetName.Substring(0,$AVSetName.Length-2) 
				$ALBAppName = $basename + "la"

               
				
                #$ALBApp = Get-AzureRmLoadBalancer -Name $ALBAppName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
                #if ($ALBApp){
                    #Write-Output "ALB App Exists: $ALBAppName"
            
				#GET FrontEnd IP for App ALB
                #$iAppPoolIP = (Get-AzureRmLoadBalancer -Name $ALBAppName -ResourceGroupName $resourceGroupName).FrontendIpConfigurations.PrivateIPAddress
                $iAppPoolIP = "4.4.4.4"
                
                            
                $PortProtocol1 = $AVSetTags.ALBPort1
                $PortProtocol2 = $AVSetTags.ALBPort2
                $PortProtocol3 = $AVSetTags.ALBPort3

				$iAppPort = @(); $Protocol = @()
                if ($PortProtocol1) {$iAppPort += $PortProtocol1.Split(':')[0]; $Protocol += $PortProtocol1.Split(':')[1]}
                if ($PortProtocol2) {$iAppPort += $PortProtocol2.Split(':')[0]; $Protocol += $PortProtocol2.Split(':')[1]}
                if ($PortProtocol3) {$iAppPort += $PortProtocol3.Split(':')[0]; $Protocol += $PortProtocol3.Split(':')[1]}

                if ($iAppPort -contains "80") {$iAppPort += @("443"); $Protocol += @("tcp")}
                 
				Write-Output "Ports and Protocols"
				$iAppPort
                $Protocol
                
				$ClientSSLCertTag = $AVSetTags.SSLCertificate
				Write-Output "SSL Certificate"
                $ClientSSLCertTag
				if ($ClientSSLCertTag -eq "empty") {$ClientSSLCert = "/Common/default.crt"; $ClientSSLKey = "/Common/default.key" }
                $ClientSSLCert
                $ClientSSLKey

				#Grab iRules
				$iRules = $AVSetTags.iRule
				$iRules = $iRules -split ','
				#Loop to assign all the iRules to an Array
				Write-Output "iRules"
				for ($j=0; $j -lt $iRules.Length;$j++) {
            
					#Assign iRules to iRule Array
					$iRuleArray += @($iRules[$j])
					$iRuleArray[$j]
            
				}

#Update ALBs

#======================= INTERNAL ALB ===================================
			#Verify if ALBIn already Exists

			$ALBInName = $resourceGroupName + "li"
            Write-Output "ALB NAME: $ALBInName"

			$ALBIn = Get-AzureRmLoadBalancer -Name $ALBInName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
           

				#Objects that don't change name
				$VnetName = $resourceGroupName + "vn"
				$subnetName = $resourceGroupName + "sn"
               
				$BackEndPoolName = $ALBInName + "be"
				$ProbeName = $ALBInName + "hp"

       			if ($ALBIn) {
				#Update ALB In to add new Rule
			    Write-Output "ALB Internal exists"
                
			    #Add new FrontEndIP, if required
                $FrontEndName = $AVSetName + "fe"
                $FrontEnd = Get-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -LoadBalancer $ALBIn -ErrorAction SilentlyContinue
                if (!$FrontEnd){
                    Write-Output "Create new FrontEndIP: $FrontEndName"
				    $VMNet = Get-AzureRmVirtualNetwork -Name $VnetName -ResourceGroupName $resourceGroupName
				    $Subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VMNet -Name $subnetName
                    $outnull = $ALBIn | Add-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -Subnet $Subnet
                    $outnull = $ALBIn | Set-AzureRmLoadBalancer
                }

                #Remove temporary FrontEndIP
                $TempFrontEndIPName = $ALBInName + "temp1"
                $ALBIn = Get-AzureRmLoadBalancer -Name $ALBInName -ResourceGroupName $resourceGroupName
                
                $TempFrontEndIP = Get-AzureRmLoadBalancerFrontendIpConfig -LoadBalancer $ALBIn -Name $TempFrontEndIPName -ErrorAction SilentlyContinue

                if ($TempFrontEndIP) {
                Write-Output "Remove temp FrontEndIP"
                    $outnull = $ALBIn | Remove-AzureRmLoadBalancerFrontendIpConfig -Name $TempFrontEndIPName
                    $outnull = $ALBIn | Set-AzureRmLoadBalancer
                    }


                
                #Create a new ALB Rule per Port set on ALBPort, if required
                for ($ii=0; $ii -lt $iAppPort.Length; $ii++) {
                
                    #Temporary Condition to accomodate EMPTY Tag on ALBPort
                    #if ($iAppPort[$ii]) {
                    if ($iAppPort[$ii] -ine "empty") {
                                                
                    
                        #Assign #for each Rule and FrontEnd IP to add to the existing ALB
				        $LBRuleName = $AVSetName + "ar" + $iAppPort[$ii]
                        $ALBIn = Get-AzureRmLoadBalancer -Name $ALBInName -ResourceGroupName $resourceGroupName
                        $RuleExist = Get-AzureRmLoadBalancerRuleConfig -Name $LBRuleName -LoadBalancer $ALBIn -ErrorAction SilentlyContinue
                        if (!$RuleExist){
                            Write-Output "Create new ALB Rule for Port: "
                            $iAppPort[$ii]

                            $FrontEnd = Get-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -LoadBalancer $ALBIn
                            $backendPool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -Name $BackEndPoolName -LoadBalancer $ALBIn
                            $probe = Get-AzureRmLoadBalancerProbeConfig -Name $ProbeName -LoadBalancer $ALBIn

                        

				                                        
                            $outnull = $ALBIn | Add-AzureRmLoadBalancerRuleConfig -Name $LBRuleName -FrontendIpConfiguration $FrontEnd -BackendAddressPool $backendPool -Probe $probe -Protocol $Protocol[$ii] -FrontendPort $iAppPort[$ii] -BackendPort $iAppPort[$ii] -IdleTimeoutInMinutes 15 -EnableFloatingIP -LoadDistribution SourceIP
				            $outnull = $ALBIn | Set-AzureRmLoadBalancer
                            
                            $ALBIn = Get-AzureRmLoadBalancer -Name $ALBInName -ResourceGroupName $resourceGroupName
				            $iAppInIP = (Get-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -LoadBalancer $ALBIn).PrivateIpAddress
				            Write-Output "IP to use on iApp Internal"
				            $iAppInIP

                            #Define iApp Deployment Name
                            $iAppName = $AVSetName + "iw" + $iAppPort[$ii] + "in"
                             if ($iAppPort[$ii]) { DeployiAppService -iAppName $iAppName -iAppIP $iAppInIP -iAppPort $iAppPort[$ii] -iAppPoolIP $iAppPoolIP }
                            
                        }
                    }
                }

        }

    #======================= EXTERNAL ALB ===================================
			#Verify if ALBEx already Exists
			$ALBExName = $resourceGroupName + "le"
			$ALBEx = Get-AzureRmLoadBalancer -Name $ALBExName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
            Write-Output "ALB NAME: $ALBExName"

				#Objects that don't change name
				$VnetName = $resourceGroupName + "vn"
				$subnetName = $resourceGroupName + "sn"
                
				$BackEndPoolName = $ALBExName + "be"
				$ProbeName = $ALBExName + "hp"
        
			if ($ALBEx) {
                #Update ALB In to add new Rule
			    Write-Output "ALB External exists: $ALBExName"
                
                
			    #Add new FrontEndIP
	            $FrontEndName = $AVSetName + "fe"
                Write-Output "FRONT END NAME"
                $FrontEndName

                $FrontEnd = Get-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -LoadBalancer $ALBEx -ErrorAction SilentlyContinue
                if (!$FrontEnd){
                    $PublicIPName = $FrontEndName + "vx"
                    $PublicIP = New-AzureRmPublicIpAddress -Name $PublicIPName -ResourceGroupName $resourceGroupName -Location $Location -DomainNameLabel $PublicIPName -AllocationMethod Static -Force
                    $outnull = $ALBEx | Add-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -PublicIpAddress $PublicIP
                    $outnull = $ALBEx | Set-AzureRmLoadBalancer
                }

                #Create a new ALB Rule per Port set on ALBPort
                for ($ii=0; $ii -lt $iAppPort.Length; $ii++) {
                
                    #Temporary Condition to accomodate EMPTY Tag on ALBPort
                    #if ($iAppPort[$ii]) {
                    if ($iAppPort[$ii] -ine "empty") {
                                        
                        #Assign #for each Rule and FrontEnd IP to add to the existing ALB
				        $LBRuleName = $AVSetName + "ar" + $iAppPort[$ii]
                       

                        $ALBEx = Get-AzureRmLoadBalancer -Name $ALBExName -ResourceGroupName $resourceGroupName
                        $RuleExist = Get-AzureRmLoadBalancerRuleConfig -Name $LBRuleName -LoadBalancer $ALBEx -ErrorAction SilentlyContinue
                        if (!$RuleExist){
                            Write-Output "Create new ALB External Rule for Port: "
                            $iAppPort[$ii]

                            $FrontEnd = Get-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -LoadBalancer $ALBEx
                            $backendPool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -Name $BackEndPoolName -LoadBalancer $ALBEx
                            $probe = Get-AzureRmLoadBalancerProbeConfig -Name $ProbeName -LoadBalancer $ALBEx

                        
                            

				            $outnull = $ALBEx | Add-AzureRmLoadBalancerRuleConfig -Name $LBRuleName -FrontendIpConfiguration $FrontEnd -BackendAddressPool $backendPool -Probe $probe -Protocol $Protocol[$ii] -FrontendPort $iAppPort[$ii] -BackendPort $iAppPort[$ii] -IdleTimeoutInMinutes 15 -EnableFloatingIP -LoadDistribution SourceIP
				            $outnull = $ALBEx | Set-AzureRmLoadBalancer


                            #IP to use on iApp deployment
				            $ALBEx = Get-AzureRmLoadBalancer -Name $ALBExName -ResourceGroupName $resourceGroupName
				            $iAppExIP = (Get-AzureRmPublicIpAddress -Name $PublicIPName -ResourceGroupName $resourceGroupName).IpAddress
				            Write-Output "IP to use on iApp External"
				            $iAppExIP

                            #Define iApp Deployment Name
                            $iAppName = $AVSetName + "iw" + $iAppPort[$ii] + "ex"
                            if ($iAppPort[$ii]) { DeployiAppService -iAppName $iAppName -iAppIP $iAppExIP -iAppPort $iAppPort[$ii] -iAppPoolIP $iAppPoolIP}

                        }
                    
                    }
                }
		    }


    #}
   }
  
  }