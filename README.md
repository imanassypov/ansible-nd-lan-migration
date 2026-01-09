# Ansible DC LAN Migration

Automated migration tooling for Cisco NX-OS switches from CLI-based management to Nexus Dashboard Fabric Controller (NDFC). This project provides complete workflows to:
- **Profile** existing switch configurations
- **Migrate** switches to centralized NDFC management
- **Pre-provision** new access switches before physical deployment

## Overview

This project implements two main workflows:

### Migration Workflow (Existing Switches)
Sequential playbooks to migrate existing CLI-managed switches to NDFC:
1. **Discovery** → Extract configurations from switches
2. **Provision Fabric** → Create fabric definitions in NDFC
3. **Deploy** → Configure VLANs, VPC, and interfaces

### Pre-Provisioning Workflow (New Switches)
Configure new access switches in NDFC before physical deployment:
1. **Pre-provision** → Register switch with serial number
2. **Configure** → Features, interfaces, VLANs, routes
3. **Bootstrap** → Deploy configuration via POAP

---

## Quick Start

```bash
# 1. Clone and setup environment
git clone <repository-url>
cd ansible-dc-lan-migration
uv sync && source .venv/bin/activate
ansible-galaxy collection install -r requirements.yml

# 2. Configure vault
echo "your-password" > .vault_pass
ansible-vault edit inventory/group_vars/all/vault.yml

# 3. Run full provisioning
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml
```

---

## Project Structure

```
ansible-dc-lan-migration/
├── fabrics/                                    # Generated artifacts per fabric
│   └── <fabric-name>/
│       ├── switch_features.yml                 # Enabled NX-OS features
│       ├── vlan_database.yml                   # VLAN configurations
│       ├── l2_interfaces.yml                   # L2 interface configs
│       ├── l2_vpc_interfaces.yml               # VPC interface configs
│       ├── l3_interfaces.yml                   # L3 interface configs (SVIs, loopbacks, routed)
│       └── static_routes.yml                   # Static route configurations
│
├── inventory/
│   ├── hosts.yml                               # Switch and ND host definitions
│   ├── group_vars/
│   │   ├── all/vault.yml                       # Encrypted credentials
│   │   └── nd/connection.yml                   # ND API settings
│   └── host_vars/nexus_dashboard/
│       └── fabric_definitions.yml              # Fabric source of truth
│
├── playbooks/
│   ├── discovery/                              # Profile existing switches
│   │   └── 1.0-profile-existing-switches.yml
│   ├── provision-fabric/                       # Fabric configuration
│   │   └── 1.0-configure-nd-fabric.yml
│   └── provision-switch/                       # Switch provisioning workflow
│       ├── 0.0-full-provision-switch.yml       # Master orchestration playbook
│       ├── 1.0-preprovision-new-switches.yml
│       ├── 1.1-create-discovery-user.yml
│       ├── 1.2-provision-features.yml
│       ├── 1.3-deploy-vpc-domain.yml
│       ├── 1.4-provision-interfaces.yml
│       ├── 1.5-provision-vlan-policies.yml
│       ├── 1.6-provision-default-route.yml
│       ├── 1.7-check-poap-status.yml
│       └── 1.8-bootstrap-switches.yml
│
├── templates/                                  # Jinja2 templates for API payloads
│
├── ansible.cfg
├── pyproject.toml
└── requirements.yml
```

---

## Playbook Reference

### Switch Provisioning Workflow (provision-switch/)

The master playbook `0.0-full-provision-switch.yml` executes all playbooks in sequence. You can also run individual playbooks as needed.

| # | Playbook | Template(s) | Description |
|---|----------|-------------|-------------|
| 0.0 | `full-provision-switch.yml` | — | Master orchestration playbook that executes all provisioning steps 1.0-1.8 in sequence |
| 1.0 | `preprovision-new-switches.yml` | `1.0-preprovision-new-switches.json.j2` | Pre-provision switches to NDFC via POAP API. Registers switch serial number, model, version, IP, role, and gateway |
| 1.1 | `create-discovery-user.yml` | `1.1-create-discovery-user.json.j2` | Create NDFC discovery user (switch_user policy) for switch authentication during discovery |
| 1.2 | `provision-features.yml` | `1.2-provision-features.json.j2` | Configure NX-OS feature policies (LACP, LLDP, interface-vlan, etc.) using feature_lookup.yml mapping |
| 1.3 | `deploy-vpc-domain.yml` | `1.3-deploy-vpc-domain.json.j2` | Deploy VPC domain configuration between aggregation switch pairs |
| 1.4 | `provision-interfaces.yml` | `1.4-provision-interfaces-*.json.j2` | Configure L2/L3 interfaces (Ethernet, port-channels, VPC, SVI) with trunk/access/routed modes |
| 1.5 | `provision-vlan-policies.yml` | `1.5-provision-vlan-policies.json.j2` | Deploy VLAN policies from vlan_database.yml to switches |
| 1.6 | `provision-default-route.yml` | `1.6-provision-default-route.json.j2` | Configure static default route (0.0.0.0/0) via management gateway |
| 1.7 | `check-poap-status.yml` | — | Query POAP inventory to check if switches have connected and are ready for bootstrap |
| 1.8 | `bootstrap-switches.yml` | `1.8-bootstrap-switches.json.j2` | Bootstrap pre-provisioned switches via POAP API to deploy Day-0 configuration |

