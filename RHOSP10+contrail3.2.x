
Deploying Juniper Contrail & Red Hat OpenStack Platform 10 with Composable Roles


Contrail 3.2.x deployment is supported using the RedHat OpenStack Director 10 (OSPd 10). OSPd10 introduced Composable services and roles. A service is an additional component and a role is a group of services. Prior to OSPd10 the services and roles were fixed to the standard OpenStack services.
Contrail adds the following roles and services:

ContrailController
- ContrailConfig
- ContrailControl
- ContrailDatabase
- ContrailWebUI

ContrailAnalytics
- ContrailAnalytics

ContrailAnalyticsDatabase
- ContrailAnalyticsDatabase

Controller*
- ContrailHeat
*existing role

Each Contrail role requires a separate Operating System instance, which can be a Baremetal Server or a Virtual Machine. Furthermore, for high availability a minimum of three instances per Contrail role are required. This means for non-HA setups 3 and for HA setups 9 additional Operating System instances are required.
In case the setup uses VMs for the instances and HA is required, the 9 instances must be distributed across 3 physical hosts in the following way:
Host1:
- VM1:
-- ContrailController1
- VM2:
-- ContrailAnalytics1
- VM3:
-- ContrailAnalyticsDatabase1
Host2:
- VM4:
-- ContrailController2
- VM5:
-- ContrailAnalytics2
- VM6:
-- ContrailAnalyticsDatabase2
Host3:
- VM7:
-- ContrailController3
- VM8:
-- ContrailAnalytics3
- VM9:
-- ContrailAnalyticsDatabase3

Contrail can be deployed using a single network (single NIC) for all traffic or separate networks for different types of traffic (multi NIC).
Single NIC

single nic image
In the single NIC all traffic uses the control_plane network
Multi NIC

multi nic image

For production deployments it is recommended to isolate traffic using multiple networks. All networks besides the control_plane network can be configured as VLANs on a single or multiple network interface cards. Bonding is supported.
Contrail can be configured to use the internal_api or the storage_mgmt network for transporting Contrail control/data traffic. However, both, Contrail control AND data traffic must use the same network (either internal_api or storage_mgmt).
Deployment Configuration

The installation of Director is not described here and should be done using the Director documentation

After applying the overcloud configuration for the OpenStack services and before actually deploying the overcloud, Contrail overcloud configuration must be performed.
Contrail packages

In order to enable Contrail deployment using OSPd10 the Contrail packages must be downloaded and added to a repository which is reachable through the ctrl_plane network or the rpms must be added to a satellite.
The package contrail-tripleo-heat-templates must be installed on the Director itself, all other packages will be installed on the the overcloud nodes.
The deployment of Contrail overcloud nodes requires some packages to be available on the overcloud images before the registration to a RH satellite or CDN is performed. These packages are:

contrail-tripleo-puppet (must be present on all overcloud nodes, including OpenStack controllers)
puppet-contrail (must be present on all overcloud nodes, including OpenStack controllers)
contrail-vrouter-utils (must be present on overcloud compute nodes)
contrail-vrouter (must be present on overcloud compute nodes)

These packages are available via the Juniper support website in the Red Hat packages tarball. You will need to log in with your Juniper account to access them:
https://cdn.juniper.net/software/contrail/3.2.3/contrail-install-packages-3.2.3.0-38~redhat73newton.tgz

There are two methods for installing the packages to the overcloud nodes:

    Automated using a local repository through ctrl_plane network
    In this method a local repository is created on a host which is reachable through the ctrl_plane network. This method is enabled by setting the ContrailRepo parameter in the contrail-services.yaml environment file, e.g.:
    ~~~
    parameter_defaults:
    ContrailRepo: http://192.0.2.1/contrail
    ~~~
    Customizing the overcloud image
    In case a repository on the ctrl_plane network cannot be used the packages can be installed on the overcloud images before deployment using virt-customize. As a minimum these packages are required:

All:
puppet-contrail
contrail-tripleo-puppet (after installation the content of /usr/share/contrail-tripleo-puppet/ has to be copied to /usr/share/openstack-puppet/modules/tripleo/)

Compute:
contrail-vrouter
contrail-vrouter-utils
Contrail nodes profiling

In order to achieve a correct distribution of Contrail roles across the nodes it is recommended to profile the nodes.
As a first step the profiling information must be added to the ironic nodes:

ironic node-update replace properties/capabilities=profile:contrail-controller,boot_option:local

