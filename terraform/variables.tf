variable "location" {
  default = "austriaeast"
}

variable "rg_name" {
  default = "ha-cluster-rg"
}

variable "golden_image_id" {
  description = "The ID of the Packer Image"
  default     = "/subscriptions/87a3738d-3e55-4c11-9e6e-da86774f84cf/resourceGroups/infra-state-rg/providers/Microsoft.Compute/images/golden-ubuntu-web-haproxy"
}

variable "admin_username" {
  default = "mazenadmin"
}
variable "ssh_public_key" {
  description = "The SSH Public Key for the VMs"
  type        = string
}
