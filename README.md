# Ansible DC LAN Migration

Automated migration tooling for Cisco NX-OS switches from CLI-based management to Nexus Dashboard Fabric Controller (NDFC). This project provides complete workflows to:
- **Profile** existing switch configurations
- **Migrate** switches to centralized NDFC management
- **Pre-provision** new access switches before physical deployment

## Overview

This project implements two NDFC onboarding workflows, automatically selected per-switch based on inventory configuration:

### Pre-provision + Bootstrap Workflow (New / Greenfield Switches)

For switches **not yet powered on**, identified by having `destination_switch_sn`, `destination_switch_model`, and `destination_switch_version` defined in `inventory/hosts.yml`. This is a two-stage POAP-based pipeline:

| Stage | Playbook | What Happens |
|-------|----------|--------------|
| **Pre-provision** | `1.0-provision-switches.yml` (tag: `preprovision-switches`) | Registers the switch serial number, model, IP, role, and gateway with NDFC using `cisco.dcnm.dcnm_inventory` POAP payloads — creating a placeholder *before* the switch boots. |
| **Configure** | `1.1` – `1.7` | Provisions features, VPC domains, VLANs, interfaces, VRFs, and default routes in NDFC so policies are ready ahead of time. |
| **Wait for POAP** | `1.8-check-poap-status.yml` | Polls the POAP inventory to confirm the physical switch has booted and contacted NDFC. |
| **Bootstrap** | `1.9-bootstrap-switches.yml` | Re-POSTs to the POAP API with `"reAdd": true`, pushing the switch's SSH fingerprint, public key, and Day-0 CLI config (port-channels, member interfaces) to complete onboarding. |

### Discovery Workflow (Existing / Brownfield Switches)

For switches **already online and reachable via SSH**, identified by the *absence* of `destination_switch_sn` in inventory:

| Stage | Playbook | What Happens |
|-------|----------|--------------|
| **Profile** | `discovery/1.0-profile-existing-switches.yml` | SSHes into each switch to extract running configs into `fabrics/<fabric>/*.yml`. |
| **Discover + Assign Role** | `1.0-provision-switches.yml` (tag: `discover-switches`) | Imports switches and assigns roles in one module workflow via `cisco.dcnm.dcnm_inventory` using SSH credentials with `preserve_config: true`. |
| **Configure** | `1.1` – `1.7` | Applies the same feature, VLAN, interface, VRF, and routing policies as the greenfield path. |

### How the Decision Is Made

The routing logic lives in `1.0-provision-switches.yml`. A single filter splits `switches_to_preprovision` into two lists:

```
inventory/hosts.yml switch entry
        │
        ├─ destination_switch_sn defined? ──► YES ──► POAP Pre-provision → Bootstrap
        │
        └─ not defined? ───────────────────► NO  ──► SSH Discovery → Role Assignment
```

| Switch Type | Inventory Markers | Onboarding Path | Key Playbooks |
|---|---|---|---|
| **New (greenfield)** | `destination_switch_sn`, `destination_switch_model`, `destination_switch_version` | Pre-provision → 1.1–1.7 → POAP check → Bootstrap | `1.0` → `1.8` → `1.9` |
| **Existing (brownfield)** | No serial number fields | Discovery (SSH import) → Role assignment → 1.1–1.6 | `1.0` (discover) → `1.1`–`1.6` |

> **Note:** This deployment assumes **inband switch management**, which requires **Nexus Dashboard 4.1.1** or later. Switches must be reachable from Nexus Dashboard to their respective loopback management addresses for discovery.

---

## Quick Start

```bash
# 1. Clone and setup environment
git clone <repository-url>
cd ansible-dc-lan-migration
uv sync && source .venv/bin/activate
ansible-galaxy collection install -r requirements.yml

# 2. Configure inventory (copy examples and customize)
cp -r inventory.example inventory
echo "your-password" > .vault_pass
ansible-vault edit inventory/group_vars/all/vault.yml

# 3. Run provisioning playbooks in sequence
ansible-playbook playbooks/provision-switch/1.0-provision-switches.yml
ansible-playbook playbooks/provision-switch/1.1-create-discovery-user.yml
# ... continue with 1.2 through 1.9
```

