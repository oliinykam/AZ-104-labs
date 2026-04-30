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

# Використання локальних змінних для уникнення хардкоду та легкої зміни параметрів
locals {
  resource_group_name = "az104-rg9b"
  location            = "East US"
  container_name      = "az104-c1"
  image               = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
}

# Task 1: Створення Resource Group згідно з вимогами лаби
resource "azurerm_resource_group" "lab_rg" {
  name     = local.resource_group_name
  location = local.location
  tags = {
    environment = "Lab-09b"
    managed_by  = "Terraform"
  }
}

# Генерація унікального суфікса для DNS, щоб уникнути конфліктів імен
resource "random_string" "dns_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Task 1: Розгортання Azure Container Instance
resource "azurerm_container_group" "lab_aci" {
  name                = local.container_name
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  ip_address_type     = "Public"
  dns_name_label      = "az104-oliinykA-${random_string.dns_suffix.result}"
  os_type             = "Linux"

  container {
    name   = "hello-world"
    image  = local.image
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  tags = azurerm_resource_group.lab_rg.tags
}

# Вивід FQDN (повного доменного імені) для швидкого тестування в Task 2
output "container_fqdn" {
  description = "The FQDN of the deployed Azure Container Instance."
  value       = azurerm_container_group.lab_aci.fqdn
}