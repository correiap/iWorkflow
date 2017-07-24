##############################################################
# Build-F5-Mgmt-NATRules.ps1
#
#	This script will creates External and Internal ALBs
#	along with: Health Probes, BackEndPool, and Inbound NAT Rules
#	to access the Management Interface of the F5s
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

    [Parameter(Mandatory=$True)]
    [string]
    $resourceGroupName,

    [Parameter(Mandatory=$True)]
    [string]
    $Location


)


    #Connect to Azure, right now it is only interactive login
    #Log into Azure
    Write-Output "Logging into Azure using SPN and Certificate"
    #Establish Automation Account identity.
    $connection = Get-AutomationConnection -Name AzureRunAsConnection
    Add-AzureRMAccount -ServicePrincipal -Tenant $connection.TenantID -ApplicationID $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
    $azSub = (Select-AzureRmSubscription -SubscriptionName $Subscription)

Write-Output "ALB NAT RULE CONFIG"



function CreateALBs ($ALBType) {
      #Assign Objects name if External ALB
          if ($ALBType -eq "External") {
          
          $ALBName = $Environment + $Retailer + $Country + "le"
          $BackEndPoolName = $ALBName + "be"
		  $ProbeName = $ALBName + "hp"
          $FrontEndNamebase = $ALBName + "fe" + "mgmt"

      #Assign Objects name if Internal ALB  
        } elseif ($ALBType -eq "Internal") {
        
          $ALBName = $Environment + $Retailer + $Country + "li"
          $BackEndPoolName = $ALBName + "be"
		  $ProbeName = $ALBName + "hp"
          $FrontEndNamebase = $ALBName + "temp"
 
        }

          $ALBExist = Get-AzureRmLoadBalancer -Name $ALBName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue
          #Create ALB if it doesn't exist
          #If External ALB also create Inbound NAT Rules to access F5 Management - Rule to NAT 443 into 8443
          if (!$ALBExist) {   
          
                
                $FrontEndName = $FrontEndNamebase +  "1"
                $InboundNATName = $ALBName + "in" + "mgmt" + "1"

                
                if ($ALBType -eq "External") {
                $PublicIPName = $ALBName + "vx" + "mgmt" + "1"
                $PublicIP = New-AzureRmPublicIpAddress -Name $PublicIPName -ResourceGroupName $resourceGroupName -Location $Location -DomainNameLabel $PublicIPName -AllocationMethod Dynamic -Force
                $FrontEndIPConfig = New-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -PublicIpAddress $PublicIP
               

                } elseif ($ALBType -eq "Internal") {
                
                $VnetName = $resourceGroupName + "vt"
                $subnetName = $resourceGroupName.Substring(0,$resourceGroupName.Length-1) + "lbf" + $Country
                #$subnetName = $resourceGroupName + "lbe"
                
                $VmNet = Get-AzureRmVirtualNetwork -Name $VnetName -ResourceGroupName $resourceGroupName
				$Subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VmNet -Name $subnetName
                
                $FrontEndIPConfig = New-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -Subnet $Subnet
                
                }

                $backendAddressPool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name $BackEndPoolName
                if ($ALBType -eq "External") {
                    $inboundNATRule = New-AzureRmLoadBalancerInboundNatRuleConfig -Name $InboundNATName -FrontendIpConfiguration $FrontEndIPConfig -Protocol TCP -FrontendPort 443 -BackendPort 443
                }

                $probe = New-AzureRmLoadBalancerProbeConfig -Name $ProbeName -Protocol tcp -Port 22 -IntervalInSeconds 15 -ProbeCount 2

                if ($ALBType -eq "External") {
                    $ALB = New-AzureRmLoadBalancer -Name $ALBName -ResourceGroupName $resourceGroupName -Location $Location -FrontendIpConfiguration $FrontEndIPConfig -BackendAddressPool $backendAddressPool -InboundNatRule $inboundNATRule -Probe $probe
                } elseif ($ALBType -eq "Internal") {
                    $ALB = New-AzureRmLoadBalancer -Name $ALBName -ResourceGroupName $resourceGroupName -Location $Location -FrontendIpConfiguration $FrontEndIPConfig -BackendAddressPool $backendAddressPool -Probe $probe
                }

                $setALB = $ALB | Set-AzureRmLoadBalancer

                
				    $nicName = $Environment + $Retailer + $Country + "lbnc" + "1"
                   
                    $nic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName
                    
                    $ALB = Get-AzureRmLoadBalancer -Name $ALBName -ResourceGroupName $resourceGroupName
                    $backendPool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -Name $BackEndPoolName -LoadBalancer $ALB
                                                       
                    if ($ALBType -eq "External") {
                        $nic.IpConfigurations[0].LoadBalancerInboundNatRules.Add($ALB.InboundNatRules[0])
                        $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
                    }
                    
                    $nic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName
                    if ($ALBType -eq "External") {
                        $nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $backendPool
                    }
                    if ($ALBType -eq "Internal") {
                       $nic.IpConfigurations[0].LoadBalancerBackendAddressPools += $backendPool                         
                    }
                    
                    
				    $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
                
    
          } 
          
          for ($i=2; $i -le $numberOfInstances; $i++)
          {
                
                
                $j = $i - 1
                
                $FrontEndName = $FrontEndNamebase + $i
                $InboundNATName = $ALBName + "in" + "mgmt" + $i
                


                if ($ALBType -eq "External") {
                $PublicIPName = $ALBName + "vx" + "mgmt" + $i
                $PublicIP = New-AzureRmPublicIpAddress -Name $PublicIPName -ResourceGroupName $resourceGroupName -Location $Location -DomainNameLabel $PublicIPName -AllocationMethod Dynamic -Force
                $setALB = $ALB | Add-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -PublicIpAddress $PublicIP

                $setALB = $ALB | Set-AzureRmLoadBalancer
               

                } elseif ($ALBType -eq "Internal") {
                
                $VnetName = $resourceGroupName + "vt"
                $subnetName = $resourceGroupName.Substring(0,$resourceGroupName.Length-1) + "lbf" + $Country
                #$subnetName = $resourceGroupName + "lbe"

                $VmNet = Get-AzureRmVirtualNetwork -Name $VnetName -ResourceGroupName $resourceGroupName
				$Subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $VmNet -Name $subnetName
                
                               
                }

                if ($ALBType -eq "External") {
                    $FrontEndIPConfig = Get-AzureRmLoadBalancerFrontendIpConfig -Name $FrontEndName -LoadBalancer $ALB
                    $setALB = $ALB | Add-AzureRmLoadBalancerInboundNatRuleConfig -Name $InboundNATName -FrontendIpConfiguration $FrontEndIPConfig -Protocol TCP -FrontendPort 443 -BackendPort 443
                }
                
                $setALB = $ALB | Set-AzureRmLoadBalancer

                
                    $nicName = $Environment + $Retailer + $Country + "lbnc" + $i
                    $nic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName
                    $ALB = Get-AzureRmLoadBalancer -Name $ALBName -ResourceGroupName $resourceGroupName
                                    
                $backendPool = Get-AzureRmLoadBalancerBackendAddressPoolConfig -Name $BackEndPoolName -LoadBalancer $ALB
                
                if ($ALBType -eq "External") {
                    $nic.IpConfigurations[0].LoadBalancerInboundNatRules.Add($ALB.InboundNatRules[$j])
                    $setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
                }

                $nic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $resourceGroupName
                
                if ($ALBType -eq "External") {
                        $nic.IpConfigurations[0].LoadBalancerBackendAddressPools = $backendPool
                    }
                if ($ALBType -eq "Internal") {
                        $nic.IpConfigurations[0].LoadBalancerBackendAddressPools += $backendPool                         
                    }
                 
				$setnic = Set-AzureRmNetworkInterface -NetworkInterface $nic
                

          }

}

        #Call Function to create External and Internal ALB
          CreateALBs -ALBType "External"
          CreateALBs -ALBType "Internal"