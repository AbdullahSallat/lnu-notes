
# Azure Storage Account for application images
resource "azurerm_storage_account" "images" {
  name = "st2dv705${substr(replace(var.subscription_id, "-", ""), 0, 8)}"

  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  # Protect images against overwrites and accidental deletion
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
  }
}

# Private container for uploaded images
resource "azurerm_storage_container" "images" {
  name                  = "images"
  storage_account_id    = azurerm_storage_account.images.id
  container_access_type = "private"
}