---

## Project Structure

```
ansible-dc-lan-migration/
├── fabrics/                                    # Generated artifacts per fabric (gitignored)
│   └── <fabric-name>/
│       ├── switch_details.yml                  # Switch hardware info (serial, model, version)
│       ├── switch_features.yml                 # Enabled NX-OS features
│       ├── vlan_database.yml                   # VLAN configurations
│       ├── l2_interfaces.yml                   # L2 interface configs
│       ├── l2_vpc_interfaces.yml               # VPC interface configs
│       ├── l3_interfaces.yml                   # L3 interface configs (SVIs, loopbacks, routed)
│       └── static_routes.yml                   # Static route configurations
│
├── inventory/                                  # Actual inventory (gitignored - contains secrets)
│   ├── hosts.yml                               # Switch and ND host definitions
│   ├── group_vars/
│   │   ├── all/vault.yml                       # Encrypted credentials
│   │   └── nd/connection.yml                   # ND API settings
│   └── host_vars/nexus_dashboard/
│       └── fabric_definitions.yml              # Fabric source of truth
│
├── inventory.example/                          # Example inventory templates (copy to inventory/)
│   ├── hosts.yml
│   ├── group_vars/
│   │   ├── all/vault.yml
│   │   └── nd/connection.yml
│   └── host_vars/nexus_dashboard/
│       └── fabric_definitions.yml
│
├── playbooks/
│   ├── discovery/                              # Profile existing switches
│   │   └── 1.0-profile-existing-switches.yml
│   ├── provision-fabric/                       # Fabric configuration
│   │   └── 1.0-provision-nd-fabrics.yml
│   └── provision-switch/                       # Switch provisioning workflow
│       ├── 1.0-provision-switches.yml          # Add switches to NDFC (POAP or Discovery)
│       ├── 1.1-create-discovery-user.yml
│       ├── 1.2-provision-features.yml
│       ├── 1.3-deploy-vpc-domain.yml
│       ├── 1.4-provision-vlan-policies.yml
│       ├── 1.5-provision-interfaces.yml
│       ├── 1.6-provision-vrf.yml
│       ├── 1.7-provision-static-routes.yml
│       ├── 1.8-check-poap-status.yml
│       └── 1.9-bootstrap-switches.yml
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

Run playbooks individually in sequence (1.0 → 1.8). For POAP workflows, run 1.0-1.6 first, then wait for switches to boot before running 1.7-1.8.

| # | Playbook | Template(s) | Description |
|---|----------|-------------|-------------|
| 1.0 | `provision-switches.yml` | Inline Jinja2 | Adds switches to NDFC using `cisco.dcnm.dcnm_inventory` (POAP pre-provision + discovery/role merge) |
| 1.1 | `create-discovery-user.yml` | `1.1-create-discovery-user.j2` | Create NDFC discovery user (switch_user policy) for switch authentication during discovery |
| 1.2 | `provision-features.yml` | `1.2-provision-features.j2` | Configure NX-OS feature policies (LACP, LLDP, interface-vlan, etc.) using 1.2-provision-features-feature_lookup.yml mapping |
| 1.3 | `deploy-vpc-domain.yml` | `1.3-deploy-vpc-domain.json.j2` | Deploy VPC domain configuration between aggregation switch pairs |
| 1.4 | `provision-vlan-policies.yml` | Inline (`create_vlan` policy) | Deploy VLAN policies from vlan_database.yml to switches via `cisco.dcnm.dcnm_policy` |
| 1.5 | `provision-interfaces.yml` | `1.5-provision-interfaces-*.j2` | Configure L2/L3 interfaces (Ethernet, port-channels, VPC, SVI) via `cisco.dcnm.dcnm_interface` |
| 1.6 | `provision-vrf.yml` | — | Configure VRF definitions on switches via `cisco.dcnm.dcnm_vrf` (skipped if no VRFs profiled) |
| 1.7 | `provision-static-routes.yml` | Inline (`static_route_v4_v6` policy) | Configure static default route (0.0.0.0/0) via management gateway using `cisco.dcnm.dcnm_policy` |
| 1.8 | `check-poap-status.yml` | — | Query POAP inventory to check if switches have connected and are ready for bootstrap |
| 1.9 | `bootstrap-switches.yml` | `1.9-bootstrap-switches.j2` | Bootstrap pre-provisioned switches via POAP API to deploy Day-0 configuration |

### How Switches Are Added to NDFC

The `1.0-provision-switches.yml` playbook automatically determines how to add each switch based on inventory configuration:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     SWITCH PROVISIONING DECISION FLOW                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   Does the switch have destination_switch_sn, destination_switch_model,    │
│   AND destination_switch_version defined in hosts.yml?                      │
│                                                                             │
│                    YES                              NO                      │
│                     │                               │                       │
│                     ▼                               ▼                       │
│   ┌─────────────────────────────┐   ┌─────────────────────────────┐        │
│   │     POAP PRE-PROVISION      │   │    DISCOVERY (SSH-BASED)    │        │
│   ├─────────────────────────────┤   ├─────────────────────────────┤        │
│   │ For NEW switches not yet    │   │ For EXISTING switches       │        │
│   │ powered on or connected.    │   │ already online.             │        │
│   │                             │   │                             │        │
│   │ • Registers serial number   │   │ • Connects via SSH          │        │
│   │   with NDFC before boot     │   │ • Imports running config    │        │
│   │ • Role assigned during      │   │ • Role assigned via API     │        │
│   │   pre-provisioning ✓        │   │   after discovery           │        │
│   │ • Gateway configured for    │   │                             │        │
│   │   POAP bootstrap            │   │                             │        │
│   └─────────────────────────────┘   └─────────────────────────────┘        │
│                                                                             │
│   Example:                          Example:                                │
│   ┌─────────────────────────────┐   ┌─────────────────────────────┐        │
│   │ leaf01:                     │   │ agg01:                      │        │
│   │   ansible_host: 198.18.24.82│   │   ansible_host: 198.18.24.66│        │
│   │   role: access              │   │   role: aggregation         │        │
│   │   destination_switch_sn:    │   │   add_to_fabric: true       │        │
│   │     91E5LEGJBAA             │   │   # No destination_switch_* │        │
│   │   destination_switch_model: │   │   # = Discovery mode        │        │
│   │     N9K-C9300v              │   │                             │        │
│   │   destination_switch_version│   │                             │        │
│   │     "10.6(1)"               │   │                             │        │
│   └─────────────────────────────┘   └─────────────────────────────┘        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Key Point for Operators**: Switch roles (access, aggregation, etc.) are handled automatically:
> - **POAP switches**: Role is set when pre-provisioning, no additional API call needed
> - **Discovery switches**: Role is assigned via NDFC API after the switch is discovered

### Discovery Workflow (discovery/)

| Playbook | Template(s) | Description |
|----------|-------------|-------------|
| `1.0-profile-existing-switches.yml` | `1.0-profile-existing-switches-switch_features.j2`, `1.0-profile-existing-switches-vlan_database.j2`, `1.0-profile-existing-switches-interfaces_inventory.j2`, `1.0-profile-existing-switches-vpc_inventory.j2`, `1.0-profile-existing-switches-static_routes.j2` | Profile existing switches via SSH to extract configurations into YAML files |

### Fabric Provisioning (provision-fabric/)

| Playbook | Template(s) | Description |
|----------|-------------|-------------|
| `1.0-provision-nd-fabrics.yml` | `1.0-configure-nd-fabric-enhanced.j2` | Create and update fabric definitions in NDFC. `classicLan` via `cisco.dcnm.dcnm_fabric`; `enhancedLan` via REST API (`POST`/`PUT /api/v1/manage/fabrics`) |

---

## Provisioning Workflow

### Full Automated Provisioning

Run the master playbook to execute all steps:

```bash
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml -v
```

### Step-by-Step Execution

```bash
# 1.0 - Pre-provision/discover switches with NDFC
ansible-playbook playbooks/provision-switch/1.0-provision-switches.yml

