# Copilot Instructions: Ansible DC LAN Migration

## Project Overview

This is an **Ansible automation project** for migrating Cisco NX-OS switches from CLI-based management to **Nexus Dashboard Fabric Controller (NDFC)**. The workflow is **profile → configure → deploy** across 6 sequential numbered playbooks.

## Critical Architecture Understanding

### Sequential Workflow (Must Execute in Order)
1. **Profile** existing switches → Extract configs to `fabrics/<fabric>/` directory
2. **Configure** ND fabric via REST API → Create fabric definitions  
3. **Add** switches to fabric → Register switches with NDFC
4. **Deploy** VLANs → Push VLAN policies
5. **Configure** VPC domains → Establish peer-links
6. **Deploy** interfaces → L2/L3/VPC interface configurations

**Key Pattern**: Each playbook generates/consumes YAML inventory files in `fabrics/<fabric>/` (e.g., `switch_migration_list.csv`, `vlan_database.yml`, `l3_interfaces.yml`). These files are **generated artifacts**, not source files.

### Fabric-Centric Organization
- Multi-fabric support via `fabric_definitions.yml` 
- Each fabric gets isolated directory: `fabrics/<fabric_name>/`
- Fabrics defined in `inventory/host_vars/nexus_dashboard/fabric_definitions.yml`
- VPC domains also defined per-fabric in same file

## Connection Patterns

### Two Connection Types (Critical!)
1. **NX-OS Switches**: `network_cli` connection via SSH
   - Uses `cisco.nxos` collection
   - Credentials: `vault_switch_password` 
   - Connection vars in `inventory/hosts.yml` under `switches` group

2. **Nexus Dashboard**: `httpapi` connection via REST API  
   - Uses `cisco.nd` collection
   - Credentials: `vault_nd_password`
   - Connection vars in `inventory/group_vars/nd/connection.yml`

**Never mix these connection types** - they require different modules and authentication patterns.

## Development Workflow

### Environment Setup (UV-based)
```bash
uv sync                              # Install deps from pyproject.toml
source .venv/bin/activate            # Activate venv
ansible-galaxy collection install -r requirements.yml
```

**Never use pip directly** - this project uses `uv` for fast, reproducible Python environment management.

### Vault Management
```bash
echo "password" > .vault_pass        # Create vault password file (gitignored)
ansible-vault edit inventory/group_vars/all/vault.yml  # Edit encrypted credentials
```

Vault file stores: `vault_switch_password`, `vault_nd_password`. Configured in `ansible.cfg` as `vault_password_file = .vault_pass`.

### Running Playbooks
```bash
# Full migration sequence
ansible-playbook playbooks/01-profile-existing-switches.yml
ansible-playbook playbooks/02-configure-nd-fabric.yml
# ... through 06

# Selective execution via tags
ansible-playbook playbooks/01-profile-existing-switches.yml --tags profile-vlans
ansible-playbook playbooks/06-configure-interfaces.yml --tags deploy-vpc-interfaces
```

Common tags: `profile-switches`, `profile-vlans`, `profile-l2-interfaces`, `profile-l3-interfaces`, `deploy-l2-interfaces`, `deploy-l3-interfaces`, `deploy-vpc-interfaces`

## Project-Specific Conventions

### Interface Naming Transformation
- **Port-channels in VPC**: `port-channel10` → `vpc10` (VPC interfaces use `vpc` prefix in NDFC)
- **Interface modes**: SVIs=`vlan`, loopbacks=`lo`, physical/port-channel=`routed`

### Interface Exclusions (Hardcoded)
Playbook `01-profile-existing-switches.yml` **excludes** from profiling:
- `mgmt0` (management interface)
- `Vlan1` (default VLAN)  
- VPC peer-link interfaces
- Port-channel member interfaces (only parent port-channel is profiled)

### Jinja2 Template Pattern
Templates in `templates/*.j2` transform Ansible variables → NDFC API JSON:
- **Input**: Ansible host_vars/inventory variables
- **Output**: JSON payloads for `cisco.nd.nd_rest` module
- **Example**: `create_fabric.json.j2` converts `fabric_definitions.yml` → ND Fabrics API format

Key template: `create_fabric.json.j2` - shows conditional logic for Classic LAN vs VXLAN fabric types.

## Critical Files Reference

- **[inventory/hosts.yml](inventory/hosts.yml)**: Defines switch inventory with `fabric`, `role`, `migrate` attributes
- **[inventory/host_vars/nexus_dashboard/fabric_definitions.yml](inventory/host_vars/nexus_dashboard/fabric_definitions.yml)**: Source of truth for fabric configs and VPC domains
- **[playbooks/01-profile-existing-switches.yml](playbooks/01-profile-existing-switches.yml)**: Most complex - 768 lines, profiles all switch configs
- **[templates/create_fabric.json.j2](templates/create_fabric.json.j2)**: Reference for NDFC API JSON structure

## Common Pitfalls

1. **Playbook order matters** - Running out of sequence causes failures (e.g., can't deploy VLANs before fabric exists)
2. **Fabric directory missing** - `fabrics/<fabric>/` created by playbook 01, doesn't exist initially
3. **API timeouts** - NDFC operations are slow; `ansible_command_timeout: 1000` set in `connection.yml`
4. **Idempotency** - Playbook 02 checks existing fabrics before creating (prevents duplicate errors)
5. **Python version** - Requires Python 3.13+ per `pyproject.toml`

## Integration Points

- **Cisco Collections**: `cisco.nd` (ND REST API), `cisco.dcnm` (DCNM/NDFC modules), `cisco.nxos` (NX-OS modules)
- **PyATS/Genie**: Listed in dependencies for advanced network testing (not actively used in current playbooks)
- **Ansible Lint**: Pre-configured in `pyproject.toml` for linting playbooks

## When Modifying Code

- **Adding new fabric types**: Update conditional logic in `create_fabric.json.j2` for fabric-type-specific parameters
- **New interface types**: Extend filtering logic in playbook 01 tasks (search for `when:` conditions on interface names)
- **API changes**: Check `cisco.nd.nd_rest` module calls - all use explicit `path` parameter with ND API endpoints
- **Inventory structure**: Switches must have `fabric` and `role` attributes defined in `hosts.yml`

## Testing Commands

```bash
ansible-playbook <playbook> --check           # Dry-run mode
ansible-playbook <playbook> --list-tasks      # Show task list
ansible-playbook <playbook> -v                # Verbose output
ansible-lint playbooks/*.yml                  # Lint all playbooks
```

Check generated files in `fabrics/<fabric>/` after profiling to validate data extraction before deployment.
