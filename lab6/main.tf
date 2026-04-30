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

resource "azurerm_resource_group" "lab_rg" {
  name     = "az104-rg6-v3"
  location = "North Europe"
}

resource "azurerm_virtual_network" "main_network" {
  name                = "az104-06-vnet1"
  address_space       = ["10.60.0.0/22"]
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
}

resource "azurerm_subnet" "web_subnet_1" {
  name                 = "Subnet0"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.main_network.name
  address_prefixes     = ["10.60.0.0/24"]
}

resource "azurerm_subnet" "web_subnet_2" {
  name                 = "Subnet1"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.main_network.name
  address_prefixes     = ["10.60.1.0/24"]
}

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.lab_rg.name
  virtual_network_name = azurerm_virtual_network.main_network.name
  address_prefixes     = ["10.60.3.224/27"]
}

resource "azurerm_network_security_group" "web_nsg" {
  name                = "az104-06-nsg"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name

  security_rule {
    name                       = "allow-http"
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

resource "azurerm_subnet_network_security_group_association" "nsg_bind_0" {
  subnet_id                 = azurerm_subnet.web_subnet_1.id
  network_security_group_id = azurerm_network_security_group.web_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "nsg_bind_1" {
  subnet_id                 = azurerm_subnet.web_subnet_2.id
  network_security_group_id = azurerm_network_security_group.web_nsg.id
}

resource "azurerm_network_interface" "vm_nics" {
  count               = 2
  name                = "az104-06-nic${count.index}"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = count.index == 0 ? azurerm_subnet.web_subnet_1.id : azurerm_subnet.web_subnet_2.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "web_servers" {
  count               = 2
  name                = "az104-06-vm${count.index}"
  resource_group_name = azurerm_resource_group.lab_rg.name
  location            = azurerm_resource_group.lab_rg.location
  size                = "Standard_D2s_v3"
  admin_username      = "student"
  admin_password      = "Pa55w.rd1234"

  network_interface_ids = [azurerm_network_interface.vm_nics[count.index].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "iis_setup" {
  count                = 2
  name                 = "IIS-Setup"
  virtual_machine_id   = azurerm_windows_virtual_machine.web_servers[count.index].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = jsonencode({
    "commandToExecute" = "powershell.exe Install-WindowsFeature -name Web-Server -IncludeManagementTools && powershell.exe remove-item 'C:\\inetpub\\wwwroot\\iisstart.htm' && powershell.exe Add-Content -Path 'C:\\inetpub\\wwwroot\\iisstart.htm' -Value $('Hello World from ' + $env:computername) && powershell.exe New-Item -Path 'c:\\inetpub\\wwwroot' -Name 'image' -Itemtype 'Directory' && powershell.exe New-Item -Path 'c:\\inetpub\\wwwroot\\image\\' -Name 'iisstart.htm' -ItemType 'file' && powershell.exe Add-Content -Path 'C:\\inetpub\\wwwroot\\image\\iisstart.htm' -Value $('Image from: ' + $env:computername) && powershell.exe New-Item -Path 'c:\\inetpub\\wwwroot' -Name 'video' -Itemtype 'Directory' && powershell.exe New-Item -Path 'c:\\inetpub\\wwwroot\\video\\' -Name 'iisstart.htm' -ItemType 'file' && powershell.exe Add-Content -Path 'C:\\inetpub\\wwwroot\\video\\iisstart.htm' -Value $('Video from: ' + $env:computername)"
  })
}

resource "azurerm_public_ip" "lb_public_ip" {
  name                = "az104-lbpip"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_lb" "external_lb" {
  name                = "az104-lb"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "az104-fe"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "lb_pool" {
  loadbalancer_id = azurerm_lb.external_lb.id
  name            = "az104-be"
}

resource "azurerm_network_interface_backend_address_pool_association" "lb_nic_bind" {
  count                   = 2
  network_interface_id    = azurerm_network_interface.vm_nics[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_pool.id
}

resource "azurerm_lb_probe" "lb_health_probe" {
  loadbalancer_id     = azurerm_lb.external_lb.id
  name                = "az104-hp"
  port                = 80
  protocol            = "Tcp"
  interval_in_seconds = 5
}

resource "azurerm_lb_rule" "lb_http_rule" {
  loadbalancer_id                = azurerm_lb.external_lb.id
  name                           = "az104-lbrule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "az104-fe"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lb_pool.id]
  probe_id                       = azurerm_lb_probe.lb_health_probe.id
}

resource "azurerm_public_ip" "appgw_public_ip" {
  name                = "az104-gwpip"
  location            = azurerm_resource_group.lab_rg.location
  resource_group_name = azurerm_resource_group.lab_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "main_appgw" {
  name                = "az104-appgw"
  resource_group_name = azurerm_resource_group.lab_rg.name
  location            = azurerm_resource_group.lab_rg.location

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "agw-ip-config"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "agw-fe-config"
    public_ip_address_id = azurerm_public_ip.appgw_public_ip.id
  }

  backend_address_pool {
    name         = "az104-appgwbe"
    ip_addresses = [for nic in azurerm_network_interface.vm_nics : nic.private_ip_address]
  }

  backend_address_pool {
    name         = "az104-imagebe"
    ip_addresses = [azurerm_network_interface.vm_nics[0].private_ip_address]
  }

  backend_address_pool {
    name         = "az104-videobe"
    ip_addresses = [azurerm_network_interface.vm_nics[1].private_ip_address]
  }

  backend_http_settings {
    name                  = "az104-http"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "az104-listener"
    frontend_ip_configuration_name = "agw-fe-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name               = "az104-gwrule"
    rule_type          = "PathBasedRouting"
    http_listener_name = "az104-listener"
    url_path_map_name  = "url-path-map"
    priority           = 10
  }

  url_path_map {
    name                               = "url-path-map"
    default_backend_address_pool_name  = "az104-appgwbe"
    default_backend_http_settings_name = "az104-http"

    path_rule {
      name                       = "images"
      paths                      = ["/image/*"]
      backend_address_pool_name  = "az104-imagebe"
      backend_http_settings_name = "az104-http"
    }

    path_rule {
      name                       = "videos"
      paths                      = ["/video/*"]
      backend_address_pool_name  = "az104-videobe"
      backend_http_settings_name = "az104-http"
    }
  }
}

output "load_balancer_public_ip" {
  description = "Public IP for Load Balancer testing"
  value       = azurerm_public_ip.lb_public_ip.ip_address
}

output "appgw_public_ip" {
  description = "Public IP for Application Gateway testing"
  value       = azurerm_public_ip.appgw_public_ip.ip_address
}