# 1.1 - Create discovery user for NDFC authentication
ansible-playbook playbooks/provision-switch/1.1-create-discovery-user.yml

# 1.2 - Configure NX-OS features
ansible-playbook playbooks/provision-switch/1.2-provision-features.yml

# 1.3 - Deploy VPC domain (for aggregation switches)
ansible-playbook playbooks/provision-switch/1.3-deploy-vpc-domain.yml

# 1.4 - Deploy VLAN policies
ansible-playbook playbooks/provision-switch/1.4-provision-vlan-policies.yml

# 1.5 - Configure interfaces (L2, port-channels, VPC, SVI)
ansible-playbook playbooks/provision-switch/1.5-provision-interfaces.yml

# 1.6 - Configure VRFs (if applicable)
ansible-playbook playbooks/provision-switch/1.6-provision-vrf.yml

# 1.7 - Configure default route
ansible-playbook playbooks/provision-switch/1.7-provision-static-routes.yml

# 1.8 - Check if switches connected via POAP
ansible-playbook playbooks/provision-switch/1.8-check-poap-status.yml

# 1.9 - Bootstrap switches to deploy configuration
ansible-playbook playbooks/provision-switch/1.9-bootstrap-switches.yml
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
│  1.4 VLANs            Deploy VLAN policies                              │
│         ↓                                                                │
│  1.5 Interfaces       Configure L2/L3/VPC/SVI interfaces                │
│         ↓                                                                │
│  1.6 VRF              Configure VRF definitions (if any)                │
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
          ansible_host: 198.18.24.81          # Switch management IP
          fabric: mgmt-fabric
          role: access
          add_to_fabric: true                  # Flag to include in provisioning
          mgmt_int: Vlan199                    # Management interface
          # POAP Pre-provisioning (new switches only):
          destination_switch_sn: FDO292012EE
          destination_switch_model: N9K-C9348GC-FX3
          destination_switch_version: "10.6(1)"
