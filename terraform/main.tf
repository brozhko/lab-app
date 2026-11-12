terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

variable "db_password" { type = string }

resource "azurerm_resource_group" "rg" {
  name     = "lab-resources-eu"
  location = "North Europe"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "lab-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  delegation {
    name = "fs"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "db_dns" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "db_dns_link" {
  name                  = "db-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.db_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

resource "azurerm_postgresql_flexible_server" "db" {
  name                   = "lab-pg-danilo-eu"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "14"
  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.db_dns.id
  administrator_login    = "labuser"
  administrator_password = var.db_password
  storage_mb             = 32768
  sku_name               = "B_Standard_B2s"
  public_network_access_enabled = false
  depends_on             = [azurerm_private_dns_zone_virtual_network_link.db_dns_link]
}

resource "azurerm_container_registry" "acr" {
  name                = "labacrdaniloeu"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true 
}

resource "azurerm_container_app_environment" "env" {
  name                = "lab-env"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_container_app" "api" {
  name                         = "api-service"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 3000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "api-container"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name  = "DATABASE_URL"
        value = "postgres://labuser:${var.db_password}@${azurerm_postgresql_flexible_server.db.fqdn}:5432/postgres"
      }
    }
  }
}

output "app_url" { value = azurerm_container_app.api.ingress[0].fqdn }
output "acr_login_server" { value = azurerm_container_registry.acr.login_server }
output "acr_username" { value = azurerm_container_registry.acr.admin_username }