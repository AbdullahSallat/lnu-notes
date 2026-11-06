
output "web_public_ip" {
  description = "Public IP address of the web server"
  value       = azurerm_public_ip.web_ip.ip_address
}


output "db_private_ip" {
  description = "Private IP address of the database server"
  value       = azurerm_network_interface.db_nic.private_ip_address
}