```

### POAP Pre-Provisioning Variables (New Switch Migration)

When migrating to a **new physical switch** via POAP (Power On Auto Provisioning), the following three variables are **mandatory** and must be defined together. Omitting any one of these will cause the switch to be skipped during provisioning.

| Variable | Required | Description |
|----------|----------|-------------|
| `destination_switch_sn` | **Yes** | Serial number of the new switch hardware. On **Nexus 9000v** (virtual), use `show license host-id` to obtain the correct serial — this is the value NDFC matches during POAP. On **physical** switches, use `show inventory` or the chassis label. NDFC uses this to uniquely identify and match the switch when it boots and contacts NDFC via POAP. |
| `destination_switch_model` | **Yes** | Hardware model of the new switch (e.g., `N9K-C9348GC-FX3`, `N9K-C93180YC-FX`). Must match the actual hardware model exactly. NDFC validates this against the switch hardware during POAP bootstrap. |
| `destination_switch_version` | **Yes** | Target NX-OS software version the switch will run (e.g., `10.6(1)`, `10.4(3)`). Used by NDFC to validate switch compatibility and optionally apply image policies during bootstrap. |

> **⚠️ Important**: All three `destination_switch_*` variables must be defined together, or none at all.
> - **All three defined** → Switch is pre-provisioned via POAP API for new hardware deployment
> - **None defined** → Switch is discovered via SSH for existing switch migration
> - **Partial definition** → Switch is **skipped** (falls into gap between POAP and Discovery workflows)

#### Example: New Switch (POAP Pre-provisioning)
```yaml
mgmt-acc01:
  ansible_host: 198.18.24.81
  fabric: mgmt-fabric
  role: access
  add_to_fabric: true
  mgmt_int: Vlan199
  destination_switch_sn: FDO292012EE           # Required for POAP
  destination_switch_model: N9K-C9348GC-FX3    # Required for POAP
  destination_switch_version: "10.6(1)"        # Required for POAP
```

#### Example: Existing Switch (Discovery via SSH)
```yaml
mgmt-acc02:
  ansible_host: 198.18.24.82
  fabric: mgmt-fabric
  role: access
  add_to_fabric: true
  mgmt_int: Vlan199
  # No destination_switch_* variables = discovered via SSH
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
- Shared preflight check uses `cisco.nd.nd_version` to validate ND reachability/version before provisioning tasks

