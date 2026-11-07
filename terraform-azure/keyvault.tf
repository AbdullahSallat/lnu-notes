
# Information about the Azure account used by Terraform
data "azurerm_client_config" "current" {}

# Key Vault for application secrets
resource "azurerm_key_vault" "app" {
  name = "kv2dv705${substr(replace(var.subscription_id, "-", ""), 0, 8)}"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}
