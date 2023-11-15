<#

Generates a testing CNI config for the supported plugin types while detecting
or outright assuming as many default settings as possible/reasonable.

USAGE: generateTestCniConf.ps1 `
    -Type nat/sdnbridge/sdnoverlay `
    -OutDir 'C:\Program Files\containerd\cni\conf' `
    -CniVersion [0.3.0]/1.0.0 `
    -HostInterfaceNamePatternPatter "*Ethernet*" `
    -EnsureOutDirEmpty $false `
    -TestSubnet "10.4.1.0/24" `
    -TestGateway "10.4.1.2" `
    -TestDnsServer "1.1.1.1"

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('nat', 'sdnbridge', 'sdnoverlay')]
    [System.String] $Type,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.IO.DirectoryInfo] $OutDir = $(New-Object IO.DirectoryInfo("C:\Program Files\containerd\cni\conf")),

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.Boolean] $EnsureOutDirEmpty = $false,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet('0.3.0', '1.0.0')]
    [System.String] $CniVersion = "0.3.0",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $TestSubnet = "10.4.1.0/24",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $TestGateway = "10.4.1.2",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $TestDnsServer = "1.1.1.1",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $HostInterfaceNamePattern = "*Ethernet*"
)

$NATPluginType = "nat"
$SDNBridgePluginType = "sdnbridge"
$SDNOverlayPluginType = "sdnoverlay"

$TestDnsServerPlaceholder = "__ARG_TEST_DNS_SERVER__"
$TestSubnetAddrPlaceholder = "__ARG_TEST_SUBNET_ADDR__"
$TestSubnetGatewayPlaceholder = "__ARG_TEST_SUBNET_GATEWAY__"

$HostSubnetPlaceholder = "__ARG_HOST_SUBNET__"

$CniConfNetNamePlaceholder = "__ARG_CNI_NET_NAME__"
$CniConfNetTypePlaceholder = "__ARG_CNI_NET_TYPE__"
$CniConfVersionPlaceholder = "__ARG_CNI_VERSION__"
$MasterInterfacePlaceholder = "__ARG_MASTER_IF__"

$NATConfTemplate = @"
{
    "type": "$CniConfNetTypePlaceholder",
    "cniVersion": "$CniConfVersionPlaceholder",
    "name": "$CniConfNetNamePlaceholder",
    "master": "$MasterInterfacePlaceholder",
    "capabilities": {
        "portMappings": true,
        "dns": true
    },
    "ipam": {
        "subnet": "$TestSubnetAddrPlaceholder",
        "routes": [
            {
                "GW": "$TestSubnetGatewayPlaceholder"
            }
        ]
    }
}
"@

$SDNBridgeConfTemplate = @"
{
    "type": "$CniConfNetTypePlaceholder",
    "cniVersion": "$CniConfVersionPlaceholder",
    "name": "$CniConfNetNamePlaceholder",
    "master": "$MasterInterfacePlaceholder",
    "capabilities": {
        "portMappings":  true,
        "dns":  true
    },
    "ipam": {
        "subnet": "$TestSubnetAddrPlaceholder",
        "routes": [
            {
                "GW": "$TestSubnetGatewayPlaceholder"
            }
        ]
    },
    "dns": {
        "Nameservers":  [
            "$TestDnsServerPlaceholder"
        ]
    },
    "AdditionalArgs": [
        {
            "name": "EndpointPolicy",
            "value": {
                "Type": "OutBoundNAT",
                "Settings": {
                    "Exceptions": [
                        "$HostSubnetPlaceholder"
                    ]
                }
            }
        },
        {
            "name": "EndpointPolicy",
            "value": {
                "Type": "SDNRoute",
                "Settings": {
                    "DestinationPrefix": "$HostSubnetPlaceholder",
                    "NeedEncap": true
                }
            }
        }
    ],
    "optionalFlags":  {
        "forceBridgeGateway": true,
        "allowAclPortMapping": true,
        "localRoutedPortMapping": true
    }
}
"@

