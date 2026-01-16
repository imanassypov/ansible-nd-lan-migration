# Copilot Instructions: Ansible DC LAN Migration

## Architecture Overview

Ansible automation migrating Cisco NX-OS switches from CLI to **Nexus Dashboard Fabric Controller (NDFC)**, plus POAP pre-provisioning for new switches.

### Data Flow (Critical to Understand)
```
1. inventory/hosts.yml                    # Defines switches with fabric, role, add_to_fabric
2. inventory/host_vars/nexus_dashboard/
   └── fabric_definitions.yml             # Source of truth: nd_fabrics[], vpc_domains[]
3. playbooks/discovery/1.0-profile*       # SSH → switches → generates fabrics/<fabric>/*.yml
4. fabrics/<fabric>/                      # Generated: l2_interfaces.yml, vlan_database.yml, etc.
5. templates/*.j2                         # Transform YAML → NDFC REST API JSON payloads
6. playbooks/provision-switch/1.x-*       # Deploy via NDFC httpapi
```

### Workflow Sequence (0.0 runs all)
| Step | Playbook | Purpose | Target |
|------|----------|---------|--------|
| 1.0 | provision-switches | POAP pre-provision or discover existing | NDFC |
| 1.1 | create-discovery-user | NDFC switch auth user | NDFC |
| 1.2 | provision-features | NX-OS features via `feature_lookup.yml` | NDFC |
| 1.3 | deploy-vpc-domain | VPC peer-link (aggregation only) | NDFC |
| 1.4 | provision-interfaces | L2/L3/VPC/SVI via `dcnm_interface` | NDFC |
| 1.5 | provision-vlan-policies | VLAN database | NDFC |
| 1.6 | provision-default-route | Static routes | NDFC |
| 1.7 | check-poap-status | Query POAP readiness | NDFC |
| 1.8 | bootstrap-switches | Deploy Day-0 config | NDFC |

## Connection Patterns (NEVER Mix!)

| Target | Connection | Collection | `hosts:` value |
|--------|------------|------------|----------------|
| NX-OS Switches | `ansible.netcommon.network_cli` | `cisco.nxos` | `switches` |
| Nexus Dashboard | `ansible.netcommon.httpapi` | `cisco.nd`, `cisco.dcnm` | `nexus_dashboard` |

Credentials: `vault_switch_password` (switches), `vault_nd_password` (ND) in `inventory/group_vars/all/vault.yml`

## Development Commands

```bash
# Setup (UV only, never pip)
uv sync && source .venv/bin/activate
ansible-galaxy collection install -r requirements.yml

# Vault
echo "password" > .vault_pass
ansible-vault edit inventory/group_vars/all/vault.yml

# Run with tags
ansible-playbook playbooks/provision-switch/1.4-provision-interfaces.yml --tags deploy-vpc-interfaces
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml -v
```

## Key Patterns

### Switch Inventory Structure (hosts.yml)
```yaml
switch_name:
  ansible_host: 198.18.24.81
  fabric: mgmt-fabric              # Must match nd_fabrics[].FABRIC_NAME
  role: access                     # access | aggregation
  add_to_fabric: true              # Include in provisioning
  mgmt_int: Vlan199                # Management interface
  # POAP pre-provision (new switches only):
  destination_switch_sn: ABC123
  destination_switch_model: N9K-C9300v
  destination_switch_version: "10.6(1)"
```

### Interface Naming Transforms (templates)
```jinja2
{# NX-OS → NDFC dcnm_interface format #}
port-channel113 → vpc113           {# VPC interfaces #}
Ethernet1/4 → e1/4                 {# regex_replace('^Ethernet', 'e') #}
```

### Common Task Pattern (filter switches by add_to_fabric)
```yaml
- name: Build list of switches to provision
  set_fact:
    switches_to_provision: >-
      {{ groups['switches'] | map('extract', hostvars)
         | selectattr('add_to_fabric', 'defined')
         | selectattr('add_to_fabric', 'equalto', true) | list }}
```

### Template → JSON → API Pattern
Templates output JSON for `cisco.nd.nd_rest` or structured data for `cisco.dcnm.*` modules:
- `1.0-preprovision-new-switches.j2` → JSON array for POAP API
- `1.4-provision-interfaces-*.j2` → config list for `dcnm_interface`

## Modules Reference

| Module | Use Case | State |
|--------|----------|-------|
| `cisco.nd.nd_rest` | Raw NDFC REST API (POAP, policies) | — |
| `cisco.dcnm.dcnm_interface` | Interface config | `replaced` (idempotent) |
| `cisco.dcnm.dcnm_vpc_pair` | VPC domain config | `merged` |
| `cisco.nxos.nxos_facts` | Discovery via SSH | — |

## Pitfalls & Notes

- **Timeouts**: NDFC is slow → `ansible_command_timeout: 1000` in `inventory/group_vars/nd/connection.yml`
- **Python 3.13+** required (pyproject.toml)
- **Fabric directories**: `fabrics/<fabric>/` created by discovery playbook, never manually
- **VPC ID 1**: Skipped in templates (reserved for peer-link managed by VPC domain)
- **Gateway format**: POAP requires prefix length (e.g., `198.18.24.65/26`)
- **Feature mapping**: `templates/feature_lookup.yml` maps NX-OS features → NDFC template names