This command tags a certain ironic node to be used for the contrail-controller role. This has to be done for all Contrail roles.

Next step is to create a profile per role, e.g:
Raw

for i in contrail-controller contrail-analytics contrail-analytics-database; do
  openstack flavor create $i --ram 4096 --vcpus 1 --disk 40
  openstack flavor set --property "capabilities:boot_option"="local" --property "capabilities:profile"="${i}" ${i}
done

This command creates a flavor per Contrail role using the profile. In the last step the flavor must be set for each role in a heat environment file, such as contrail-services.yaml, e.g.:
Raw

parameter_defaults:
  OvercloudControlFlavor: control
  OvercloudContrailControllerFlavor: contrail-controller
  OvercloudContrailAnalyticsFlavor: contrail-analytics
  OvercloudContrailAnalyticsDatabaseFlavor: contrail-analytics-database
  OvercloudComputeFlavor: compute

Contrail overcloud configuration

The Contrail overcloud is configured by setting a set of different parameters in heat environment files. The Contrail heat templates and example environment files are located in /usr/share/contrail-tripleo-heat-templates directory and must be copied to the tripleo heat templates directory (cp /usr/share/contrail-tripleo-heat-templates/* ~/templates/).
The environments/contrail folder contains examples covering different environments and use-cases.
Overcloud network configuration

The overcloud network configuration is the most complex part and requires careful planning. As described above, Contrail can be deployed using a single NIC (with or without VLAN and bonding), multiple NICs (with or without VLAN and bonding), Contrail traffic on internal_api or storage_mgmt network, dynamically or statically assigned IP addresses.
The network configuration is defined in two separate files:

    contrail-net-*.yaml
    This file contains the general network information such as subnet information for the various networks, DNS server, vrouter interface/gateway/netmask and it associates NIC templates with the different roles

    contrail-nic-*.yaml
    These files define the NIC layout for the different roles by associating NICs with networks and VLANs. A typical NIC configuration for the vrouters vhost0 interface:

Raw

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          Network_config:
            -
              type: interface
              name: nic2
              use_dhcp: false
            -
              type: interface
              name: vhost0
              use_dhcp: false
              addresses:
                -
                  ip_netmask: {get_param: InternalApiIpSubnet}
              routes:
                -
                  default: true
                  next_hop: {get_param: InternalApiDefaultRoute}

There are two interfaces: nic2 and vhost0. Nic2 is the 2nd interface in the system to which vhost0 is bound to. nic2 doesn’t contain any network configuration, whereas vhost0 has the internal_api network and the default route configured.

Examples:
1. Single NIC
internal_api and ctrl_plane networks are collapsed.

a. Network configuration
Raw

#cat  environments/contrail/contrail-net-single.yaml
resource_registry:
  OS::TripleO::Compute::Net::SoftwareConfig: contrail-nic-config-compute-single.yaml
  OS::TripleO::Controller::Net::SoftwareConfig: contrail-nic-config-single.yaml
  OS::TripleO::ContrailController::Net::SoftwareConfig: contrail-nic-config-single.yaml
  OS::TripleO::ContrailAnalytics::Net::SoftwareConfig: contrail-nic-config-single.yaml
  OS::TripleO::ContrailAnalyticsDatabase::Net::SoftwareConfig: contrail-nic-config-single.yaml
  OS::TripleO::ContrailTsn::Net::SoftwareConfig: contrail-nic-config-compute-single.yaml

parameter_defaults:
  ControlPlaneSubnetCidr: '24' #subnet size of ctrl_plane network
  ControlPlaneDefaultRoute: 192.0.2.254 #default gw of ctrl_plane network
  EC2MetadataIp: 192.0.2.1  # Generally the IP of the Undercloud
  DnsServers: ["8.8.8.8","8.8.4.4"]
  VrouterPhysicalInterface: eth0 #ph. Interface used by vrouter
  VrouterGateway: 192.0.2.1 #default gw for vrouter
  VrouterNetmask: 255.255.255.0 #subnet mask used for vrouter network
  ControlVirtualInterface: eth0 #crtl_plane network
  PublicVirtualInterface: vlan10 #vlan id for public network

Control plane node NIC configuration
Raw

#cat  environments/contrail/contrail-nic-config-single.yaml
heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: nic1
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
                -
                  default: true
                  next_hop: {get_param: ControlPlaneDefaultRoute}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

c. Compute NIC configuration
Raw

#cat  environments/contrail/contrail-nic-config-compute-single.yaml

heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: vhost0
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
                -
                  default: true
                  next_hop: {get_param: ControlPlaneDefaultRoute}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

    Multi NIC
    Multiple networks are used for the different types of traffics. Contrail uses the internal_api network.

a. Network configuration
Raw

#cat environments/contrail/contrail-nic.yaml

resource_registry:
  OS::TripleO::Compute::Net::SoftwareConfig: contrail-nic-config-compute.yaml
  OS::TripleO::ContrailDpdk::Net::SoftwareConfig: contrail-nic-config-compute.yaml
  OS::TripleO::Controller::Net::SoftwareConfig: contrail-nic-config.yaml
  OS::TripleO::ContrailController::Net::SoftwareConfig: contrail-nic-config.yaml
  OS::TripleO::ContrailAnalytics::Net::SoftwareConfig: contrail-nic-config.yaml
  OS::TripleO::ContrailAnalyticsDatabase::Net::SoftwareConfig: contrail-nic-config.yaml
  OS::TripleO::ContrailTsn::Net::SoftwareConfig: contrail-nic-config-compute.yaml

parameter_defaults:
  ControlPlaneSubnetCidr: '24'
  ControlPlaneDefaultRoute: 192.0.2.254
  InternalApiNetCidr: 10.0.0.0/24
  InternalApiAllocationPools: [{'start': '10.0.0.10', 'end': '10.0.0.200'}]
  InternalApiDefaultRoute: 10.0.0.1
  ManagementNetCidr: 10.1.0.0/24
  ManagementAllocationPools: [{'start': '10.1.0.10', 'end': '10.1.0.200'}]
  ManagementInterfaceDefaultRoute: 10.1.0.1
  ExternalNetCidr: 10.2.0.0/24
  ExternalAllocationPools: [{'start': '10.2.0.10', 'end': '10.2.0.200'}]
  EC2MetadataIp: 192.0.2.1  # Generally the IP of the Undercloud
  DnsServers: ["10.87.64.101"]
  VrouterPhysicalInterface: eth1
  VrouterGateway: 10.0.0.1
  VrouterNetmask: 255.255.255.0
  ControlVirtualInterface: eth0
  PublicVirtualInterface: vlan10
# VlanParentInterface: eth1 # If VrouterPhysicalInterface is a vlan interface using vlanX notation

b. Control plane node NIC configuration
Raw

#cat  environments/contrail/contrail-nic.yaml
heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: nic1
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
            -
              type: interface
              name: nic2
              use_dhcp: false
              addresses:
                -
                  ip_netmask: {get_param: InternalApiIpSubnet}
              routes:
                -
                  default: true
                  next_hop: {get_param: InternalApiDefaultRoute}
            -
              type: linux_bridge
              name: br0
              use_dhcp: false
              members:
                -
                  type: interface
                  name: nic3
                  # force the MAC address of the bridge to this interface
                  #                   primary: true              
                  #                   
            -
              type: vlan
              vlan_id: {get_param: ManagementNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ManagementIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: ExternalNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ExternalIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageMgmtNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageMgmtIpSubnet}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

c. Compute NIC configuration
Raw

#cat  environments/contrail/contrail-nic-config-compute.yaml

heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: nic1
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
            -
              type: interface
              name: nic2
              use_dhcp: false
            -
              type: interface
              name: vhost0
              use_dhcp: false
              addresses:
                -
                  ip_netmask: {get_param: InternalApiIpSubnet}
              routes:
                -
                  default: true
                  next_hop: {get_param: InternalApiDefaultRoute}
            -
              type: linux_bridge
              name: br0
              use_dhcp: false
              members:
                -
                  type: interface
                  name: nic3
                  # force the MAC address of the bridge to this interface
                  #                   primary: true              
                  #                   
            -
              type: vlan
              vlan_id: {get_param: ManagementNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ManagementIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: ExternalNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ExternalIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageMgmtNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageMgmtIpSubnet}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

    Multi NIC with storage_mgmt for Contrail traffic
    Multiple networks are used and Contrail traffic uses storage_mgmt network. The storage network must be enabled for the contrail services:

Raw

#cat environments/contrail/contrail-services-storage-mgmt.yaml
# A Heat environment file which can be used to enable OpenContrail
# # extensions, configured via puppet
resource_registry:
  OS::TripleO::Services::NeutronDhcpAgent: OS::Heat::None
  OS::TripleO::Services::NeutronL3Agent: OS::Heat::None
  OS::TripleO::Services::NeutronMetadataAgent: OS::Heat::None
  OS::TripleO::Services::NeutronOvsAgent: OS::Heat::None
  OS::TripleO::Services::ComputeNeutronOvsAgent: OS::Heat::None
  OS::TripleO::NodeUserData: install_vrouter_kmod.yaml
  OS::TripleO::Services::ContrailHeat: ../../puppet/services/network/contrail-heat.yaml
  OS::TripleO::Services::ContrailAnalytics: ../../puppet/services/network/contrail-analytics.yaml
  OS::TripleO::Services::ContrailAnalyticsDatabase: ../../puppet/services/network/contrail-analytics-database.yaml
  OS::TripleO::Services::ContrailConfig: ../../puppet/services/network/contrail-config.yaml
  OS::TripleO::Services::ContrailControl: ../../puppet/services/network/contrail-control.yaml
  OS::TripleO::Services::ContrailDatabase: ../../puppet/services/network/contrail-database.yaml
  OS::TripleO::Services::ContrailWebUI: ../../puppet/services/network/contrail-webui.yaml
  OS::TripleO::Services::ContrailTsn: ../../puppet/services/network/contrail-tsn.yaml
  OS::TripleO::Services::ContrailDpdk: ../../puppet/services/network/contrail-dpdk.yaml
  OS::TripleO::Services::ComputeNeutronCorePlugin: ../../puppet/services/network/contrail-vrouter.yaml
  OS::TripleO::Services::NeutronCorePlugin: ../../puppet/services/network/contrail-neutron-plugin.yaml
parameter_defaults:
  ServiceNetMap:
    ContrailAnalyticsNetwork: storage_mgmt
    ContrailAnalyticsDatabaseNetwork: storage_mgmt
    ContrailConfigNetwork: storage_mgmt
    ContrailControlNetwork: storage_mgmt
    ContrailDatabaseNetwork: storage_mgmt
    ContrailWebuiNetwork: storage_mgmt
    ContrailTsnNetwork: storage_mgmt
    ContrailVrouterNetwork: storage_mgmt
    ContrailDpdkNetwork: storage_mgmt
#   KeystoneAdminApiNetwork: internal_api
  ContrailControlManageNamed: true
  ContrailRepo: http://192.0.2.1/contrail
  EnablePackageInstall: true
  ContrailConfigIfmapUserName: api-server
  ContrailConfigIfmapUserPassword: api-server
  OvercloudControlFlavor: control
  OvercloudContrailControllerFlavor: contrail-controller
  OvercloudContrailAnalyticsFlavor: contrail-analytics
  OvercloudContrailAnalyticsDatabaseFlavor: contrail-analytics-database
  OvercloudContrailTsnFlavor: contrail-tsn
  OvercloudComputeFlavor: compute
  OvercloudContrailDpdkFlavor: compute-dpdk
  ControllerCount: 3
  ContrailControllerCount: 3
  ContrailAnalyticsCount: 3
  ContrailAnalyticsDatabaseCount: 3
  ContrailTsnCount: 0
  ComputeCount: 2
  ContrailDpdkCount: 0
  DnsServers: ["10.87.64.101"]
  NtpServer: 10.0.0.1
  NeutronCorePlugin: neutron_plugin_contrail.plugins.opencontrail.contrail_plugin.NeutronPluginContrailCoreV2
  NeutronServicePlugins: 'neutron_plugin_contrail.plugins.opencontrail.loadbalancer.v2.plugin.LoadBalancerPluginV2'
  NeutronTunnelTypes: ''
  NeutronMetadataProxySharedSecret: secret
  ContrailControlRNDCSecret: sHE1SM8nsySdgsoRxwARtA==
  NovaComputeExtraConfig:
    # Required for Centos 7.3 and Qemu 2.6.0
    nova::compute::libvirt::libvirt_cpu_mode: 'none'

a. Network configuration

For using the storage_mgmt network the VIPs for the Contrail services must be defined:
Raw

#cat environments/contrail/contrail-net-storage-mgmt.yaml
resource_registry:
  OS::TripleO::Compute::Net::SoftwareConfig: contrail-nic-config-compute-storage-mgmt.yaml
  OS::TripleO::ContrailDpdk::Net::SoftwareConfig: contrail-nic-config-compute-storage-mgmt.yaml
  OS::TripleO::Controller::Net::SoftwareConfig: contrail-nic-config-storage-mgmt.yaml
  OS::TripleO::ContrailController::Net::SoftwareConfig: contrail-nic-config-storage-mgmt.yaml
  OS::TripleO::ContrailAnalytics::Net::SoftwareConfig: contrail-nic-config-storage-mgmt.yaml
  OS::TripleO::ContrailAnalyticsDatabase::Net::SoftwareConfig: contrail-nic-config-storage-mgmt.yaml
  OS::TripleO::ContrailTsn::Net::SoftwareConfig: contrail-nic-config-compute-storage-mgmt.yaml

parameter_defaults:
  ContrailConfigVIP: 10.0.0.10
  ContrailAnalyticsVIP: 10.0.0.10
  ContrailWebuiVIP: 10.0.0.10
  ContrailVIP: 10.0.0.10
  ControlPlaneSubnetCidr: '24'
  ControlPlaneDefaultRoute: 192.0.2.254
  InternalApiNetCidr: 10.3.0.0/24
  InternalApiAllocationPools: [{'start': '10.3.0.10', 'end': '10.3.0.200'}]
  InternalApiDefaultRoute: 10.3.0.1
  StorageMgmtNetCidr: 10.0.0.0/24
  StorageMgmtAllocationPools: [{'start': '10.0.0.10', 'end': '10.0.0.200'}]
  StorageMgmtDefaultRoute: 10.0.0.1
  StorageMgmtInterfaceDefaultRoute: 10.0.0.1
  StorageMgmtVirtualIP: 10.0.0.10
  ManagementNetCidr: 10.1.0.0/24
  ManagementAllocationPools: [{'start': '10.1.0.10', 'end': '10.1.0.200'}]
  ManagementInterfaceDefaultRoute: 10.1.0.1
  ExternalNetCidr: 10.2.0.0/24
  ExternalAllocationPools: [{'start': '10.2.0.10', 'end': '10.2.0.200'}]
  EC2MetadataIp: 192.0.2.1  # Generally the IP of the Undercloud
  DnsServers: ["10.87.64.101"]
  VrouterPhysicalInterface: eth1
  VrouterGateway: 10.0.0.1
  VrouterNetmask: 255.255.255.0
  ControlVirtualInterface: eth0
  PublicVirtualInterface: vlan10

Control plane node NIC configuration
Raw

#cat  environments/contrail/contrail-nic-config-storage-mgmt.yaml
heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  StorageMgmtInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: nic1
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
            -
              type: interface
              name: nic2
              use_dhcp: false
              addresses:
                -
                  ip_netmask: {get_param: StorageMgmtIpSubnet}
              routes:
                -
                  default: true
                  next_hop: {get_param: StorageMgmtInterfaceDefaultRoute}
            -
              type: linux_bridge
              name: br0
              use_dhcp: false
              members:
                -
                  type: interface
                  name: nic3
                  # force the MAC address of the bridge to this interface
                  #                   primary: true              
                  #                   
            -
              type: vlan
              vlan_id: {get_param: ManagementNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ManagementIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: ExternalNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ExternalIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: InternalApiNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: InternalApiIpSubnet}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

Compute NIC configuration
Raw

#cat  environments/contrail/contrail-nic-config-compute-storage-mgmt.yaml

heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  StorageMgmtInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: nic1
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
            -
              type: interface
              name: nic2
              use_dhcp: false
            -
              type: interface
              name: vhost0
              use_dhcp: false
              addresses:
                -
                  ip_netmask: {get_param: StorageMgmtIpSubnet}
              routes:
                -
                  default: true
                  next_hop: {get_param: StorageMgmtInterfaceDefaultRoute}
            -
              type: linux_bridge
              name: br0
              use_dhcp: false
              members:
                -
                  type: interface
                  name: nic3
                  # force the MAC address of the bridge to this interface
                  #                   primary: true              
                  #                   
            -
              type: vlan
              vlan_id: {get_param: ManagementNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ManagementIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: ExternalNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ExternalIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: InternalApiNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: InternalApiIpSubnet}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

Multi NIC with Bond/VLAN
Network configuration
Raw

#cat environments/contrail/contrail-net-bond-vlan.yaml

resource_registry:
  OS::TripleO::Compute::Net::SoftwareConfig: contrail-nic-config-compute-bond-vlan.yaml
  OS::TripleO::Controller::Net::SoftwareConfig: contrail-nic-config-vlan.yaml
  OS::TripleO::ContrailController::Net::SoftwareConfig: contrail-nic-config-vlan.yaml
  OS::TripleO::ContrailAnalytics::Net::SoftwareConfig: contrail-nic-config-vlan.yaml
  OS::TripleO::ContrailAnalyticsDatabase::Net::SoftwareConfig: contrail-nic-config-vlan.yaml
  OS::TripleO::ContrailTsn::Net::SoftwareConfig: contrail-nic-config-compute.yaml
  OS::TripleO::ContrailDpdk::Net::SoftwareConfig: contrail-nic-config-compute-bond-vlan-dpdk.yaml

parameter_defaults:
  ControlPlaneSubnetCidr: '24'
  ControlPlaneDefaultRoute: 192.0.2.254
  InternalApiNetCidr: 10.0.0.0/24
  InternalApiAllocationPools: [{'start': '10.0.0.10', 'end': '10.0.0.200'}]
  InternalApiDefaultRoute: 10.0.0.1
  ManagementNetCidr: 10.1.0.0/24
  ManagementAllocationPools: [{'start': '10.1.0.10', 'end': '10.1.0.200'}]
  ManagementInterfaceDefaultRoute: 10.1.0.1
  ExternalNetCidr: 10.2.0.0/24
  ExternalAllocationPools: [{'start': '10.2.0.10', 'end': '10.2.0.200'}]
  EC2MetadataIp: 192.0.2.1  # Generally the IP of the Undercloud
  DnsServers: ["8.8.8.8","8.8.4.4"]
  VrouterPhysicalInterface: vlan100
  VrouterGateway: 10.0.0.1
  VrouterNetmask: 255.255.255.0
  ControlVirtualInterface: eth0
  PublicVirtualInterface: vlan10
  VlanParentInterface: bond0
  BondInterface: bond0
  BondInterfaceMembers: 'eth1,eth2'
  InternalApiNetworkVlanID: 100

Compute NIC configuration
Raw

#cat  environments/contrail/contrail-nic-config-compute-bond-vlan.yaml

heat_template_version: 2015-04-30

description: >
  Software Config to drive os-net-config to configure multiple interfaces
  for the compute role.

parameters:
  ControlPlaneIp:
    default: ''
    description: IP address/subnet on the ctlplane network
    type: string
  ExternalIpSubnet:
    default: ''
    description: IP address/subnet on the external network
    type: string
  InternalApiIpSubnet:
    default: ''
    description: IP address/subnet on the internal API network
    type: string
  InternalApiDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the internal api network.
    type: string
  StorageIpSubnet:
    default: ''
    description: IP address/subnet on the storage network
    type: string
  StorageMgmtIpSubnet:
    default: ''
    description: IP address/subnet on the storage mgmt network
    type: string
  TenantIpSubnet:
    default: ''
    description: IP address/subnet on the tenant network
    type: string
  ManagementIpSubnet: # Only populated when including environments/network-management.yaml
    default: ''
    description: IP address/subnet on the management network
    type: string
  ExternalNetworkVlanID:
    default: 10
    description: Vlan ID for the external network traffic.
    type: number
  InternalApiNetworkVlanID:
    default: 20
    description: Vlan ID for the internal_api network traffic.
    type: number
  StorageNetworkVlanID:
    default: 30
    description: Vlan ID for the storage network traffic.
    type: number
  StorageMgmtNetworkVlanID:
    default: 40
    description: Vlan ID for the storage mgmt network traffic.
    type: number
  TenantNetworkVlanID:
    default: 50
    description: Vlan ID for the tenant network traffic.
    type: number
  ManagementNetworkVlanID:
    default: 60
    description: Vlan ID for the management network traffic.
    type: number
  ControlPlaneSubnetCidr: # Override this via parameter_defaults
    default: '24'
    description: The subnet CIDR of the control plane network.
    type: string
  ControlPlaneDefaultRoute: # Override this via parameter_defaults
    description: The default route of the control plane network.
    type: string
  ExternalInterfaceDefaultRoute: # Not used by default in this template
    default: '10.0.0.1'
    description: The default route of the external network.
    type: string
  ManagementInterfaceDefaultRoute: # Commented out by default in this template
    default: unset
    description: The default route of the management network.
    type: string
  DnsServers: # Override this via parameter_defaults
    default: []
    description: A list of DNS servers (2 max for some implementations) that will be added to resolv.conf.
    type: comma_delimited_list
  EC2MetadataIp: # Override this via parameter_defaults
    description: The IP address of the EC2 metadata server.
    type: string

resources:
  OsNetConfigImpl:
    type: OS::Heat::StructuredConfig
    properties:
      group: os-apply-config
      config:
        os_net_config:
          network_config:
            -
              type: interface
              name: nic1
              use_dhcp: false
              dns_servers: {get_param: DnsServers}
              addresses:
                -
                  ip_netmask:
                    list_join:
                      - '/'
                      - - {get_param: ControlPlaneIp}
                        - {get_param: ControlPlaneSubnetCidr}
              routes:
                -
                  ip_netmask: 169.254.169.254/32
                  next_hop: {get_param: EC2MetadataIp}
            -
              type: linux_bond
              name: bond0
              use_dhcp: false
              bonding_options: "mode=active-backup"
              members:
              -
                type: interface
                name: eth1
              -
                type: interface
                name: eth2
            -
              type: vlan
              vlan_id: {get_param: InternalApiNetworkVlanID}
              device: bond0
            -
              type: interface
              name: vhost0
              use_dhcp: false
              addresses:
                -
                  ip_netmask: {get_param: InternalApiIpSubnet}
              routes:
                -
                  default: true
                  next_hop: {get_param: InternalApiDefaultRoute}
            -
              type: linux_bridge
              name: br0
              use_dhcp: false
              members:
                -
                  type: interface
                  name: nic4
                  # force the MAC address of the bridge to this interface
                  #                   primary: true              
                  #                   
            -
              type: vlan
              vlan_id: {get_param: ManagementNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ManagementIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: ExternalNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: ExternalIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageIpSubnet}
            -
              type: vlan
              vlan_id: {get_param: StorageMgmtNetworkVlanID}
              device: br0
              addresses:
                -
                  ip_netmask: {get_param: StorageMgmtIpSubnet}

outputs:
  OS::stack_id:
    description: The OsNetConfigImpl resource.
    value: {get_resource: OsNetConfigImpl}

Overcloud service configuration
The Contrail services are configured by setting parameters in ~/templates/environments/contrail/contrail-services.yaml
Raw

# A Heat environment file which can be used to enable OpenContrail
# # extensions, configured via puppet
resource_registry:
  OS::TripleO::Services::NeutronDhcpAgent: OS::Heat::None
  OS::TripleO::Services::NeutronL3Agent: OS::Heat::None
  OS::TripleO::Services::NeutronMetadataAgent: OS::Heat::None
  OS::TripleO::Services::NeutronOvsAgent: OS::Heat::None
  OS::TripleO::Services::ComputeNeutronOvsAgent: OS::Heat::None
  OS::TripleO::NodeUserData: install_vrouter_kmod.yaml
  OS::TripleO::Services::ContrailHeat: ../../puppet/services/network/contrail-heat.yaml
  OS::TripleO::Services::ContrailAnalytics: ../../puppet/services/network/contrail-analytics.yaml
  OS::TripleO::Services::ContrailAnalyticsDatabase: ../../puppet/services/network/contrail-analytics-database.yaml
  OS::TripleO::Services::ContrailConfig: ../../puppet/services/network/contrail-config.yaml
  OS::TripleO::Services::ContrailControl: ../../puppet/services/network/contrail-control.yaml
  OS::TripleO::Services::ContrailDatabase: ../../puppet/services/network/contrail-database.yaml
  OS::TripleO::Services::ContrailWebUI: ../../puppet/services/network/contrail-webui.yaml
  OS::TripleO::Services::ContrailTsn: ../../puppet/services/network/contrail-tsn.yaml
  OS::TripleO::Services::ContrailDpdk: ../../puppet/services/network/contrail-dpdk.yaml
  OS::TripleO::Services::ComputeNeutronCorePlugin: ../../puppet/services/network/contrail-vrouter.yaml
  OS::TripleO::Services::NeutronCorePlugin: ../../puppet/services/network/contrail-neutron-plugin.yaml
parameter_defaults:
  ServiceNetMap: # can be internal_api or storage_mgmt. 
    ContrailAnalyticsNetwork: internal_api
    ContrailAnalyticsDatabaseNetwork: internal_api
    ContrailConfigNetwork: internal_api
    ContrailControlNetwork: internal_api
    ContrailDatabaseNetwork: internal_api
    ContrailWebuiNetwork: internal_api
    ContrailTsnNetwork: internal_api
    ContrailVrouterNetwork: internal_api
    ContrailDpdkNetwork: internal_api
#   KeystoneAdminApiNetwork: internal_api
  #VrouterControlNodeIps: 10.0.0.40,10.0.0.41
  ContrailControlManageNamed: true
  ContrailRepo: http://192.0.2.1/contrail
  EnablePackageInstall: true
  ContrailConfigIfmapUserName: api-server
  ContrailConfigIfmapUserPassword: api-server
  OvercloudControlFlavor: control
  OvercloudContrailControllerFlavor: contrail-controller
  OvercloudContrailAnalyticsFlavor: contrail-analytics
  OvercloudContrailAnalyticsDatabaseFlavor: contrail-analytics-database
  OvercloudContrailTsnFlavor: contrail-tsn
  OvercloudComputeFlavor: compute
  OvercloudContrailDpdkFlavor: compute-dpdk
  ControllerCount: 3
  ContrailControllerCount: 3
  ContrailAnalyticsCount: 0
  ContrailAnalyticsDatabaseCount: 0
  ContrailTsnCount: 0
  ComputeCount: 2
  ContrailDpdkCount: 0
  DnsServers: ["10.87.64.101"]
  NtpServer: 10.0.0.1
  NeutronCorePlugin: neutron_plugin_contrail.plugins.opencontrail.contrail_plugin.NeutronPluginContrailCoreV2
  NeutronServicePlugins: 'neutron_plugin_contrail.plugins.opencontrail.loadbalancer.v2.plugin.LoadBalancerPluginV2'
  NeutronTunnelTypes: ''
  NeutronMetadataProxySharedSecret: secret
  ContrailControlRNDCSecret: sHE1SM8nsySdgsoRxwARtA==
  NovaComputeExtraConfig:
    # Required for Centos 7.3 and Qemu 2.6.0
    nova::compute::libvirt::libvirt_cpu_mode: 'none'

In case storage_mgmt is used for the Contrail services the Contrail*VIP parameters have to be define. See environments/contrail/contrail-net-storage-mgmt.yaml
Contrail overcloud deployment
In the deployment examples below the custom templates are marked in red.
Single NIC
Raw

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --roles-file tripleo-heat-templates/environments/contrail/roles_data.yaml \
  -e tripleo-heat-templates/environments/puppet-pacemaker.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e tripleo-heat-templates/environments/contrail/network-isolation.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net.yaml \
  -e tripleo-heat-templates/environments/contrail/ips-from-pool-all.yaml \
  -e tripleo-heat-templates/environments/network-management.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml

Multi NIC with storage_mgmt
Raw

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --roles-file tripleo-heat-templates/environments/contrail/roles_data.yaml \
  -e tripleo-heat-templates/environments/puppet-pacemaker.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services-storage-mgmt.yaml \
  -e tripleo-heat-templates/environments/contrail/network-isolation.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net-storage-mgmt.yaml \
  -e tripleo-heat-templates/environments/contrail/ips-from-pool-all-storage-mgmt.yaml \
  -e tripleo-heat-templates/environments/network-management.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml \

Multi NIC with bond/vlan
Raw

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --roles-file tripleo-heat-templates/environments/contrail/roles_data.yaml \
  -e tripleo-heat-templates/environments/puppet-pacemaker.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e tripleo-heat-templates/environments/contrail/network-isolation.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net-bond-vlan.yaml \
  -e tripleo-heat-templates/environments/contrail/ips-from-pool-all.yaml \
  -e tripleo-heat-templates/environments/network-management.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml 

Multi NIC with bond/vlan and custom hostname
Raw

openstack overcloud deploy --templates tripleo-heat-templates/ \
  --roles-file tripleo-heat-templates/environments/contrail/roles_data.yaml \
  -e tripleo-heat-templates/environments/puppet-pacemaker.yaml \
  -e tripleo-heat-templates/environments/contrail/hostname-map.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-role-map.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-services.yaml \
  -e tripleo-heat-templates/environments/contrail/network-isolation.yaml \
  -e tripleo-heat-templates/environments/contrail/contrail-net-bond-vlan.yaml \
  -e tripleo-heat-templates/environments/contrail/ips-from-pool-all.yaml \
  -e tripleo-heat-templates/environments/network-management.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/environment-rhel-registration.yaml \
  -e tripleo-heat-templates/extraconfig/pre_deploy/rhel-registration/rhel-registration-resource-registry.yaml

