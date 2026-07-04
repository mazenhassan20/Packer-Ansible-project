output "haproxy_public_ip" {
  value = azurerm_public_ip.haproxy_pip.ip_address
}

output "web_servers_private_ips" {
  value = azurerm_linux_virtual_machine.web_vm[*].private_ip_address
}