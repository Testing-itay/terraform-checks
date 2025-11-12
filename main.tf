resource "azurerm_public_ip" "public_ip_afw" {
  name                    = var.public_ip_name
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku                     = var.public_ip_sku
  sku_tier                = var.public_ip_sku_tier
  zones                   = var.public_ip_zones
  allocation_method       = var.public_ip_allocation_method
  ddos_protection_mode    = var.public_ip_ddos_protection_mode
  idle_timeout_in_minutes = var.public_ip_idle_timeout_in_minutes
  tags                    = var.tags
}

resource "azurerm_firewall" "afw" {
  name                = var.afw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  zones               = var.afw_zones
  threat_intel_mode   = var.afw_threat_intel_mode
  sku_name            = var.afw_sku
  sku_tier            = var.afw_tier

  ip_configuration {
    name                 = "afw_ip_config"
    subnet_id            = var.afw_subnet_id
    public_ip_address_id = azurerm_public_ip.public_ip_afw.id
  }
}

resource "azurerm_firewall_application_rule_collection" "afw_application_rules" {
  name                = "ApplicationRules"
  azure_firewall_name = azurerm_firewall.afw.name
  resource_group_name = azurerm_firewall.afw.resource_group_name
  priority            = 500
  action              = "Allow"

  dynamic "rule" {
    for_each = var.afw_application_rules
    content {
      name             = rule.value.name
      source_addresses = rule.value.source_addresses
      target_fqdns     = rule.value.target_fqdns

      dynamic "protocol" {
        for_each = rule.value.protocol
        content {
          port = protocol.value.port
          type = protocol.value.type
        }
      }
    }
  }
}

resource "azurerm_firewall_network_rule_collection" "afw_network_rules" {
  name                = "NetworkRules"
  azure_firewall_name = azurerm_firewall.afw.name
  resource_group_name = azurerm_firewall.afw.resource_group_name
  priority            = 400
  action              = "Allow"

  dynamic "rule" {
    for_each = var.afw_network_rules
    content {
      name                  = rule.value.name
      source_addresses      = rule.value.source_addresses
      destination_ports     = rule.value.destination_ports
      destination_addresses = rule.value.destination_addresses
      protocols             = rule.value.protocols
    }
  }
}

module "monitor_diagnostics_setting" {
  source = "git::https://dev.azure.com/semperis/Identity%20Protection/_git/infra-tf-modules//azure/monitor_diagnostics_setting"

  diagnostic_settings = [
    {
      name                       = var.diagnostic_setting_public_ip_name
      target_resource_id         = azurerm_public_ip.public_ip_afw.id
      log_analytics_workspace_id = var.diagnostic_setting_public_ip_log_analytics_workspace_id
      enabled_log                = var.diagnostic_setting_public_ip_enabled_log
      metrics                    = var.diagnostic_setting_public_ip_metrics
    },
    {
      name                       = var.diagnostic_setting_afw_name
      target_resource_id         = azurerm_firewall.afw.id
      log_analytics_workspace_id = var.diagnostic_setting_afw_log_analytics_workspace_id
      enabled_log                = var.diagnostic_setting_afw_enabled_log
      metrics                    = var.diagnostic_setting_afw_metrics
    },
  ]
}

locals {
  alerts = [
    for alert in var.afw_alerts : merge(alert, { scopes = [azurerm_firewall.afw.id], tags = var.tags })
  ]

   pip_alerts = [
    for pip_alert in var.pip_afw_alerts : merge(pip_alert, { scopes = [azurerm_public_ip.public_ip_afw.id], tags = var.tags })
  ]
  log_alerts = [
    for alert in var.afw_log_alerts : merge(alert, { scopes = [azurerm_firewall.afw.id], tags = var.tags })
  ]
}

module "metric_alert" {
  source = "git::https://dev.azure.com/semperis/Identity%20Protection/_git/infra-tf-modules//azure/metric_alert"
  alerts = concat(local.alerts, local.pip_alerts)
}

module "log_alert" {
  source = "git::https://dev.azure.com/semperis/Identity%20Protection/_git/infra-tf-modules//azure/log_alert"
  alerts = local.log_alerts
}
