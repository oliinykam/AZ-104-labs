terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # Використовуємо 4.x версію, як у вашому прикладі
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  # У версії 4.0 іноді вимагається вказати subscription_id, 
  # але якщо ви вже залогінені через az login, має працювати і так.
}

# === TASK 1: Resource Group & Web App ===

resource "azurerm_resource_group" "rg9" {
  name     = "az104-rg9"
  location = "West Europe"
}

resource "random_id" "webapp_suffix" {
  byte_length = 4 # Згенерує 8 символів (hex), наприклад "a1b2c3d4"
}

resource "azurerm_service_plan" "asp9" {
  name                = "az104-asp9"
  resource_group_name = azurerm_resource_group.rg9.name
  location            = azurerm_resource_group.rg9.location
  os_type             = "Linux"
  sku_name            = "S1" 
}

resource "azurerm_linux_web_app" "webapp" {
  name                = "az104-webapp-${random_id.webapp_suffix.hex}"
  resource_group_name = azurerm_resource_group.rg9.name
  location            = azurerm_service_plan.asp9.location
  service_plan_id     = azurerm_service_plan.asp9.id

  site_config {
    always_on = false # Економить ресурси на S1
    application_stack {
      php_version = "8.2"
    }
  }
}

# === TASK 2: Deployment Slot ===

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.webapp.id

  site_config {
    always_on = false
    application_stack {
      php_version = "8.2"
    }
  }
}

# === TASK 3: GitHub Deployment Settings ===

resource "azurerm_app_service_source_control_slot" "github_staging" {
  slot_id                = azurerm_linux_web_app_slot.staging.id
  repo_url               = "https://github.com/Azure-Samples/php-docs-hello-world"
  branch                 = "master"
  use_manual_integration = true
}

# === TASK 5: Autoscaling (Rules Based) ===

resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "az104-autoscale"
  resource_group_name = azurerm_resource_group.rg9.name
  location            = azurerm_resource_group.rg9.location
  target_resource_id  = azurerm_service_plan.asp9.id

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 2
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.asp9.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.asp9.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT1M"
      }
    }
  }
}

# === OUTPUTS ===

output "staging_url" {
  value = "https://${azurerm_linux_web_app_slot.staging.default_hostname}"
}

output "swap_command" {
  value = <<-EOT
    az webapp deployment slot swap \
      --resource-group ${azurerm_resource_group.rg9.name} \
      --name ${azurerm_linux_web_app.webapp.name} \
      --slot staging \
      --target-slot production
  EOT
}