resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location
}

# 1.VNet & Subnet
resource "azurerm_virtual_network" "vnet" {
  name                = "cluster-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "cluster-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# 2. Public IP للـ HAProxy فقط
resource "azurerm_public_ip" "haproxy_pip" {
  name                = "haproxy-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# 3. Network Interfaces 
resource "azurerm_network_interface" "haproxy_nic" {
  name                = "haproxy-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.haproxy_pip.id
  }
}

resource "azurerm_network_interface" "web_nic" {
  count               = 2
  name                = "web-nic-${count.index}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# 4. بناء السيرفرات باستخدام الـ Golden Image
resource "azurerm_linux_virtual_machine" "haproxy_vm" {
  name                            = "haproxy-server"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_DS1_v2"
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") 
}
  network_interface_ids           = [azurerm_network_interface.haproxy_nic.id]
  source_image_id                 = var.golden_image_id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}

resource "azurerm_linux_virtual_machine" "web_vm" {
  count                           = 2
  name                            = "web-server-${count.index + 1}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_D2s_v3"
  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub") 
}
  network_interface_ids           = [azurerm_network_interface.web_nic[count.index].id]
  source_image_id                 = var.golden_image_id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
}
# 5. Security Group for HAProxy (Allow SSH & HTTP)
resource "azurerm_network_security_group" "haproxy_nsg" {
  name                = "haproxy-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "haproxy_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.haproxy_nic.id
  network_security_group_id = azurerm_network_security_group.haproxy_nsg.id
}