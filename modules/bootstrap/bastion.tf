
locals {
  rg_name                  = "rg-boot-bastion"
  vnet_name                = "rg-boot-vnet"
  vnet1-address-space      = ["10.1.0.0/16"]
  vnet1-subnet1-address    = ["10.1.0.0/24"]
  azbastion-subnet-address = ["10.1.1.0/26"]
  vault_name               = "vault-boot-bastion"
}


resource "azurerm_resource_group" "rg-bastion" {
  location = "uksouth"
  name     = local.rg_name
}

# azurerm_resource_group.rg-bastion.name

resource "azurerm_virtual_network" "tf-vnetwork-01" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-bastion.name
  address_space       = local.vnet1-address-space
}

resource "azurerm_subnet" "vnet1-subnet1" {
  name                 = "vnet1-subnet1"
  resource_group_name  = azurerm_resource_group.rg-bastion.name
  virtual_network_name = azurerm_virtual_network.tf-vnetwork-01.name
  address_prefixes     = local.vnet1-subnet1-address
}

resource "azurerm_subnet" "AzureBastionSubnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.rg-bastion.name
  virtual_network_name = azurerm_virtual_network.tf-vnetwork-01.name
  address_prefixes     = local.azbastion-subnet-address
}

# Create PublicIP for Azure Bastion
resource "azurerm_public_ip" "azb-publicIP" {
  name                = "azb-publicIP"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-bastion.name
  allocation_method   = "Static"
  sku                 = "Standard"

}

# Create Azure Bastion Host
resource "azurerm_bastion_host" "azb-host" {
  name                = "azb-host"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-bastion.name
  scale_units         = 2

  ip_configuration {
    name                 = "azb-Ip-configuration"
    subnet_id            = azurerm_subnet.AzureBastionSubnet.id
    public_ip_address_id = azurerm_public_ip.azb-publicIP.id
  }
}


resource "azurerm_network_interface" "linuxVM-PrivIP-nic" {
  location            = var.location
  name                = "linuxVM-PrivIP-nic"
  resource_group_name = azurerm_resource_group.rg-bastion.name
  ip_configuration {
    name                          = "linuxVM-PrivIP-nic-ipConfig"
    subnet_id                     = azurerm_subnet.vnet1-subnet1.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Key Vault

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "azkv-name" {
  name                        = local.vault_name
  location                    = var.location
  resource_group_name         = azurerm_resource_group.rg-bastion.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  sku_name                    = "standard"
  enable_rbac_authorization   = true

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }
}

resource "random_password" "rndm-pswd" {
  length           = 18
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 4
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_role_assignment" "sc" {
  scope                = azurerm_key_vault.azkv-name.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "boot" {
  scope                = azurerm_key_vault.azkv-name.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = "Update"
}

resource "azurerm_key_vault_secret" "linuxVM-pswd" {
  name         = "VM-Password"
  value        = random_password.rndm-pswd.result
  key_vault_id = azurerm_key_vault.azkv-name.id
  depends_on = [
    azurerm_role_assignment.sc
  ]
}




resource "azurerm_network_security_group" "azb-nsg" {
  name                = "azb-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-bastion.name

  # * * * * * * IN-BOUND Traffic * * * * * * #

  security_rule {
    # Ingress traffic from Internet on 443 is enabled
    name                       = "AllowIB_HTTPS443_Internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
  security_rule {
    # Ingress traffic for control plane activity that is GatewayManager to be able to talk to Azure Bastion
    name                       = "AllowIB_TCP443_GatewayManager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    # Ingress traffic for health probes, enabled AzureLB to detect connectivity
    name                       = "AllowIB_TCP443_AzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
  security_rule {
    # Ingress traffic for data plane activity that is VirtualNetwork service tag
    name                       = "AllowIB_BastionHost_Commn8080"
    priority                   = 130
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    # Deny all other Ingress traffic 
    name                       = "DenyIB_any_other_traffic"
    priority                   = 900
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # * * * * * * OUT-BOUND Traffic * * * * * * #

  # Egress traffic to the target VM subnets over ports 3389 and 22
  security_rule {
    name                       = "AllowOB_SSHRDP_VirtualNetwork"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["3389", "22"]
    source_address_prefix      = "*"
    destination_address_prefix = "VirtualNetwork"
  }
  # Egress traffic to AzureCloud over 443
  security_rule {
    name                       = "AllowOB_AzureCloud"
    priority                   = 105
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }
  # Egress traffic for data plane communication between the Bastion and VNets service tags
  security_rule {
    name                       = "AllowOB_BastionHost_Comn"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["8080", "5701"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  # Egress traffic for SessionInformation
  security_rule {
    name                       = "AllowOB_GetSessionInformation"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# Associate the NSG to the AZBastionHost Subnet
resource "azurerm_subnet_network_security_group_association" "azbsubnet-and-nsg-association" {
  network_security_group_id = azurerm_network_security_group.azb-nsg.id
  subnet_id                 = azurerm_subnet.AzureBastionSubnet.id
}

# * * * * * * *  NSG / Security rule for LinuxVM to allow only SSH/RDP traffic from the Azure Bastion * * * * * * *
resource "azurerm_network_security_group" "VMs-nsg" {
  name                = "VMs-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg-bastion.name

  security_rule {
    name                       = "AllowIB_SSHRDP_fromBastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "22", "3389"]
    source_address_prefix      = "10.1.1.0/26"
    destination_address_prefix = "*"
  }
}

# Associate the NSG to the LinuxVM's NIC
resource "azurerm_network_interface_security_group_association" "linuxVM-nic-and-nsg-association" {
  network_interface_id      = azurerm_network_interface.linuxVM-PrivIP-nic.id
  network_security_group_id = azurerm_network_security_group.VMs-nsg.id
}