---

## POAP Requirements for Aggregation Port-Channels

When configuring VPC port-channels on aggregation switches that connect to POAP-enabled leaf switches, specific LACP and spanning-tree settings are **required** to ensure successful POAP bootstrapping.

### Automated Configuration via Inventory

The `disable_lacp_suspend_individual_po_list` variable in `inventory/hosts.yml` automates the required LACP suspend-individual configuration through NDFC. Add this variable to aggregation switches with a list of VPC IDs that connect to POAP leaf switches:

```yaml
# inventory/hosts.yml
aggegation:
  hosts:
    agg01:
      ansible_host: 198.18.24.12
      role: aggregation
      fabric: mgmt-fabric
      add_to_fabric: true
      mgmt_int: Vlan199
      # DHCP relay servers for management VLAN (for POAP leaf switches)
      mgmt_int_dhcp_relay_list:
        - 198.18.1.100
      # VPC port-channels that connect to POAP leaf switches
      disable_lacp_suspend_individual_po_list:
        - 104
        - 105
      destination_switch_sn: 9S7PWWEGDWW
    agg02:
      ansible_host: 198.18.24.13
      role: aggregation
      fabric: mgmt-fabric
      add_to_fabric: true
      mgmt_int: Vlan199
      # DHCP relay servers for management VLAN (for POAP leaf switches)
      mgmt_int_dhcp_relay_list:
        - 198.18.1.100
      # VPC port-channels that connect to POAP leaf switches
      disable_lacp_suspend_individual_po_list:
        - 104
        - 105
      destination_switch_sn: 9DVWNV7F75Y
```

### POAP Inventory Variables Reference

| Variable | Type | Description |
|----------|------|-------------|
| `mgmt_int` | string | Management interface name (e.g., `Vlan199`). Used to identify the SVI that receives DHCP relay configuration. |
| `mgmt_int_dhcp_relay_list` | list | List of DHCP server IPs to configure as relay addresses on the management SVI. Required for POAP leaf switches to acquire temporary DHCP IP addresses during bootstrap. |
| `disable_lacp_suspend_individual_po_list` | list | List of VPC IDs (integers) that should have `no lacp suspend-individual` configured. Required for VPCs connecting to POAP leaf switches. |

When `1.5-provision-interfaces.yml` runs:
- VPCs in `disable_lacp_suspend_individual_po_list` get `DISABLE_LACP_SUSPEND: true` in NDFC → `no lacp suspend-individual` on switch
- SVIs matching `mgmt_int` get DHCP relay addresses from `mgmt_int_dhcp_relay_list` → `ip dhcp relay address <ip>` on switch

**Debug output example:**
```
Configuring 10 VPC interface(s):
- vpc101: trunk mode, peers 198.18.24.12
- vpc102: trunk mode, peers 198.18.24.12
- vpc103: trunk mode, peers 198.18.24.12
- vpc104: trunk mode, peers 198.18.24.12, POAP support (suspend-individual disabled)
- vpc105: trunk mode, peers 198.18.24.12, POAP support (suspend-individual disabled)
...
```

> **Post-POAP Cleanup**: Once all downstream leaf switches have completed POAP bootstrapping and their port-channels are operational, you can remove `disable_lacp_suspend_individual_po_list` and `mgmt_int_dhcp_relay_list` from the aggregation switches, then re-run `1.5-provision-interfaces.yml` to restore default settings.

### Why This is Required

During POAP, the leaf switch boots with no configuration — LACP is not yet enabled on its interfaces. The aggregation switch's port-channel member ports must remain active individually to allow:

1. **DHCP Discovery**: The leaf switch sends DHCP requests from its physical interface (not a port-channel)
2. **POAP Script Download**: Configuration scripts are downloaded before LACP is configured
3. **STP Convergence**: BPDUs flow through member interfaces before the port-channel forms

Without `no lacp suspend-individual`, the aggregation switch suspends its member ports when no LACP PDUs are received, blocking all traffic from the booting leaf switch.

### Required Port-Channel Configuration

```cisco
interface port-channel <id>
  no lacp suspend-individual
  spanning-tree port type normal
  spanning-tree bpduguard disable
```

