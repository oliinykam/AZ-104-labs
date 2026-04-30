terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  admin_user = "localadmin"
  admin_pass = "Pa55w.rd1234!"
  location   = "North Europe"
  zone       = "2"
  vm_size    = "Standard_DC1s_v3"
  image_sku  = "2022-datacenter-g2"
}

resource "azurerm_resource_group" "lab_rg" {
  name     = "az104-rg8-v1"
  location = local.location
}

resource "azurerm_virtual_network" "vm_vnet" {
  name                = "vm-vnet"
  address_space       = ["10.80.0.0/20"]
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
}

resource "azurerm_subnet" "vm_subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.vm_vnet.name
  address_prefixes     = ["10.80.0.0/24"]
}

resource "azurerm_network_interface" "vm_nic" {
  count               = 2
  name                = "az104-vm${count.index + 1}-nic"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vms" {
  count               = 2
  name                = "az104-vm${count.index + 1}"
  resource_group_name = azurerm_resource_group.lab_rg.name
  location            = azurerm_resource_group.lab_rg.location
  size                = local.vm_size
  zone                = local.zone
  admin_username      = local.admin_user
  admin_password      = local.admin_pass

  network_interface_ids = [azurerm_network_interface.vm_nic[count.index].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = local.image_sku
    version   = "latest"
  }
}

resource "azurerm_managed_disk" "vm1_data_disk" {
  name                 = "vm1-disk1"
  location             = azurerm_resource_group.lab_rg.location
  resource_group_name  = azurerm_resource_group.lab_rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 32
  zone                 = local.zone
}

resource "azurerm_virtual_machine_data_disk_attachment" "vm1_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.vm1_data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.vms[0].id 
  lun                = 10
  caching            = "ReadWrite"
}

resource "azurerm_virtual_network" "vmss_vnet" {
  name                = "vmss-vnet"
  address_space       = ["10.82.0.0/20"]
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
}

resource "azurerm_subnet" "vmss_subnet" {
  name                 = "subnet0" 
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.vmss_vnet.name
  address_prefixes     = ["10.82.0.0/24"] 
}

resource "azurerm_network_security_group" "vmss_nsg" {
  name                = "vmss1-nsg"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name

  security_rule {
    name                       = "allow-http"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80" 
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "vmss_pip" {
  name                = "vmss-lb-pip"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "vmss_lb" {
  name                = "vmss-lb"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.vmss_pip.id
  }
}

resource "azurerm_lb_backend_address_pool" "vmss_bepool" {
  loadbalancer_id = azurerm_lb.vmss_lb.id
  name            = "BackEndAddressPool"
}

resource "azurerm_windows_virtual_machine_scale_set" "vmss" {
  name                 = "vmss1"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  location             = azurerm_resource_group.lab_rg.location
  sku                  = local.vm_size
  instances            = 2
  admin_username       = local.admin_user
  admin_password       = local.admin_pass
  zones                = [local.zone] 

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = local.image_sku
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name                      = "nic"
    primary                   = true
    network_security_group_id = azurerm_network_security_group.vmss_nsg.id

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.vmss_subnet.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.vmss_bepool.id]
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "vmss_autoscale" {
  name                = "vmss1-autoscale"
  resource_group_name = azurerm_resource_group.lab_rg.name
  location            = azurerm_resource_group.lab_rg.location
  target_resource_id  = azurerm_windows_virtual_machine_scale_set.vmss.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 2
      minimum = 2
      maximum = 10 
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70 
      }

      scale_action {
        direction = "Increase"
        type      = "PercentChangeCount"
        value     = "50" 
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_windows_virtual_machine_scale_set.vmss.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30 
      }

      scale_action {
        direction = "Decrease"
        type      = "PercentChangeCount"
        value     = "20"
        cooldown  = "PT5M"
      }
    }
  }
}