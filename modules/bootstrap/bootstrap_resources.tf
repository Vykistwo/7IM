import {
  to = azurerm_resource_group.bootstrap
  id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/tf_starter"
}

resource "azurerm_resource_group" "bootstrap" {
  name = "tf_starter"
  location = "uksouth"
}


import {
  to = azurerm_storage_account.bootstrap
  id = "/subscriptions/${data.azurerm_subscription.current.subscription_id}/resourceGroups/tf_starter/providers/Microsoft.Storage/storageAccounts/${var.storage_account_name}"
}

resource "azurerm_storage_account" "bootstrap" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.bootstrap.name
  location                 = "uksouth"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  cross_tenant_replication_enabled = false
  allow_nested_items_to_be_public = false
}

import {
  to = azurerm_storage_container.bootstrap
  id = "https://${var.storage_account_name}.blob.core.windows.net/tfstate"
}


resource "azurerm_storage_container" "bootstrap" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.bootstrap.name
  container_access_type = "private"
}