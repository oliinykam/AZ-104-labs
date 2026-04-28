resource "azuread_group" "help_desk" {
  display_name     = "Help Desk"
  security_enabled = true
}

resource "azurerm_role_assignment" "vm_contributor" {
  scope                = azurerm_management_group.az104_mg1.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azuread_group.help_desk.object_id
}