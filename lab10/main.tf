terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_id" "sa_id" {
  byte_length = 4
}

resource "azurerm_resource_group" "rg_region1" {
  name     = "az104-rg-region1"
  location = "East US"
}

resource "azurerm_virtual_network" "vnet1" {
  name                = "az104-10-vnet1"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg_region1.location
  resource_group_name = azurerm_resource_group.rg_region1.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg_region1.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.10.0.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "az104-10-nic"
  location            = azurerm_resource_group.rg_region1.location
  resource_group_name = azurerm_resource_group.rg_region1.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "vm0" {
  name                = "az104-10-vm0"
  resource_group_name = azurerm_resource_group.rg_region1.name
  location            = azurerm_resource_group.rg_region1.location
  size                = "Standard_DC2s_v3"
  admin_username      = "localadmin"
  admin_password      = "Pa55w.rd1234!" 

  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    name                 = "az104-10-vm0-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
}

resource "azurerm_recovery_services_vault" "vault" {
  name                = "az104-rsv-region1"
  location            = azurerm_resource_group.rg_region1.location
  resource_group_name = azurerm_resource_group.rg_region1.name
  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"
}

resource "azurerm_backup_policy_vm" "policy" {
  name                = "az104-backup"
  resource_group_name = azurerm_resource_group.rg_region1.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  timezone            = "FLE Standard Time"

  backup {
    frequency = "Daily"
    time      = "00:00"
  }

  retention_daily {
    count = 30
  }

  instant_restore_retention_days = 2
}

resource "azurerm_backup_protected_vm" "vm_backup" {
  resource_group_name = azurerm_resource_group.rg_region1.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  source_vm_id        = azurerm_windows_virtual_machine.vm0.id
  backup_policy_id    = azurerm_backup_policy_vm.policy.id
}

resource "azurerm_storage_account" "sa_logs" {
  name                     = "viklogs${random_id.sa_id.hex}"
  resource_group_name      = azurerm_resource_group.rg_region1.name
  location                 = azurerm_resource_group.rg_region1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_monitor_diagnostic_setting" "vault_diagnostics" {
  name               = "Logs and Metrics to storage"
  target_resource_id = azurerm_recovery_services_vault.vault.id
  storage_account_id = azurerm_storage_account.sa_logs.id

  enabled_log { category = "CoreAzureBackup" }
  enabled_log { category = "AddonAzureBackupJobs" }
  enabled_log { category = "AddonAzureBackupAlerts" }
  enabled_log { category = "AzureSiteRecoveryJobs" }
  enabled_log { category = "AzureSiteRecoveryEvents" }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_resource_group" "rg_region2" {
  name     = "az104-rg-region2"
  location = "West US"
}

resource "azurerm_recovery_services_vault" "vault_region2" {
  name                = "az104-rsv-region2"
  location            = azurerm_resource_group.rg_region2.location
  resource_group_name = azurerm_resource_group.rg_region2.name
  sku                 = "Standard"
}

resource "azurerm_virtual_network" "vnet_target" {
  name                = "az104-10-vnet2"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg_region2.location
  resource_group_name = azurerm_resource_group.rg_region2.name
}

resource "azurerm_storage_account" "sa_staging" {
  name                     = "asrstaging${random_id.sa_id.hex}"
  resource_group_name      = azurerm_resource_group.rg_region1.name
  location                 = azurerm_resource_group.rg_region1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_site_recovery_fabric" "primary" {
  name                = "primary-fabric"
  resource_group_name = azurerm_resource_group.rg_region2.name
  recovery_vault_name = azurerm_recovery_services_vault.vault_region2.name
  location            = azurerm_resource_group.rg_region1.location
}

resource "azurerm_site_recovery_fabric" "secondary" {
  name                = "secondary-fabric"
  resource_group_name = azurerm_resource_group.rg_region2.name
  recovery_vault_name = azurerm_recovery_services_vault.vault_region2.name
  location            = azurerm_resource_group.rg_region2.location
}

resource "azurerm_site_recovery_protection_container" "primary" {
  name                 = "primary-protection-container"
  resource_group_name  = azurerm_resource_group.rg_region2.name
  recovery_vault_name  = azurerm_recovery_services_vault.vault_region2.name
  recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
}

resource "azurerm_site_recovery_protection_container" "secondary" {
  name                 = "secondary-protection-container"
  resource_group_name  = azurerm_resource_group.rg_region2.name
  recovery_vault_name  = azurerm_recovery_services_vault.vault_region2.name
  recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
}

resource "azurerm_site_recovery_replication_policy" "policy" {
  name                                                 = "policy"
  resource_group_name                                  = azurerm_resource_group.rg_region2.name
  recovery_vault_name                                  = azurerm_recovery_services_vault.vault_region2.name
  recovery_point_retention_in_minutes                  = 24 * 60
  application_consistent_snapshot_frequency_in_minutes = 4 * 60
}

resource "azurerm_site_recovery_protection_container_mapping" "container_mapping" {
  name                                      = "container-mapping"
  resource_group_name                       = azurerm_resource_group.rg_region2.name
  recovery_vault_name                       = azurerm_recovery_services_vault.vault_region2.name
  recovery_fabric_name                      = azurerm_site_recovery_fabric.primary.name
  recovery_source_protection_container_name = azurerm_site_recovery_protection_container.primary.name
  recovery_target_protection_container_id   = azurerm_site_recovery_protection_container.secondary.id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy.id
}

resource "azurerm_site_recovery_network_mapping" "network_mapping" {
  name                        = "network-mapping"
  resource_group_name         = azurerm_resource_group.rg_region2.name
  recovery_vault_name         = azurerm_recovery_services_vault.vault_region2.name
  source_recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
  target_recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
  source_network_id           = azurerm_virtual_network.vnet1.id
  target_network_id           = azurerm_virtual_network.vnet_target.id
}

data "azurerm_managed_disk" "osdisk" {
  name                = "az104-10-vm0-osdisk"
  resource_group_name = azurerm_resource_group.rg_region1.name
  depends_on          = [azurerm_windows_virtual_machine.vm0]
}

resource "azurerm_site_recovery_replicated_vm" "vm_replication" {
  name                                      = "vm-replication"
  resource_group_name                       = azurerm_resource_group.rg_region2.name
  recovery_vault_name                       = azurerm_recovery_services_vault.vault_region2.name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.primary.name
  source_vm_id                              = azurerm_windows_virtual_machine.vm0.id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy.id
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.primary.name
  
  target_resource_group_id                = azurerm_resource_group.rg_region2.id
  target_recovery_fabric_id               = azurerm_site_recovery_fabric.secondary.id
  target_recovery_protection_container_id = azurerm_site_recovery_protection_container.secondary.id
  target_network_id                       = azurerm_virtual_network.vnet_target.id

  managed_disk {
    disk_id                    = data.azurerm_managed_disk.osdisk.id
    staging_storage_account_id = azurerm_storage_account.sa_staging.id
    target_disk_type           = "Standard_LRS"
    target_replica_disk_type   = "Standard_LRS"
    target_resource_group_id   = azurerm_resource_group.rg_region2.id
  }

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.container_mapping,
    azurerm_site_recovery_network_mapping.network_mapping,
  ]
}