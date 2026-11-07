
# Allow the web VM to read and write application images.
resource "azurerm_role_assignment" "web_blob_access" {
  scope                = azurerm_storage_account.images.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.web.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}


# Web VM can read database secrets
resource "azurerm_role_assignment" "web_keyvault" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.web.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# Database VM can read database secrets
resource "azurerm_role_assignment" "db_keyvault" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.db.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}


# Allow the current Azure user to create and manage secrets
resource "azurerm_role_assignment" "current_user_keyvault" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
