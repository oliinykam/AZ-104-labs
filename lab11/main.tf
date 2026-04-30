terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.117"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  skip_provider_registration = false
}

resource "azurerm_resource_group" "rg11" {
  name     = "az104-rg11"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "az104-11-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet0"
  resource_group_name  = azurerm_resource_group.rg11.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "az104-vm0-nic"
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm0" {
  name                            = "az104-11-vm0"
  resource_group_name             = azurerm_resource_group.rg11.name
  location                        = azurerm_resource_group.rg11.location
  size                            = "Standard_DC1s_v3" 
  admin_username                  = "localadmin"
  admin_password                  = "Pa$$w0rd1234!"
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_monitor_action_group" "ag" {
  name                = "Alert the operations team"
  resource_group_name = azurerm_resource_group.rg11.name
  short_name          = "AlertOpsTeam"

  email_receiver {
    name          = "VM was deleted"
    email_address = "andrii.oliinyk.23@pnu.edu.ua" 
  }
}

resource "azurerm_monitor_activity_log_alert" "alert" {
  name                = "VM was deleted"
  resource_group_name = azurerm_resource_group.rg11.name
  location            = "Global"
  scopes              = [azurerm_resource_group.rg11.id]
  description         = "A VM in your resource group was deleted"

  criteria {
    category       = "Administrative"
    operation_name = "Microsoft.Compute/virtualMachines/delete"
  }

  action {
    action_group_id = azurerm_monitor_action_group.ag.id
  }
}

resource "azurerm_monitor_alert_processing_rule_suppression" "suppression" {
  name                = "Planned-Maintenance"
  resource_group_name = azurerm_resource_group.rg11.name
  scopes              = [azurerm_resource_group.rg11.id]
  description         = "Suppress notifications during planned maintenance."

  schedule {
    effective_from  = "2026-04-30T22:00:00"
    effective_until = "2026-05-01T07:00:00"
    time_zone       = "FLE Standard Time"
  }
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "az104-11-law-oliinykA-v1" 
  location            = azurerm_resource_group.rg11.location
  resource_group_name = azurerm_resource_group.rg11.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_log_analytics_solution" "vminsights" {
  solution_name         = "VMInsights"
  location              = azurerm_resource_group.rg11.location
  resource_group_name   = azurerm_resource_group.rg11.name
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name        = azurerm_log_analytics_workspace.law.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/VMInsights"
  }
}