###########################################################################################################
# Author - Conner Henry
# Date 5/8/2016
# Purpose - DSC script - apply config to all mgt host server following SCVMM vhd push
# 1. configure the required service
# 2. ensure all required features are enabled
# 3. Set Basic Server Settings
# 4. Enable Firewall and rules
# 5. Configure the iSCSi Interfaces
# 6. Configure iSCSi initator for Tegile 
# 7. Configure MPIO
# 8. (Check Server GUI is Off) pending testing
#
# Help Site - 
# Notes - Saved to Git
##########################################################################################################

# Start ConfigData

function GetComputers {
    import-module ActiveDirectory
    Get-ADComputer -SearchBase "OU=Lab Servers,OU=LAB NETWORK,DC=mgt,DC=lan" -Filter *
}
$computers = GetComputers
 
#Pull list of computers and GUIDs into hash table
$ConfigData = @{
    AllNodes = @(
        foreach ($node in $computers) {
            @{NodeName = $node.Name; NodeGUID = $node.objectGUID;}
            
        }
    )
}

# Check computer that are in the table
#$computers
#$ConfigData.AllNodes


# Start Configuration File
Configuration MgtHostConfig {

#param (
#        [Parameter()][string]$UserName,
#        [PSCredential]$Password
        
#      )

#region DSC Resources 
    # Import DSC Resource required  
    Import-DscResource –ModuleName PSDesiredStateConfiguration
    Import-DscResource –ModuleName xPSDesiredStateConfiguration
    Import-DscResource -ModuleName xSMBShare
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xComputerManagement
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName xSystemSecurity
    Import-DscResource -ModuleName xRemoteDesktopAdmin
    Import-DscResource -ModuleName xWinEventLog
    Import-DSCResource -ModuleName xTimeZone
    Import-DscResource -modulename cISCSI
    Import-DscResource -Module SYSTEMHOSTING
    Import-DscResource -ModuleName xStorage
    Import-DSCResource -ModuleName xDSCFirewall -ModuleVersion 1.0
    
   
    #Install-Module -Name xNetworking
  

#endregion  DSC Resource

Node $AllNodes.NodeGuid {
    
#region Windows Services    
        Service WindowsFirewall {
            Name = "MPSSvc"
            StartupType = "Automatic"
            State = "Running"
            }
        
        Service iSCSiService {
            Name = 'MSiSCSI'
            StartupType = 'Automatic'
            State = 'Running'
            }  
#endregion

#region Windows Server Features  

        WindowsFeature StorageServices   {
            Ensure = "Present"
            Name = "Storage-Services"
        }

        WindowsFeature FailoverClustering   {
            Ensure = "Present"
            Name = "Failover-Clustering"
        }
        
        WindowsFeature WindowsMPIO {
            Ensure = "Present"
            Name = "Multipath-IO"
       }
        
#endregion Windws Features

#region Windows Server Settings   
        
        xIEESC SetAdminIEESC {
            UserRole = "Administrators"
            IsEnabled = $False           
        }     

        xTimeZone ServerTime {
            TimeZone = "Atlantic Standard Time"
        }

        xRemoteDesktopAdmin RemoteDesktopSettings {
            Ensure = 'Present'
            UserAuthentication = 'secure'
        }

        # Get-MPIOSetting
        # All changes to MPIO settings require a reboot before taking effect.
        cMPIOSetting mpioSetting {
            EnforceDefaults = $true
            PathVerificationState = 'Disabled'
            PathVerificationPeriod = 30
            PDORemovePeriod = 20
            RetryCount = 3
            RetryInterval = 1
            UseCustomPathRecovery = 'Disabled'
            CustomPathRecovery = 40
            DiskTimeoutValue = 60
        }   # MPIO
   
 
#endregion

#region Windows Firewall Settings

        xFirewall FirewallClusertUpdate { 
            Name                  = "Inbound Rule for Remote Shutdown (RPC-EP-In)" 
            DisplayName           = "Inbound Rule for Remote Shutdown (RPC-EP-In)" 
            Group                 = "Remote Shutdown"
            LocalAddress          = "%systemroot%\system32\wininit.exe"  
            Ensure                = "Present" 
            Action                = "Allow" 
            Enabled                 = $true 
            Profile               = "Domain" 
        }
        
        xDSCFirewall EnablePublic {
            Ensure = "Present"
            Zone = "Public"
            Dependson = "[Service]WindowsFirewall"
        }
        
        xDSCFirewall EnabledDomain {
            Ensure = "Present"
            Zone = "Domain"
            Dependson = "[Service]WindowsFirewall"
        }

        xDSCFirewall EnabledPrivate {
            Ensure = "Present"
            Zone = "Private"
            Dependson = "[Service]WindowsFirewall"
        } 
#endregion Windows Firewall Settings

} # End All Nodes

Node $AllNodes.where{$_.NodeName -eq “BS-MGT-HVH2”}.NodeGuid {
        
        # Get the iSCSi Net Adapters and ensure they are enabled
        cNetAdapter EnableiSCSiNIC1 {
            InterfaceAlias = 'iSCSi-SANSW-1'
            Enabled        = $true
        }

        cNetAdapter EnableiSCSiNIC2 {
            InterfaceAlias = 'iSCSi-SANSW-2'
            Enabled        = $true
        }

        # Get the iSCSi Adapters by Mac and label them
        cNetAdapterName NameiSCSiNIC1 {
            MACAddress             = ' Need to get MACs '
            InterfaceAlias         = 'iSCSi-SANSW-1'
            
        }
        
        cNetAdapterName NameiSCSiNIC2 {
            MACAddress             = ' Need to get MACs '
            InterfaceAlias         = 'iSCSi-SANSW-2'
        }

        # Get the iSCSi Adapters by Alias and assign IPV4 Settings
        xIPAddress SetiSCSiNic1 {
            InterfaceAlias = 'iSCSi-SANSW-1'
            IPAddress = '10.10.10.11'
            AddressFamily = 'IPV4'
            Dependson = '[cNetAdapterName]NameiSCSiNIC1'
            SubnetMask = '255.255.255.0'
            }

        xIPAddress SetiSCSiNic2 {
            InterfaceAlias = 'iSCSi-SANSW-2'
            IPAddress = '10.10.10.12'
            AddressFamily = 'IPV4'
            Dependson = '[cNetAdapterName]NameiSCSiNIC2'
            SubnetMask = '255.255.255.0'
            }

        # Connect the issci initiator to the iscsi target and optionally regestier it with the iSNS Server
        ciSCSIInitiator iSCSIInitiator {
            Ensure = 'Present'
            nodeaddress = 'iqn.1991-05.com.microsoft:mgt-dsc1-filecluster-target'
            TargetPortalAddress = '172.21.2.50'  
            #InitiatorPortalAddress = ' IP Address'
            IsPersistent = $true
            #iSNSServer  = 'isns1.domainname.com'
            DependsOn = "[WaitforAny]iSCSiService"
         } # End iSCSITarget Resource
      
 
   
   
    } # End Log Node
   
    

} # End Config



# Start Building the MOF and copying the files

# Build the MOF Files
MgtHostConfig -ConfigurationData $ConfigData -OutputPath "$Env:Temp\Scripts\DSC Host Server Config"

# Create the checksums 
write-host "Creating checksums..."
New-DSCCheckSum -ConfigurationPath "$Env:Temp\Scripts\DSC Host Server Config" -OutPath "$Env:Temp\Scripts\DSC Host Server Config" -Verbose -Force
 
# Copy the files to the correct location on the Pull Server
write-host "Copying configurations to pull service configuration store..."
$SourceFiles = "$Env:Temp\Scripts\DSC Host Server Config\*.mof*"
$TargetFiles = "$env:SystemDrive\Program Files\WindowsPowershell\DscService\Configuration"
Move-Item $SourceFiles $TargetFiles -Force
Remove-Item "$Env:Temp\Scripts\DSC Host Server Config"