### Configuration Rationale

| Configuration | Why Required |
|---------------|--------------|
| `no lacp suspend-individual` | Prevents LACP from suspending individual member ports when the port-channel is down. During POAP, the leaf switch does not yet have LACP configured, so member ports operate individually. This allows DHCP and STP BPDUs to flow through member interfaces before the port-channel forms. |
| `spanning-tree port type normal` | Disables Bridge Assurance on the port-channel. POAP switches boot with default STP settings (Bridge Assurance enabled), but pre-configured aggregation switches may have Bridge Assurance disabled. Mismatched Bridge Assurance settings cause `TYPE_Inc` (Type Inconsistent) errors, blocking all uplinks and preventing POAP from completing. |
| `spanning-tree bpduguard disable` | Prevents BPDUGuard from shutting down the port if BPDUs are received. During POAP, the leaf switch may send BPDUs as it converges STP topology before receiving its final configuration. |

### Symptom: POAP Failure Due to STP TYPE_Inc

If aggregation port-channels are missing these configurations, POAP switches will exhibit:

```
switch# show spanning-tree vlan 1
VLAN0001
  Spanning tree enabled protocol rstp
  Root ID    Priority    32769
             Address     xxxx.xxxx.xxxx
             This bridge is the root

Interface        Role Sts Cost      Prio.Nbr Type
---------------- ---- --- --------- -------- --------------------------------
Eth1/49          Desg BKN*4         128.49   P2p *TYPE_Inc
Eth1/50          Desg BKN*4         128.50   P2p *TYPE_Inc
```

**Impact**: All uplinks blocked → POAP script cannot download configuration from NDFC → switch stuck in POAP mode.

### Resolution

Apply the required configuration to **all VPC port-channels** on aggregation switches that connect to POAP leaf switches:

```bash
# On both aggregation switches (agg01, agg02)
configure terminal
interface port-channel 113
  no lacp suspend-individual
  spanning-tree port type normal
  spanning-tree bpduguard disable
interface port-channel 114
  no lacp suspend-individual
  spanning-tree port type normal
  spanning-tree bpduguard disable
end
copy running-config startup-config
```

After applying, POAP switches should converge STP with one uplink as `Root FWD` and successfully download configuration from NDFC.

---

## POAP MTU Requirements

> **⚠️ Important**: The native VLAN used for POAP (configured with DHCP helper) **must** have a default MTU of **1500 bytes**.

### Issue

POAP bootstrapping may fail if the native VLAN on aggregation switch uplinks is configured with jumbo MTU (e.g., 9216). During POAP, the new switch boots with default MTU settings (1500) and cannot properly communicate with the DHCP server or NDFC if there is an MTU mismatch on the path.

### Symptoms

- POAP switch fails to obtain DHCP lease
- POAP script download fails or times out
- Intermittent connectivity during bootstrap phase
- Large packets (configuration payloads) fail while small packets (ICMP ping) succeed

### Resolution

Ensure the native VLAN SVI on aggregation switches uses default MTU:

```cisco
interface Vlan199
  description POAP Native VLAN - DHCP Helper
  ip address 198.18.24.65/26
  ip dhcp relay address <dhcp-server-ip>
  no ip redirects
  ! Do NOT configure jumbo MTU on this VLAN
  ! MTU must remain at default 1500 for POAP compatibility
```

> **Note**: Jumbo MTU (9216) is appropriate for data VLANs carrying production traffic, but the POAP/management native VLAN should always use standard 1500 MTU to ensure compatibility with switches during initial bootstrap.

---

## Troubleshooting

### Common Commands

