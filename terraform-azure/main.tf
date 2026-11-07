
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-2dv705"
  location = "austriaeast"
}


# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# Public subnet for the web server
resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Private subnet for the database
resource "azurerm_subnet" "db" {
  name                 = "snet-db"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}


# Security group for web server
resource "azurerm_network_security_group" "web_nsg" {
  name                = "nsg-web-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name


  security_rule {
    name                       = "Allow-SSH-Admin"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Security group for database

resource "azurerm_network_security_group" "db_nsg" {
  name                = "nsg-db-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow MySQL only from web ASG
  security_rule {
    name                                  = "Allow-MySQL-Web"
    priority                              = 100
    direction                             = "Inbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "3306"
    source_application_security_group_ids = [azurerm_application_security_group.web_asg.id]
    destination_address_prefix            = "*"
  }

  # Deny MySQL from all other sources
  security_rule {
    name                       = "Deny-MySQL-Others"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Attach security groups to subnets
resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}


resource "azurerm_application_security_group" "web_asg" {
  name                = "asg-web-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}


# Public IP for the web server
resource "azurerm_public_ip" "web_ip" {
  name                = "pip-web-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network interface for the web server
resource "azurerm_network_interface" "web_nic" {
  name                = "nic-web-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "web-ipconfig"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web_ip.id
  }
}

# Add the web server network interface to the ASG
resource "azurerm_network_interface_application_security_group_association" "web_asg_assoc" {
  network_interface_id          = azurerm_network_interface.web_nic.id
  application_security_group_id = azurerm_application_security_group.web_asg.id
}


# Private network interface for database VM
resource "azurerm_network_interface" "db_nic" {
  name                = "nic-db-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "db-ipconfig"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Dynamic"
  }
}


# Public IP used by the NAT Gateway
resource "azurerm_public_ip" "nat_ip" {
  name                = "pip-nat-2dv705"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# NAT Gateway for outbound internet access
resource "azurerm_nat_gateway" "nat" {
  name                    = "nat-2dv705"
  location                = azurerm_resource_group.rg.location
  resource_group_name     = azurerm_resource_group.rg.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

# Connect public IP to NAT Gateway
resource "azurerm_nat_gateway_public_ip_association" "nat_ip" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat_ip.id
}

# Connect NAT Gateway to private database subnet
resource "azurerm_subnet_nat_gateway_association" "db_nat" {
  subnet_id      = azurerm_subnet.db.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}


# Web server
resource "azurerm_linux_virtual_machine" "web" {
  name                = "vm-web-2dv705"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2als_v2"

  admin_username                  = "azureuser"
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.web_nic.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand("~/.ssh/2dv705_azure.pub"))
  }

  identity {
    type = "SystemAssigned"
  }



  custom_data = base64encode(templatefile(
    "${path.module}/cloud-config-web.yaml.tftpl",
    {
      bootstrap_b64   = filebase64("${path.module}/web-bootstrap.sh")
      vault_name      = azurerm_key_vault.app.name
      db_host         = azurerm_network_interface.db_nic.private_ip_address
      storage_account = azurerm_storage_account.images.name
    }
  ))


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Database server
resource "azurerm_linux_virtual_machine" "db" {
  name                = "vm-db-2dv705"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2als_v2"

  admin_username                  = "azureuser"
  disable_password_authentication = true

  network_interface_ids = [
    azurerm_network_interface.db_nic.id
  ]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand("~/.ssh/2dv705_azure.pub"))
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile(
    "${path.module}/cloud-config-db.yaml.tftpl",
    {
      vault_name    = azurerm_key_vault.app.name
      bootstrap_b64 = filebase64("${path.module}/db-bootstrap.sh")
    }
  ))

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  depends_on = [
    azurerm_subnet_nat_gateway_association.db_nat
  ]
}
