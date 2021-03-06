function New-EswApplicationGatewayConfig
{
<#

.SYNOPSIS
Adds a probe, listener(s), httpSetting and rule(s) to an existing applcation gateway.

.DESCRIPTION
Adds a probe, listener(s), httpSetting and rule(s) to an existing applcation gateway.
In the case of multi-region a second listener and rule is setup for traffic manager.

.PARAMETER AppGatewayName
The name of the Azure application gateway you wish to configure.

.PARAMETER ResourceGroupName
The Azure resource group name that the application gateway is in.

.PARAMETER Name
The name of the probe/listener/httpSetting/rule you wish to create. The convention is that they will all have the same name.
In the case of multi-region a secondary listener and rule will be setup with '-tm' trailing both.

.PARAMETER Port
The port you want to create the rule for, for SSL this should be 443.

.PARAMETER DnsName
The dns name of the application.

.PARAMETER DnsSuffix
The dns suffix of both the application configured through the load balancer and the certificate configured on the appliation gateway.

.PARAMETER ProbePath
The path of the probe you wish to create. The default is '/Probe'.

.PARAMETER IsMultiRegion
In the case of multi-region a second listner and rule is set up for traffic manager.

.PARAMETER Force
Force the re-configuration of both the probe and the rule.

.EXAMPLE
New-EswLoadBalancerConfig -LoadBalancerName 'test-lb' -ResourceGroupName 'test-rg' -Name 'test' -Port 999
Will create a 'test' probe and rule for port '999' on the 'test-lb' load balancer in the 'test-rg' resource group.

.FUNCTIONALITY
Configures rules on application gateways.
   
#>
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory=$true, Position=0)]
        [string] $AppGatewayName,

        [parameter(Mandatory=$true, Position=1)]
        [string] $ResourceGroupName,

        [parameter(Mandatory=$true, Position=2)]
        [string] $Name,

        [parameter(Mandatory=$true, Position=3)]
        [string] $Port,

        [parameter(Mandatory=$true, Position=4)]
        [string] $DnsName,

        [parameter(Mandatory=$true, Position=5)]
        [string] $DnsSuffix,

        [string] $ProbePath = "/Probe",
        
        [switch] $IsMultiRegion,

        [switch] $Force
    )

    $agRefresh = Get-AzureRmApplicationGateway -Name $AppGatewayName -ResourceGroupName $ResourceGroupName

    if(($agRefresh.FrontendPorts | ? { $_.Port -eq 443 }).Count -eq 0) {
        $agRefresh | Add-AzureRmApplicationGatewayFrontendPort -Name 'https-port' -Port 443 | Set-AzureRmApplicationGateway > $null
        $agRefresh = Get-AzureRmApplicationGateway -Name $AppGatewayName -ResourceGroupName $ResourceGroupName
    }

    $agProbe = $null
    $agListener = $null
    $agTmListener = $null
    $agHttpSetting = $null
    $agTmRule = $null
    $agRule = $null

    try { $agProbe = ($agRefresh.Probes | ? { $_.Name -eq $Name })[0] } catch {}
    try { $agTmlistener = ($agRefresh.HttpListeners | ? { $_.Name -eq "$Name-tm" })[0] } catch {}
    try { $agListener = ($agRefresh.HttpListeners | ? { $_.Name -eq $Name })[0] } catch {}
    try { $agHttpSetting = ($agRefresh.BackendHttpSettingsCollection | ? { $_.Name -eq $Name })[0] } catch {}
    try { $agTmRule = ($agRefresh.RequestRoutingRules | ? { $_.Name -eq "$Name-tm" })[0] } catch {}
    try { $agRule = ($agRefresh.RequestRoutingRules | ? { $_.Name -eq $Name })[0] } catch {}

    if($agProbe -or $agListener -or $agTmListener -or $agHttpSetting -or $agTmRule -or $agRule -and $Force.IsPresent) {
        $agRefresh | Remove-AzureRmApplicationGatewayRequestRoutingRule -Name $agRule.Name `
                    | Remove-AzureRmApplicationGatewayRequestRoutingRule -Name $agTmRule.Name `
                    | Remove-AzureRmApplicationGatewayBackendHttpSettings -Name $agHttpSetting.Name `
                    | Remove-AzureRmApplicationGatewayHttpListener -Name $agTmListener.Name `
                    | Remove-AzureRmApplicationGatewayHttpListener -Name $agListener.Name `
                    | Remove-AzureRmApplicationGatewayProbeConfig -Name $agProbe.Name `
                    | Set-AzureRmApplicationGateway > $null
        
        $agProbe = $null
        $agListener = $null
        $agTmListener = $null
        $agHttpSetting = $null
        $agTmRule = $null
        $agRule = $null

        $agRefresh = $null
        $agRefresh = Get-AzureRmApplicationGateway -Name $ag.Name -ResourceGroupName $ag.ResourceGroupName
    }

    if($agProbe -eq $null) {
        $agRefresh | Add-AzureRmApplicationGatewayProbeConfig -Name "$Name" `
                                                        -Protocol Http `
                                                        -HostName "$DnsName.$DnsSuffix" `
                                                        -Path "$ProbePath" `
                                                        -Interval 30 `
                                                        -Timeout 120 `
                                                        -UnhealthyThreshold 2 > $null
    }

    if($IsMultiRegion.IsPresent -and $agTmListener -eq $null) {
        $agRefresh | Add-AzureRmApplicationGatewayHttpListener -Name "$Name-tm" `
                                                                    -Protocol "Https" `
                                                                    -SslCertificate ($agRefresh.SslCertificates | ? { $_.Name -eq "star.$DnsSuffix" })[0] `
                                                                    -FrontendIPConfiguration ($agRefresh.FrontendIPConfigurations)[0] `
                                                                    -FrontendPort ($agRefresh.FrontendPorts | ? { $_.Port -eq 443 })[0] `
                                                                    -HostName "$Name.$DnsSuffix" > $null
    }

    if($agListener -eq $null) {
        $agRefresh | Add-AzureRmApplicationGatewayHttpListener -Name "$Name" `
                                                                -Protocol "Https" `
                                                                -SslCertificate ($agRefresh.SslCertificates | ? { $_.Name -eq "star.$DnsSuffix" })[0] `
                                                                -FrontendIPConfiguration ($agRefresh.FrontendIPConfigurations)[0] `
                                                                -FrontendPort ($agRefresh.FrontendPorts | ? { $_.Port -eq 443 })[0] `
                                                                -HostName "$DnsName.$DnsSuffix" > $null
    }

    if($agHttpSetting -eq $null) {
        $agRefresh | Add-AzureRmApplicationGatewayBackendHttpSettings -Name "$Name" `
                                                                        -Port $Port `
                                                                        -Protocol "HTTP" `
                                                                        -Probe ($agRefresh.Probes | ? { $_.Name -eq $Name})[0] `
                                                                        -CookieBasedAffinity "Disabled" > $null
    }

    if($IsMultiRegion.IsPresent -and $agTmRule -eq $null) {
        $agRefresh | Add-AzureRmApplicationGatewayRequestRoutingRule -Name "$Name-tm" `
                                                                            -RuleType Basic `
                                                                            -BackendHttpSettings ($agRefresh.BackendHttpSettingsCollection | ? { $_.Name -eq $Name })[0] `
                                                                            -HttpListener ($agRefresh.HttpListeners | ? { $_.Name -eq "$Name-tm" })[0] `
                                                                            -BackendAddressPool ($agRefresh.BackendAddressPools)[0] > $null
    } 

    if($agRule -eq $null) {
        $agRefresh | Add-AzureRmApplicationGatewayRequestRoutingRule -Name "$Name" `
                                                                        -RuleType Basic `
                                                                        -BackendHttpSettings ($agRefresh.BackendHttpSettingsCollection | ? { $_.Name -eq $Name })[0] `
                                                                        -HttpListener ($agRefresh.HttpListeners | ? { $_.Name -eq "$Name" })[0] `
                                                                        -BackendAddressPool ($agRefresh.BackendAddressPools)[0] > $null
    }

    $agRefresh | Set-AzureRmApplicationGateway > $null    
}