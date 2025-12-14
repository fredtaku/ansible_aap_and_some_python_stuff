#!/bin/bash
#
# AAP 2.5 Container Discovery Script
# Purpose: Discover and categorize all containers in an AAP 2.5 installation
# Usage: ./aap2.5_discovery.sh [output_format]
#        output_format: text (default), json, csv
#

set -e

# Configuration
OUTPUT_FORMAT="${1:-text}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
INVENTORY_FILE="/home/tfred/aap2.5_install/inventory-growth"
PODMAN_USER="tfred"

# Color codes for text output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Container categorization
declare -A CONTAINER_PURPOSES=(
    ["automation-controller-web"]="Automation Controller - Web UI and API server"
    ["automation-controller-task"]="Automation Controller - Job execution and task manager"
    ["automation-controller-rsyslog"]="Automation Controller - Logging service"
    ["automation-hub-web"]="Automation Hub - Web service and API"
    ["automation-hub-content"]="Automation Hub - Content management"
    ["automation-hub-worker"]="Automation Hub - Background worker for async tasks"
    ["automation-hub-api"]="Automation Hub - API service"
    ["pulp-web"]="Pulp - Content delivery web service"
    ["pulp-content"]="Pulp - Content serving application"
    ["pulp-api"]="Pulp - API service"
    ["pulp-worker"]="Pulp - Background content processing"
    ["eda-web"]="Event-Driven Ansible - Web UI and API"
    ["eda-api"]="Event-Driven Ansible - API service"
    ["eda-worker"]="Event-Driven Ansible - Event processing worker"
    ["eda-scheduler"]="Event-Driven Ansible - Task scheduler"
    ["eda-daphne"]="Event-Driven Ansible - WebSocket server"
    ["eda-default-worker"]="Event-Driven Ansible - Default worker"
    ["eda-activation-worker"]="Event-Driven Ansible - Activation worker"
    ["redis"]="Redis - Cache and message broker"
    ["redis-unix"]="Redis - Unix socket cache service"
    ["receptor"]="Receptor - Mesh networking for execution nodes"
    ["gateway-web"]="Platform Gateway - Web and routing service"
    ["gateway-api"]="Platform Gateway - API service"
    ["nginx"]="Nginx - Reverse proxy and load balancer"
    ["postgres"]="PostgreSQL - Database server"
    ["postgresql"]="PostgreSQL - Database server"
)

# Extract hostnames from inventory
get_hosts_from_inventory() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "Error: Inventory file not found at $INVENTORY_FILE" >&2
        exit 1
    fi

    grep -E "^aap2.5-node[0-9]+\.example\.com" "$INVENTORY_FILE" | sort -u
}

# Categorize container by name
categorize_container() {
    local container_name="$1"
    local purpose="Unknown purpose"

    # Check for exact matches first
    if [[ -n "${CONTAINER_PURPOSES[$container_name]}" ]]; then
        purpose="${CONTAINER_PURPOSES[$container_name]}"
    else
        # Check for partial matches
        for key in "${!CONTAINER_PURPOSES[@]}"; do
            if [[ "$container_name" == *"$key"* ]]; then
                purpose="${CONTAINER_PURPOSES[$key]}"
                break
            fi
        done
    fi

    echo "$purpose"
}

# Get container details from a host
get_containers_from_host() {
    local hostname="$1"
    local result_file="$2"

    echo "Scanning $hostname..." >&2

    # Check if host is reachable
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$hostname" "echo OK" &>/dev/null; then
        echo "WARNING: Cannot connect to $hostname" >&2
        return 1
    fi

    # Get container information
    ssh "$hostname" "sudo su - $PODMAN_USER -c 'podman ps -a --format \"{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}|{{.Size}}\"'" 2>/dev/null | \
    while IFS='|' read -r id name image status ports size; do
        local purpose
        purpose=$(categorize_container "$name")

        # Extract component type from container name
        local component="Unknown"
        case "$name" in
            automation-controller-*)
                component="Automation Controller"
                ;;
            automation-hub-*|pulp-*)
                component="Automation Hub"
                ;;
            eda-*)
                component="Event-Driven Ansible"
                ;;
            gateway-*)
                component="Platform Gateway"
                ;;
            redis*)
                component="Redis"
                ;;
            receptor*)
                component="Receptor"
                ;;
            postgres*|postgresql*)
                component="PostgreSQL"
                ;;
        esac

        echo "$hostname|$component|$name|$id|$image|$status|$ports|$size|$purpose" >> "$result_file"
    done

    return 0
}

