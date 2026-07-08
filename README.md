# 🏗️ Immutable Infrastructure & Dynamic Configuration

A production-style infrastructure project that builds a **Golden VM Image** with Packer, provisions a **High Availability web cluster** on Azure with Terraform, and configures all servers automatically with Ansible — all without touching the Azure console once.

![Packer](https://img.shields.io/badge/Packer-02A8EF?style=flat-square&logo=packer&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat-square&logo=ansible&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat-square&logo=microsoftazure&logoColor=white)

---

## 📌 What is Immutable Infrastructure?

In a traditional (mutable) setup, you SSH into a server and change its config, install packages, or patch it while it's running. Over time, servers accumulate undocumented changes — this is called **configuration drift**, and it's what makes "it works on my machine" a real production problem.

**Immutable Infrastructure** flips this model:

> Instead of modifying a running server — you throw it away and replace it with a fresh one built from a known-good image.

Every server in this project is born from the same **Golden Image** — a pre-baked, hardened, ready-to-configure VM image built once by Packer and used everywhere.

---

## 🏛️ Architecture

```
                        Internet
                           │
                     ┌─────▼──────┐
                     │   HAProxy   │  ← Only public-facing VM
                     │  (port 80)  │    Public IP: assigned by Azure
                     └─────┬──────┘
                           │ round-robin load balancing
               ┌───────────┴───────────┐
               │                       │
        ┌──────▼──────┐         ┌──────▼──────┐
        │  web-server-1│         │  web-server-2│
        │   (NGINX)    │         │   (NGINX)    │
        │  10.0.1.x    │         │  10.0.1.x    │
        └─────────────┘         └─────────────┘

        ← Private Subnet only — no public IPs →
        ← SSH access via HAProxy as Jump Host  →

All 3 VMs are built from the same Golden Image (Packer)
All networking lives inside: VNet 10.0.0.0/16 → Subnet 10.0.1.0/24
```

### Network Security Model

| Server | Public IP | SSH Access | HTTP Access |
|---|---|---|---|
| HAProxy | ✅ Yes | Direct | Port 80 (proxied to web servers) |
| web-server-1 | ❌ No | Via HAProxy (ProxyJump) | Internal only |
| web-server-2 | ❌ No | Via HAProxy (ProxyJump) | Internal only |

---

## 🧰 Tech Stack

| Tool | Version | Role |
|---|---|---|
| **Packer** | ≥ 1.11 | Builds the Golden VM Image |
| **Terraform** | ≥ 1.5 | Provisions Azure infrastructure |
| **Ansible** | Latest | Configures servers post-provisioning |
| **Azure** | — | Cloud provider (austriaeast region) |
| **NGINX** | Ubuntu apt | Web server on private VMs |
| **HAProxy** | Ubuntu apt | Load balancer, public entry point |

---

## 📁 Repository Structure

```
Packer-Ansible-project/
├── packer/
│   ├── ubuntu.pkr.hcl      # Packer template — defines the Golden Image
│   └── setup.sh             # Shell provisioner — runs inside the image at build time
├── terraform/
│   ├── providers.tf         # Azure provider + remote backend (Azure Blob Storage)
│   ├── variables.tf         # All input variables with descriptions
│   ├── main.tf              # VNet, Subnet, NICs, NSG, VMs
│   └── outputs.tf           # HAProxy public IP + web server private IPs
└── ansible/
    ├── ansible.cfg          # Ansible global settings (host key checking, pipelining)
    ├── inventory.ini        # Host definitions + ProxyJump config for private VMs
    ├── web.yml              # Playbook: configure NGINX on private web servers
    └── haproxy.yml          # Playbook: configure HAProxy load balancer
```

---

## ✅ Prerequisites

| Tool | Install |
|---|---|
| Azure CLI | https://learn.microsoft.com/en-us/cli/azure/install-azure-cli |
| Packer | https://developer.hashicorp.com/packer/install |
| Terraform | https://developer.hashicorp.com/terraform/install |
| Ansible | `pip install ansible` or `sudo apt install ansible` |

Log in to Azure before doing anything:

```bash
az login
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"
```

You also need two Azure resource groups created before starting:

```bash
# Holds the Golden Image and Terraform remote state
az group create --name infra-state-rg --location austriaeast

# Storage account for Terraform remote state
az storage account create \
  --name tfstatemazen2026 \
  --resource-group infra-state-rg \
  --location austriaeast \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name tfstatemazen2026
```

---

## 🔑 SSH Key Setup

All VMs use SSH key authentication only — no passwords.

```bash
# Generate a key pair if you don't have one
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""

# The public key goes into Terraform
cat ~/.ssh/id_rsa.pub
```

---

## 🚀 Step-by-Step Execution

### Step 1 — Build the Golden Image with Packer

The Golden Image is an Ubuntu 22.04 LTS VM with NGINX and HAProxy pre-installed, services disabled (Ansible manages them), and Azure-generalized for reuse.

```bash
cd packer

# Initialize the Azure Packer plugin
packer init ubuntu.pkr.hcl

# Validate the template
packer validate ubuntu.pkr.hcl

# Build the image (takes ~5-10 minutes)
packer build ubuntu.pkr.hcl
```

After a successful build, you'll see the image in Azure:

```bash
az image show \
  --resource-group infra-state-rg \
  --name golden-ubuntu-web-haproxy \
  --query id \
  --output tsv
```

Copy the image ID — you'll need it in the next step.

**What `setup.sh` does inside the image:**
- Updates all packages
- Installs NGINX, HAProxy, curl, vim, htop, net-tools
- Stops and disables both services (Ansible will start them with the right config)
- Cleans up logs and runs `waagent -deprovision` to generalize the image for Azure

> ⚠️ **Important:** `setup.sh` does a selective log cleanup (`*.log` files only) — it does **not** delete the `/var/log/nginx` or `/var/log/haproxy` *directories* themselves. Deleting those directories would cause NGINX to fail on its first start because it can't find its log path.

---

### Step 2 — Provision Infrastructure with Terraform

```bash
cd terraform

terraform init

# Pass the golden image ID and your SSH public key
terraform plan \
  -var="golden_image_id=<IMAGE_ID_FROM_STEP_1>" \
  -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

terraform apply \
  -var="golden_image_id=<IMAGE_ID_FROM_STEP_1>" \
  -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

**What Terraform creates:**

- Resource Group `ha-cluster-rg`
- VNet `cluster-vnet` (`10.0.0.0/16`) + Subnet `cluster-subnet` (`10.0.1.0/24`)
- 1 × HAProxy VM (`Standard_DS1_v2`) with a **public Static IP**
- 2 × Web VMs (`Standard_D2s_v3`) with **private IPs only**
- NSG on HAProxy allowing inbound SSH (22) and HTTP (80)
- Remote state stored in Azure Blob Storage

Get the outputs after apply:

```bash
terraform output haproxy_public_ip       # the public IP you'll use to access the site
terraform output web_servers_private_ips  # the private IPs for Ansible inventory
```

---

### Step 3 — Update Ansible Inventory

Open `ansible/inventory.ini` and fill in the real IPs from Terraform outputs:

```ini
[lb]
haproxy ansible_host=<HAPROXY_PUBLIC_IP>

[web]
web1 ansible_host=<WEB1_PRIVATE_IP>
web2 ansible_host=<WEB2_PRIVATE_IP>

[all:vars]
ansible_user=mazenadmin
ansible_ssh_private_key_file=~/.ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[web:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ProxyJump=mazenadmin@<HAPROXY_PUBLIC_IP>'
```

Also update the web server IPs in `ansible/haproxy.yml` under the `backend http_back` block:

```yaml
server web1 <WEB1_PRIVATE_IP>:80 check inter 2s rise 2 fall 3
server web2 <WEB2_PRIVATE_IP>:80 check inter 2s rise 2 fall 3
```

---

### Step 4 — Configure Servers with Ansible

Wait ~30 seconds after Terraform finishes for VMs to fully boot, then:

```bash
cd ansible

# Test connectivity first
ansible all -i inventory.ini -m ping

# Configure NGINX on the two private web servers
ansible-playbook -i inventory.ini web.yml

# Configure HAProxy load balancer
ansible-playbook -i inventory.ini haproxy.yml
```

**What `web.yml` does:**
- Disables HAProxy on web servers (not needed there)
- Recreates `/var/log/nginx` and `/var/run/nginx` directories (wiped during Packer generalization)
- Deploys a custom `index.html` that shows which server handled the request
- Enables and starts NGINX

**What `haproxy.yml` does:**
- Deploys the HAProxy config with both web server IPs
- Validates the config with `haproxy -c` before applying
- Enables round-robin load balancing with health checks
- Starts a stats dashboard on `:8080/stats`
- Restarts HAProxy via a handler (only if config changed)

---

### Step 5 — Verify Everything Works

```bash
# Hit the load balancer — refresh a few times to see round-robin in action
curl http://<HAPROXY_PUBLIC_IP>
curl http://<HAPROXY_PUBLIC_IP>

# Check HAProxy stats dashboard
curl http://<HAPROXY_PUBLIC_IP>:8080/stats

# SSH into a private web server through HAProxy (ProxyJump)
ssh -J mazenadmin@<HAPROXY_PUBLIC_IP> mazenadmin@<WEB1_PRIVATE_IP>

# Check NGINX status on a web server
systemctl status nginx
```

You should see alternating responses from `web1` and `web2` as HAProxy round-robins between them.

---

## 🧹 Teardown

```bash
cd terraform
terraform destroy \
  -var="golden_image_id=placeholder" \
  -var="ssh_public_key=placeholder"

# Optionally delete the Golden Image too
az image delete \
  --resource-group infra-state-rg \
  --name golden-ubuntu-web-haproxy
```

---

## 🛠️ Troubleshooting

**NGINX fails to start on web servers**

The most common cause: Packer's `waagent -deprovision` wipes `/var/log` contents during generalization, but if the log *directory* itself is missing, NGINX won't start. The `web.yml` playbook handles this by recreating both `/var/log/nginx` and `/var/run/nginx` before starting the service.

```bash
# Check what's wrong
ssh -J mazenadmin@<HAPROXY_PUBLIC_IP> mazenadmin@<WEB_IP>
sudo journalctl -u nginx --no-pager -n 30
sudo ls -la /var/log/nginx    # should exist
sudo ls -la /var/run/nginx    # should exist
```

**Ansible can't reach private web servers**

The `ProxyJump` in `inventory.ini` routes SSH through HAProxy. Make sure:
1. HAProxy VM is up and SSH-accessible
2. Your private key (`~/.ssh/id_rsa`) is the one that matches what was passed to Terraform
3. The private IPs in `inventory.ini` match `terraform output web_servers_private_ips`

```bash
# Test HAProxy SSH first
ssh -i ~/.ssh/id_rsa mazenadmin@<HAPROXY_PUBLIC_IP> "echo ok"

# Then test the jump
ssh -i ~/.ssh/id_rsa \
  -J mazenadmin@<HAPROXY_PUBLIC_IP> \
  mazenadmin@<WEB1_PRIVATE_IP> "echo ok"
```

**Terraform state issues**

Remote state is in Azure Blob Storage. If `terraform init` fails, check the storage account exists:

```bash
az storage account show --name tfstatemazen2026 --resource-group infra-state-rg
az storage container show --name tfstate --account-name tfstatemazen2026
```

---

## 🛡️ Security Practices Applied

- ✅ **No public IPs on web servers** — only HAProxy is internet-facing
- ✅ **SSH key authentication only** — password auth disabled on all VMs (`disable_password_authentication = true`)
- ✅ **NSG on HAProxy** — only ports 22 and 80 open inbound
- ✅ **ProxyJump for private server access** — web servers unreachable directly from the internet
- ✅ **Immutable image model** — servers are never patched in place; rebuild the image and reprovision
- ✅ **HAProxy config validation** — `haproxy -c` validates config before it's applied, preventing a bad config from taking down the LB
- ✅ **No credentials in code** — SSH public key passed as a variable, never hardcoded in `.tf` files
---
ِ**Author** 
:Mazen Elsayad