### Discovery Workflow (discovery/)

| Playbook | Template(s) | Description |
|----------|-------------|-------------|
| `1.0-profile-existing-switches.yml` | `switch_features.yml.j2`, `vlan_database.yml.j2`, `interfaces_inventory.j2`, `vpc_inventory.j2`, `static_routes.j2` | Profile existing switches via SSH to extract configurations into YAML files |

### Fabric Provisioning (provision-fabric/)

| Playbook | Template(s) | Description |
|----------|-------------|-------------|
| `1.0-configure-nd-fabric.yml` | `02-configure-nd-fabric.json.j2` | Create and configure fabric definitions in NDFC |

---

## Provisioning Workflow

### Full Automated Provisioning

Run the master playbook to execute all steps:

```bash
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml -v
```

### Step-by-Step Execution

```bash
# 1.0 - Pre-provision switches with NDFC
ansible-playbook playbooks/provision-switch/1.0-preprovision-new-switches.yml

# 1.1 - Create discovery user for NDFC authentication
ansible-playbook playbooks/provision-switch/1.1-create-discovery-user.yml

# 1.2 - Configure NX-OS features
ansible-playbook playbooks/provision-switch/1.2-provision-features.yml

# 1.3 - Deploy VPC domain (for aggregation switches)
ansible-playbook playbooks/provision-switch/1.3-deploy-vpc-domain.yml

# 1.4 - Configure interfaces (L2, port-channels, VPC)
ansible-playbook playbooks/provision-switch/1.4-provision-interfaces.yml

# 1.5 - Deploy VLAN policies
ansible-playbook playbooks/provision-switch/1.5-provision-vlan-policies.yml

# 1.6 - Configure default route
ansible-playbook playbooks/provision-switch/1.6-provision-default-route.yml

# 1.7 - Check if switches connected via POAP
ansible-playbook playbooks/provision-switch/1.7-check-poap-status.yml

# 1.8 - Bootstrap switches to deploy configuration
ansible-playbook playbooks/provision-switch/1.8-bootstrap-switches.yml
```

### Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    SWITCH PROVISIONING WORKFLOW                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1.0 Pre-provision    Register switch (serial, IP, model, role)         │
│         ↓                                                                │
│  1.1 Discovery User   Create switch_user for NDFC authentication        │
│         ↓                                                                │
│  1.2 Features         Enable NX-OS features (LACP, LLDP, etc.)          │
│         ↓                                                                │
│  1.3 VPC Domain       Configure VPC peer-link (aggregation only)        │
│         ↓                                                                │
│  1.4 Interfaces       Configure L2/L3/VPC interfaces                    │
│         ↓                                                                │
│  1.5 VLANs            Deploy VLAN policies                              │
│         ↓                                                                │
│  1.6 SVI              Configure management SVI with IP                  │
│         ↓                                                                │
│  1.7 Default Route    Configure static default route                    │
│         ↓                                                                │
│  1.8 POAP Status      Check switch connectivity to NDFC                 │
│         ↓                                                                │
│  1.9 Bootstrap        Deploy Day-0 config via POAP                      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Inventory Configuration

### Switch Inventory

Add switches to provision in `inventory/hosts.yml`:

```yaml
switches:
  children:
    access:
      hosts:
        mgmt-acc01:
          ansible_host: 198.18.24.81          # Source switch IP (for profiling)
          fabric: mgmt-fabric
          role: access
          add_to_fabric: true                  # Flag to include in provisioning
          destination_switch_sn: 9VBJSRKWVIZ   # NEW switch serial number
          destination_switch_model: N9K-C9300v
          destination_switch_version: "10.6(1)"
```

### Vault Configuration

Configure credentials in `inventory/group_vars/all/vault.yml`:

```yaml
vault_switch_password: "switch-password"
vault_nd_password: "nexus-dashboard-password"
vault_discovery_username: "ndfc"              # Optional: defaults to 'ndfc'
vault_discovery_password: "discovery-pass"    # Optional: defaults to vault_switch_password
```

---

## Idempotency

All provisioning playbooks are **idempotent**:
- Query NDFC for existing resources before creating
- Skip already-configured items
- Safe to re-run multiple times

Example output:
```
Feature policies to configure (excluding existing): 2
Already configured (skipped): 5
- mgmt-acc01: lacp -> feature_lacp
- mgmt-acc01: lldp -> feature_lldp
```

---

## Connection Patterns

### NX-OS Switches (`network_cli`)
- SSH connection to switches
- Uses `cisco.nxos` collection
- Credentials: `vault_switch_password`