# Output in text format
output_text() {
    local data_file="$1"

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}AAP 2.5 Container Discovery Report${NC}"
    echo -e "${GREEN}Generated: $(date)${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    # Group by host
    local current_host=""
    while IFS='|' read -r hostname component container_name id image status ports size purpose; do
        if [[ "$hostname" != "$current_host" ]]; then
            current_host="$hostname"
            echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}Host: $hostname${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
        fi

        # Color code status
        local status_color=$GREEN
        if [[ "$status" == *"Exited"* ]] || [[ "$status" == *"stopped"* ]]; then
            status_color=$RED
        elif [[ "$status" == *"Created"* ]]; then
            status_color=$YELLOW
        fi

        echo -e "${YELLOW}Container:${NC} $container_name"
        echo -e "  ${YELLOW}Component:${NC} $component"
        echo -e "  ${YELLOW}Purpose:${NC} $purpose"
        echo -e "  ${YELLOW}ID:${NC} $id"
        echo -e "  ${YELLOW}Image:${NC} $image"
        echo -e "  ${YELLOW}Status:${NC} ${status_color}$status${NC}"
        [[ -n "$ports" ]] && echo -e "  ${YELLOW}Ports:${NC} $ports"
        [[ -n "$size" ]] && echo -e "  ${YELLOW}Size:${NC} $size"
        echo ""
    done < "$data_file"

    # Summary
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Summary${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo "Total Hosts: $(cut -d'|' -f1 "$data_file" | sort -u | wc -l)"
    echo "Total Containers: $(wc -l < "$data_file")"
    echo ""
    echo "Containers by Component:"
    cut -d'|' -f2 "$data_file" | sort | uniq -c | sort -rn | while read count comp; do
        echo "  $comp: $count"
    done
    echo ""
    echo "Containers by Status:"
    cut -d'|' -f6 "$data_file" | sed 's/Up.*/Running/' | sed 's/Exited.*/Stopped/' | sort | uniq -c | sort -rn | while read count stat; do
        echo "  $stat: $count"
    done
}

# Output in JSON format
output_json() {
    local data_file="$1"

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"report_type\": \"AAP 2.5 Container Discovery\","
    echo "  \"containers\": ["

    local first=true
    while IFS='|' read -r hostname component container_name id image status ports size purpose; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi

        echo -n "    {"
        echo -n "\"hostname\": \"$hostname\", "
        echo -n "\"component\": \"$component\", "
        echo -n "\"container_name\": \"$container_name\", "
        echo -n "\"id\": \"$id\", "
        echo -n "\"image\": \"$image\", "
        echo -n "\"status\": \"$status\", "
        echo -n "\"ports\": \"$ports\", "
        echo -n "\"size\": \"$size\", "
        echo -n "\"purpose\": \"$purpose\""
        echo -n "}"
    done < "$data_file"

    echo ""
    echo "  ]"
    echo "}"
}

# Output in CSV format
output_csv() {
    local data_file="$1"

    echo "Hostname,Component,Container Name,ID,Image,Status,Ports,Size,Purpose"
    while IFS='|' read -r hostname component container_name id image status ports size purpose; do
        echo "\"$hostname\",\"$component\",\"$container_name\",\"$id\",\"$image\",\"$status\",\"$ports\",\"$size\",\"$purpose\""
    done < "$data_file"
}

# Main execution
main() {
    local temp_file=$(mktemp)
    trap "rm -f $temp_file" EXIT

    echo "Starting AAP 2.5 Container Discovery..." >&2
    echo "Reading inventory from: $INVENTORY_FILE" >&2
    echo "" >&2

    # Get all hosts
    local hosts
    hosts=$(get_hosts_from_inventory)

    if [[ -z "$hosts" ]]; then
        echo "Error: No hosts found in inventory" >&2
        exit 1
    fi

    # Scan each host
    for host in $hosts; do
        get_containers_from_host "$host" "$temp_file" || true
    done

    # Check if we found any containers
    if [[ ! -s "$temp_file" ]]; then
        echo "Error: No containers found on any host" >&2
        exit 1
    fi

    echo "" >&2
    echo "Discovery complete. Generating report..." >&2
    echo "" >&2

    # Generate output
    case "$OUTPUT_FORMAT" in
        json)
            output_json "$temp_file"
            ;;
        csv)
            output_csv "$temp_file"
            ;;
        text|*)
            output_text "$temp_file"
            ;;
    esac
}

# Run main function
main
