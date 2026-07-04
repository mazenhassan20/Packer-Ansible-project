packer {
  required_plugins {
    azure = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

source "azure-arm" "ubuntu_golden" {
  use_azure_cli_auth = true

  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  vm_size         = "Standard_D2s_v3"
  location        = "austriaeast"

  managed_image_resource_group_name = "infra-state-rg"
  managed_image_name                = "golden-ubuntu-web-haproxy"
}

build {
  sources = ["source.azure-arm.ubuntu_golden"]

  provisioner "shell" {
    script = "./setup.sh"
  }
}