$SDNOverlayConfTemplate = @"
{
    "cniVersion": "$CniConfVersionPlaceholder",
    "name": "$CniConfNetNamePlaceholder",
    "type": "$CniConfNetTypePlaceholder",
    "capabilities": {
        "portMappings": true,
        "dns": true
    },
    "AdditionalArgs": [
        {
            "name": "EndpointPolicy",
            "value": {
                "Type": "OutBoundNAT",
                "Settings": {
                    "Exceptions": [
                        "$HostSubnetPlaceholder",
                        "$TestSubnetAddrPlaceholder"
                    ]
                }
            }
        },
        {
            "name": "EndpointPolicy",
            "value": {
                "Type": "SDNRoute",
                "Settings": {
                    "DestinationPrefix": "$HostSubnetPlaceholder",
                    "NeedEncap": true
                }
            }
        }
    ]
}
"@
# AdditionalArgs: [{
#     "name": "EndpointPolicy",
#     "value": {
#         "Type": "ProviderAddress",
#         "Settings": {
#             "ProviderAddress": "10.1.0.5"
#         }
#     }
# }]

$PluginConfTemplateMap = @{
    $NATPluginType = $NATConfTemplate;
    $SDNBridgePluginType = $SDNBridgeConfTemplate;
    $SDNOverlayPluginType = $SDNOverlayConfTemplate
}

$PluginTypeToBinaryMap = @{
    $NATPluginType = "nat";
    $SDNBridgePluginType = "L2Bridge";
    $SDNOverlayPluginType = "Overlay"
}

function Get-HostNetwork {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [System.String] $HostInterfaceNamePattern = "*Ethernet*"
    )

    $ifInfo = (Get-NetIPAddress -InterfaceAlias "$HostInterfaceNamePattern" -AddressFamily IPv4)[0]
    if ($ifInfo -eq $null) {
        throw "Unable to find network interafce with IPv4 address with alias patter '$HostInterfaceNamePattern': $(Get-NetIPaddress)"
    }
    # return "$($ifInfo.IPAddress)/$($ifInfo.PrefixLength)"
    return $ifInfo
}

function Render-Config {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('nat', 'sdnbridge', 'sdnoverlay')]
        [System.String] $Type,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String] $NetName
    )

    $confTemplate = $PluginConfTemplateMap[$Type]
    if ($confTemplate -eq $null) {
        throw "Unsupported plugin type '$Type'. Supported types are: $($PluginConfTemplateMap.Keys)"
    }

    # $confCniType = $PluginTypeToBinaryMap[$Type]
    # if ($confCniType -eq $null) {
    #     throw "Unsupported plugin binary type '$Type'. Supported types are: $($PluginTypeToBinaryMap.Keys)"
    # }

    $hostIf = Get-HostNetwork -HostInterfaceNamePattern "$HostInterfaceNamePattern"
    $hostSubnet = "$($hostIf.IPAddress)/$($hostIf.PrefixLength)"
    return $confTemplate.
        Replace($CniConfNetNamePlaceholder, "$netName").
        Replace($CniConfNetTypePlaceholder, "$Type").
        Replace($CniConfVersionPlaceholder, "$CniVersion").
        Replace($MasterInterfacePlaceholder, $hostIf.InterfaceAlias).
        Replace($TestSubnetAddrPlaceholder, "$TestSubnet").
        Replace($TestSubnetGatewayPlaceholder, "$TestGateway").
        Replace($TestDnsServerPlaceholder, "$TestDnsServer").
        Replace($HostSubnetPlaceholder, "$hostSubnet")
}

if (Test-Path -Path "$OutDir") {
    if (-not (Test-Path -Path "$OutDir" -PathType Container)) {
        throw "Provided OutDir path exists but is NOT a directory: '$OutDir'"
    }

    if (-not ((Get-ChildItem "$OutDir") -eq $null)) {
        if ($EnsureOutDirEmpty) {
            throw "Provided OutDir path is an existing non-empty directory: '$OutDir"
        }
    }
} else {
    New-Item -ItemType Directory "$OutDir"
}

$netName = "testnet-$Type"
$ConfOutFile = "$OutDir\0-containerd-${netName}.conf"
$conf = Render-Config -Type "$Type" -NetName "$netName"
$conf | Out-File -FilePath "$ConfOutFile" -Encoding ASCII
Write-Output "Successfully saved testing CNI config of type '$Type' at: '$ConfOutFile'"
