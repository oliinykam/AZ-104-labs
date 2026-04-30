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
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  location = "eastus"
  rg_name  = "az104-rg7"
  vnet_ip  = ["10.0.0.0/16"]
  sub_ip   = ["10.0.1.0/24"]
}

data "http" "my_public_ip" {
  url = "https://ipv4.icanhazip.com"
}

resource "random_integer" "suffix" {
  min = 10000
  max = 99999
}

resource "azurerm_resource_group" "lab_rg" {
  name     = local.rg_name
  location = local.location
}

resource "azurerm_virtual_network" "lab_vnet" {
  name                = "vnet-storage-lab"
  resource_group_name = azurerm_resource_group.lab_rg.name
  location            = azurerm_resource_group.lab_rg.location
  address_space       = local.vnet_ip
}

resource "azurerm_subnet" "storage_subnet" {
  name                 = "StorageSubnet"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.lab_vnet.name
  address_prefixes     = local.sub_ip
  service_endpoints    = ["Microsoft.Storage"]
}

resource "azurerm_storage_account" "lab_storage" {
  name                          = "az104stor${random_integer.suffix.result}"
  resource_group_name           = azurerm_resource_group.lab_rg.name
  location                      = azurerm_resource_group.lab_rg.location
  account_tier                  = "Standard"
  account_replication_type      = "GRS"
  public_network_access_enabled = true

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.storage_subnet.id]
    ip_rules                   = [chomp(data.http.my_public_ip.response_body)]
  }
}

resource "azurerm_storage_management_policy" "lifecycle_rule" {
  storage_account_id = azurerm_storage_account.lab_storage.id

  rule {
    name    = "Movetocool"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
      }
    }
  }
}

resource "azurerm_storage_container" "secure_data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.lab_storage.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "test_blob" {
  name                   = "securitytest/test-upload.txt"
  storage_account_name   = azurerm_storage_account.lab_storage.name
  storage_container_name = azurerm_storage_container.secure_data.name
  type                   = "Block"
  access_tier            = "Hot"
  source_content         = "Hello from Terraform! This is a test file for AZ-104 Lab 07."
}

resource "azurerm_storage_container_immutability_policy" "time_retention" {
  storage_container_resource_manager_id = azurerm_storage_container.secure_data.id
  immutability_period_in_days           = 180
  depends_on                            = [azurerm_storage_blob.test_blob]
}

resource "azurerm_storage_share" "lab_share" {
  name               = "share1"
  storage_account_id = azurerm_storage_account.lab_storage.id
  quota              = 50
  access_tier        = "TransactionOptimized"
}
