#!/bin/bash
#==============================================================================
# Script: dry-run-ndfc-api.sh
# Purpose: Run NDFC playbook in dry-run mode and extract only API calls
#
# Usage:
#   ./scripts/dry-run-ndfc-api.sh <playbook-path> [output-file]
#
# Examples:
#   ./scripts/dry-run-ndfc-api.sh playbooks/provision-switch/1.1-create-discovery-user.yml
#   ./scripts/dry-run-ndfc-api.sh playbooks/provision-switch/1.4-provision-interfaces.yml my-output.log
#
# Output:
#   Shows only NDFC API calls with:
#   - HTTP method (POST/GET/PUT/DELETE)
#   - API endpoint path
#   - JSON payload
#==============================================================================

set -e

PLAYBOOK="${1:?Usage: $0 <playbook-path> [output-file]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Generate default output filename from playbook name
PLAYBOOK_NAME=$(basename "$PLAYBOOK" .yml)
OUTPUT_FILE="${2:-dry-run-${PLAYBOOK_NAME}-api-$(date +%Y%m%d-%H%M%S).log}"
FULL_LOG="/tmp/ansible-dry-run-full-$$.log"

cd "$PROJECT_ROOT"

echo "═══════════════════════════════════════════════════════════════════════"
echo "NDFC API Dry-Run: $PLAYBOOK_NAME"
echo "Output: $OUTPUT_FILE"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

# Run playbook and save full output
ansible-playbook "$PLAYBOOK" --check -vvv 2>&1 | tee "$FULL_LOG" | awk '
/TASK \[.*\]/ { 
  task = $0
  printed_task = 0
}

# Capture nd_rest invocation parameters
/invocation:/ { in_invocation = 1; next }
in_invocation && /module_args:/ { in_module_args = 1; next }
in_module_args && /method:/ { 
  method = $0 
  gsub(/^[ \t]+/, "", method)
}
in_module_args && /path:.*\/appcenter/ { 
  path = $0 
  gsub(/^[ \t]+/, "", path)
}
in_module_args && /^[ ]{6}[a-z]/ && !/method:|path:|content:|host:|username:|password:|use_ssl:|validate_certs:|use_proxy:|file_path:/ {
  # End of module_args we care about
}
in_invocation && /^[a-zA-Z]/ { in_invocation = 0; in_module_args = 0 }

# Capture jsondata from result
/jsondata:/ { 
  if (!printed_task && task) {
    print "\n" task
    printed_task = 1
  }
  if (method) print "  " method
  if (path) print "  " path
  print "  payload:"
  capturing = 1
  method = ""
  path = ""
  next
}

# Also capture content being sent 
/content:.*\{/ {
  if (!printed_task && task) {
    print "\n" task
    printed_task = 1
  }
  if (method) print "  " method
  if (path) print "  " path
  print "  content: " $0
  method = ""
  path = ""
}

capturing && /^  (previous|status|current|ansible_loop_var|item):/ { 
  capturing = 0 
  print ""
}
capturing && /^    / { 
  print $0
}
' | tee "$OUTPUT_FILE"

# Check if output is empty
if [ ! -s "$OUTPUT_FILE" ] || [ "$(grep -c 'method:' "$OUTPUT_FILE" 2>/dev/null)" -eq 0 ]; then
  echo ""
  echo "⚠️  No API calls captured. Possible reasons:"
  echo "    - Playbook failed before reaching API calls"
  echo "    - No changes needed (idempotent - already configured)"
  echo "    - Switches filtered out (add_to_fabric: false or conditions not met)"
  echo ""
  echo "Check full log for details:"
  echo "  grep -E 'failed:|skipping:|PLAY RECAP' $FULL_LOG"
  echo ""
  # Show recap
  grep "PLAY RECAP" -A 10 "$FULL_LOG" | head -15
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "API calls saved to: $OUTPUT_FILE"
echo "Full log saved to: $FULL_LOG"
echo "═══════════════════════════════════════════════════════════════════════"
