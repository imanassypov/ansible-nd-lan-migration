# Copilot Instructions: Ansible DC LAN Migration

## Project Overview

Ansible automation for migrating Cisco NX-OS switches from CLI-based management to **Nexus Dashboard Fabric Controller (NDFC)**, plus pre-provisioning new access switches via POAP.

## Architecture

### Three Workflows
```
playbooks/
├── discovery/                  # Profile existing switches → generates fabrics/<fabric>/*.yml
├── provision-fabric/           # Create NDFC fabric definitions
└── provision-switch/           # Pre-provision + deploy configs (1.0-1.8)
    └── 0.0-full-provision-switch.yml  # Master orchestration playbook
```

### Provisioning Sequence (1.0-1.8)
Run `0.0-full-provision-switch.yml` for full workflow, or individual playbooks:
1. **1.0** Pre-provision switches (POAP API) → 2. **1.1** Discovery user → 3. **1.2** Features
4. **1.3** VPC domain (aggregation only) → 5. **1.4** Interfaces (L2/L3/VPC/SVI)
6. **1.5** VLAN policies → 7. **1.6** Default route → 8. **1.7** POAP status → 9. **1.8** Bootstrap

### Data Flow
- **Source of truth**: [inventory/host_vars/nexus_dashboard/fabric_definitions.yml](inventory/host_vars/nexus_dashboard/fabric_definitions.yml) (fabrics + VPC domains)
- **Generated artifacts**: `fabrics/<fabric>/` (vlan_database.yml, l2_interfaces.yml, etc.) - created by discovery playbook
- **Templates**: `templates/*.j2` transform variables → NDFC API JSON payloads

## Connection Patterns (Critical!)

| Target | Connection | Collection | Credentials |
|--------|------------|------------|-------------|
| NX-OS Switches | `network_cli` (SSH) | `cisco.nxos` | `vault_switch_password` |
| Nexus Dashboard | `httpapi` (REST) | `cisco.nd`, `cisco.dcnm` | `vault_nd_password` |

**Never mix connection types** - playbooks targeting ND use `hosts: nexus_dashboard`, switches use `hosts: switches`.

## Development Workflow

```bash
# Setup (uses UV, never pip)
uv sync && source .venv/bin/activate
ansible-galaxy collection install -r requirements.yml

# Vault
echo "password" > .vault_pass
ansible-vault edit inventory/group_vars/all/vault.yml

# Run provisioning
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml
```

## Key Conventions

### Switch Inventory Structure
Switches in [inventory/hosts.yml](inventory/hosts.yml) require:
```yaml
mgmt-acc01:
  ansible_host: 198.18.24.81
  fabric: mgmt-fabric              # Required: maps to fabric_definitions
  role: access                     # Required: access|aggregation
  add_to_fabric: true              # Include in provisioning
  destination_switch_sn: ABC123    # NEW switch serial (for POAP)
```

### Interface Naming (NDFC format)
- `port-channel113` → `vpc113` for VPC interfaces
- `Ethernet1/4` → `e1/4` for member interfaces
- Feature mapping: `templates/feature_lookup.yml` (NX-OS feature → NDFC template)

### Idempotency Pattern
All playbooks query NDFC for existing resources before creating - safe to re-run.

## Modules Used

| Module | Purpose | Example Playbook |
|--------|---------|------------------|
| `cisco.nd.nd_rest` | Raw ND REST API calls | 1.0-preprovision |
| `cisco.dcnm.dcnm_vpc_pair` | VPC domain config | 1.3-deploy-vpc-domain |
| `cisco.dcnm.dcnm_interface` | Interface provisioning | 1.4-provision-interfaces |
| `cisco.nxos.nxos_facts` | Switch discovery | discovery/1.0-profile |

## Testing

```bash
ansible-playbook <playbook> --check   # Dry-run
ansible-playbook <playbook> -v        # Verbose
ansible-lint playbooks/**/*.yml       # Lint
```

## Pitfalls
- **Timeouts**: NDFC is slow; `ansible_command_timeout: 1000` in [connection.yml](inventory/group_vars/nd/connection.yml)
- **Python 3.13+** required per pyproject.toml
- **Fabric directory**: `fabrics/<fabric>/` created by discovery playbook, not manually