```bash
# Dry-run mode
ansible-playbook playbooks/provision-switch/1.0-provision-switches.yml --check

# Verbose output
ansible-playbook playbooks/provision-switch/0.0-full-provision-switch.yml -vvv

# List tasks
ansible-playbook playbooks/provision-switch/1.5-provision-interfaces.yml --list-tasks

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

## Caveats & Known Issues

### POAP Failure on Certain NX-OS Versions (CSCwm11715)

A known Cisco defect ([CSCwm11715](https://bst.cloudapps.cisco.com/bugsearch/bug/CSCwm11715)) prevents POAP from completing successfully on affected NX-OS releases. Switches hit by this bug will contact NDFC during POAP but fail to finish the bootstrap process — they may loop indefinitely or remain stuck in a pre-provisioned state.

**Impact on this project**: The pre-provision + bootstrap workflow (`1.0` → `1.7` → `1.8`) will fail at the bootstrap stage for switches running an affected NX-OS version. The `1.7-check-poap-status.yml` playbook may show the switch as connected, but `1.8-bootstrap-switches.yml` will not complete successfully.

**Workaround**: Upgrade or downgrade the target switch to a NX-OS version that includes the fix for CSCwm11715 before attempting POAP onboarding. Verify the fixed-in version on the [bug details page](https://bst.cloudapps.cisco.com/bugsearch/bug/CSCwm11715). Ensure the `destination_switch_version` in `inventory/hosts.yml` matches the patched image loaded on the switch.

### DHCP Relay Must Point to Nexus Dashboard Permanent IPs for POAP

> **Important**: When configuring DHCP relay on the aggregation/upstream switch for POAP, the relay destination **must** be the permanent (data) IP addresses of the individual Nexus Dashboard nodes — not the cluster virtual IP (VIP) or management IP. NDFC's built-in DHCP server for POAP listens on the node-level permanent IPs. If the relay points to the cluster VIP, POAP DHCP requests will not receive a response and new switches will fail to bootstrap.
>
> On the aggregation switch (or layer 3 gateway for the POAP VLAN):
> ```
> interface Vlan199
>   ip dhcp relay address <ND-node-1-permanent-IP>
>   ip dhcp relay address <ND-node-2-permanent-IP>
>   ip dhcp relay address <ND-node-3-permanent-IP>
> ```
> Verify the permanent IPs in the Nexus Dashboard UI under **Admin Console → Infrastructure → Cluster Configuration**.

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
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/fabrics/{fabric}/inventory/poap` | POST | 1.9 | Bootstrap switch via POAP |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/policies/switches/{serial}` | GET | 1.2, 1.4, 1.7 | Query existing policies for a switch (idempotency check) |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/control/policies/bulk-create` | POST | 1.1, 1.2, 1.4, 1.7 | Create switch policies via `cisco.dcnm.dcnm_policy` (features, VLANs, routes, users) |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/vpcpair` | GET | 1.3 | Query existing VPC pairs |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/vpcpair` | POST | 1.3 | Create VPC domain pair |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/vpcpair` | DELETE | 1.3 | Delete VPC pair (cleanup) |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/interface/detail?serialNumber={serial}` | GET | 1.5 | Query existing interfaces on a switch |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/interface?serialNumber={serial}` | GET | 1.5 | Query interface summary for a switch |
| `/appcenter/cisco/ndfc/api/v1/lan-fabric/rest/globalInterface` | POST | 1.5 | Create/configure interfaces (L2, L3, VPC, SVI) via `cisco.dcnm.dcnm_interface` |
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
| `create_vlan` | Create VLAN | 1.4-provision-vlan-policies |
| `static_route_v4_v6` | Static route configuration | 1.7-provision-static-routes |
| `int_trunk_host` | Ethernet trunk interface | 1.5-provision-interfaces |
| `int_access_host` | Ethernet access interface | 1.5-provision-interfaces |
| `int_port_channel_trunk_host` | Port-channel trunk interface | 1.5-provision-interfaces |
| `int_port_channel_access_host` | Port-channel access interface | 1.5-provision-interfaces |
| `int_port_channel_trunk_member_11_1` | Port-channel trunk member (auto-assigned by NDFC) | 1.5-provision-interfaces |
| `int_vpc_trunk_host` | VPC trunk interface | 1.5-provision-interfaces |
| `int_vpc_access_host` | VPC access interface | 1.5-provision-interfaces |
| `int_vlan` | SVI (VLAN interface) | 1.5-provision-interfaces |

### C. Feature Lookup Mapping

Mapping of NX-OS features to NDFC template names (from `templates/1.2-provision-features-feature_lookup.yml`):

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