### Nexus Dashboard (`httpapi`)
- HTTPS REST API connection
- Uses `cisco.nd` collection
- Credentials: `vault_nd_password`
- Timeout: 1000 seconds

---

## Troubleshooting

### Common Commands

```bash
# Dry-run mode
ansible-playbook playbooks/provision-switch/1.0-preprovision-new-switches.yml --check

# Verbose output
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml -vvv

# List tasks
ansible-playbook playbooks/provision-switch/1.4-provision-interfaces.yml --list-tasks

# Lint playbooks
ansible-lint playbooks/**/*.yml
```

### Verify Generated Files

```bash
ls -la fabrics/mgmt-fabric/
cat fabrics/mgmt-fabric/l2_interfaces.yml
cat fabrics/mgmt-fabric/switch_features.yml
```

### Check Vault

```bash
ansible-vault view inventory/group_vars/all/vault.yml
```

---

## Prerequisites

### Software
- **Python 3.13+** (via UV)
- **Ansible Core 2.15.0+**
- **UV Package Manager**

### Ansible Collections
- `cisco.nd` >= 1.3.0
- `cisco.dcnm` >= 2.4.0
- `cisco.nxos` >= 4.6.0

### Install

```bash
# Install UV
curl -LsSf https://astral.sh/uv/install.sh | sh

# Setup project
uv sync
source .venv/bin/activate
ansible-galaxy collection install -r requirements.yml
```

---

## Appendix

### A. API Endpoints Reference

Complete list of NDFC REST API endpoints used by this project:

| Endpoint | Method | Playbook(s) | Purpose |
|----------|--------|-------------|---------|
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/fabrics/{fabric}/inventory` | GET | 1.0 | Query existing switches in fabric |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/fabrics/{fabric}/inventory/poap` | GET | 1.8, 1.9 | Query POAP inventory for connected switches |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/fabrics/{fabric}/inventory/poap` | POST | 1.0, 1.9 | Pre-provision switch / Bootstrap switch via POAP |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/policies/switches/{serial}` | GET | 1.1, 1.2, 1.5, 1.7 | Query existing policies for a switch (idempotency check) |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/policies/bulk-create` | POST | 1.1, 1.2, 1.5, 1.7 | Create switch policies (features, VLANs, routes, users) |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/vpcpair` | GET | 1.3 | Query existing VPC pairs |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/vpcpair` | POST | 1.3 | Create VPC domain pair |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/vpcpair` | DELETE | 1.3 | Delete VPC pair (cleanup) |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/interface/detail?serialNumber={serial}` | GET | 1.4 | Query existing interfaces on a switch |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/interface?serialNumber={serial}` | GET | 1.6 | Query interface summary for a switch |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/globalInterface` | POST | 1.4, 1.6 | Create/configure interfaces (L2, L3, VPC, SVI) |
| `/api/v1/manage/fabrics/{fabric}/switches` | GET | 1.3 | Query switches in fabric with role filter |

### B. Policy Templates Reference

NDFC policy templates used by this project:

| Template Name | Purpose | Used By |
|---------------|---------|---------|
| `switch_user` | NDFC discovery user credentials | 1.1-create-discovery-user |
| `feature_lacp` | Enable LACP feature | 1.2-provision-features |
| `feature_lldp` | Enable LLDP feature | 1.2-provision-features |
| `feature_interface_vlan_11_1` | Enable interface-vlan feature | 1.2-provision-features |
| `feature_tacacs` | Enable TACACS+ feature | 1.2-provision-features |
| `feature_nxapi` | Enable NX-API feature | 1.2-provision-features |
| `feature_vpc` | Enable VPC feature | 1.2-provision-features |
| `create_vlan` | Create VLAN | 1.5-provision-vlan-policies |
| `static_route_v4_v6` | Static route configuration | 1.6-provision-default-route |
| `int_trunk_host` | Ethernet trunk interface | 1.4-provision-interfaces |
| `int_access_host` | Ethernet access interface | 1.4-provision-interfaces |
| `int_port_channel_trunk_host` | Port-channel trunk interface | 1.4-provision-interfaces |
| `int_vpc_trunk_host` | VPC trunk interface | 1.4-provision-interfaces |
| `int_vlan` | SVI (VLAN interface) | 1.4-provision-interfaces |

### C. Feature Lookup Mapping

Mapping of NX-OS features to NDFC template names (from `templates/feature_lookup.yml`):

| NX-OS Feature | NDFC Template |
|---------------|---------------|
| `lacp` | `feature_lacp` |
| `lldp` | `feature_lldp` |
| `interface-vlan` | `feature_interface_vlan_11_1` |
| `tacacs+` | `feature_tacacs` |
| `nxapi` | `feature_nxapi` |
| `vpc` | `feature_vpc` |
| `hsrp` | `feature_hsrp` |
| `ospf` | `feature_ospf` |
| `bgp` | `feature_bgp` |
| `pim` | `feature_pim` |

---

## License

MIT License

## Authors

- Russell Johnston (rujohns2@cisco.com)
- Igor Manassypov (imanassy@cisco.com)
