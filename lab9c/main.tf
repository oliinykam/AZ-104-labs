terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" 
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "East US" 
}

variable "rg_name" {
  type    = string
  default = "az104-rg9c" 
}

resource "azurerm_resource_group" "lab_rg" {
  name     = var.rg_name
  location = var.location
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.rg_name}"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "env" {
  name                       = "my-environment-oliinykA"
  location                   = azurerm_resource_group.lab_rg.location
  resource_group_name        = azurerm_resource_group.lab_rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

resource "azurerm_container_app" "app" {
  name                         = "my-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.lab_rg.name
  revision_mode                = "Single"

  template {
    container {
      name   = "hello-world-container"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 80
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

output "application_url" {
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}"
}