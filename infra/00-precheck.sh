#!/usr/bin/env bash
# ==============================================================================
# Script: infra/00-precheck.sh
# Purpose: Read-only pre-flight inspection for Azure AKS + ACR deployment.
# Safety: READ-ONLY. Makes ZERO modifications to Azure resources.
# ==============================================================================

set -euo pipefail

# Text formatting for readable output
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

REGION="${1:-}"

print_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# ------------------------------------------------------------------------------
# 1. Verify Prerequisites & Azure CLI Authentication
# ------------------------------------------------------------------------------
print_header "1. Azure CLI Authentication Check"

# 'command -v az' checks if the Azure CLI binary is installed and present in PATH.
if ! command -v az &>/dev/null; then
    echo -e "${RED}[ERROR] Azure CLI ('az') is not installed or not in PATH.${NC}"
    echo "To install the Azure CLI:"
    echo "  - Windows: winget install -e --id Microsoft.AzureCLI"
    echo "  - Linux/WSL: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
    echo "  - Official docs: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

echo -e "${GREEN}[OK] Azure CLI is installed.${NC}"

# 'az account show' verifies that the user is actively logged in to Azure.
# If not logged in, it exits with an error directing the user to run 'az login'.
if ! az account show &>/dev/null; then
    echo -e "${RED}[ERROR] You are not logged in to Azure.${NC}"
    echo "Please run 'az login' in your terminal and select your subscription before running this script."
    exit 1
fi

echo -e "${GREEN}[OK] Active Azure login session detected.${NC}"

# ------------------------------------------------------------------------------
# 2. Show Active Subscription Details
# ------------------------------------------------------------------------------
print_header "2. Current Active Subscription"

# 'az account show' returns the currently selected subscription context.
# We query the subscription ID, name, tenant ID, and account state.
az account show --query "{SubscriptionId:id, SubscriptionName:name, TenantId:tenantId, State:state}" -o table

# ------------------------------------------------------------------------------
# 3. Check Required Azure Resource Providers
# ------------------------------------------------------------------------------
print_header "3. Resource Provider Registration Status"
echo "Checking registration status for providers needed by AKS, ACR, and Traefik..."

# Resource providers required for this project:
# - Microsoft.ContainerService: Required to create and manage AKS clusters
# - Microsoft.ContainerRegistry: Required for Azure Container Registry (ACR)
# - Microsoft.Network: Required for VNet, Subnet, and Public IP (Traefik LoadBalancer)
# - Microsoft.Compute: Required for underlying VM instances running Kubernetes nodes
PROVIDERS=(
    "Microsoft.ContainerService"
    "Microsoft.ContainerRegistry"
    "Microsoft.Network"
    "Microsoft.Compute"
)

printf "%-32s %-15s %-10s\n" "Provider Namespace" "Status" "Action Needed"
printf "%-32s %-15s %-10s\n" "--------------------------------" "---------------" "-------------"

for provider in "${PROVIDERS[@]}"; do
    # 'az provider show' fetches the registration status of the specified namespace.
    # A status of 'Registered' means the subscription is authorized to deploy resources under this provider.
    STATE=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "Unknown")
    
    if [ "$STATE" == "Registered" ]; then
        STATUS_COLOR="${GREEN}Registered${NC}"
        ACTION="None (Ready)"
    else
        STATUS_COLOR="${YELLOW}${STATE}${NC}"
        ACTION="Run: az provider register --namespace $provider"
    fi
    printf "%-32s %-24b %-10s\n" "$provider" "$STATUS_COLOR" "$ACTION"
done

# ------------------------------------------------------------------------------
# 4. Check for Azure Policy Location Restrictions
# ------------------------------------------------------------------------------
print_header "4. Azure Policy: Allowed Locations Check"

echo "Checking if subscription policies restrict resource deployments to specific regions..."

# 'az policy assignment list' lists all governance policies assigned to this subscription.
# Student subscriptions and enterprise sandboxes often assign the 'Allowed locations' policy.
POLICY_LOCATIONS=$(az policy assignment list \
    --query "[?contains(displayName, 'allowed') || contains(displayName, 'location') || contains(displayName, 'Location') || parameters.listOfAllowedLocations != null].{Name:displayName, AllowedLocations:parameters.listOfAllowedLocations.value}" \
    -o json 2>/dev/null || echo "[]")

if [ "$POLICY_LOCATIONS" != "[]" ] && [ -n "$POLICY_LOCATIONS" ] && [ "$POLICY_LOCATIONS" != "null" ]; then
    echo -e "${YELLOW}[NOTE] Location restrictions detected in your Azure Policy assignments:${NC}"
    echo "$POLICY_LOCATIONS"
else
    echo -e "${GREEN}[INFO] No explicit 'Allowed locations' Azure Policy restriction detected.${NC}"
    echo "You may deploy to any standard Azure region supported by your subscription tier."
fi

# ------------------------------------------------------------------------------
# 5. List Available 2 vCPU / >=4 GiB VM Sizes in Target Region
# ------------------------------------------------------------------------------
print_header "5. Available VM Sizes (2 vCPU, >=4 GiB RAM)"

if [ -z "$REGION" ]; then
    echo -e "${YELLOW}[INFO] No region argument provided.${NC}"
    echo "Usage: ./infra/00-precheck.sh <region>"
    echo "Example: ./infra/00-precheck.sh eastus"
    echo ""
    echo "To see available Azure locations for your subscription, run:"
    echo "  az account list-locations --query \"[?metadata.regionCategory=='Recommended'].{DisplayName:displayName, Name:name}\" -o table"
else
    echo "Listing virtual machine sizes in region '${REGION}' with 2 vCPUs and at least 4 GiB memory..."
    
    # 'az vm list-skus' queries available SKUs in the given location.
    # We filter virtual machines that have 2 vCPUs, >= 4GB RAM, and display restriction codes (if any quota issues exist).
    az vm list-skus \
        --location "$REGION" \
        --resource-type virtualMachines \
        --query "[?capabilities[?name=='vCPUs' && value=='2'] && capabilities[?name=='MemoryGB' && to_number(value)>=4]].{Name:name, Tier:tier, vCPUs:capabilities[?name=='vCPUs'].value | [0], MemoryGB:capabilities[?name=='MemoryGB'].value | [0], Restrictions:restrictions[0].reasonCode}" \
        -o table 2>/dev/null || {
            echo -e "${YELLOW}[NOTE] Fallback query via 'az vm list-sizes'...${NC}"
            # 'az vm list-sizes' provides a fast fallback if SKU listing fails or times out.
            az vm list-sizes --location "$REGION" \
                --query "[?numberOfCores==\`2\` && memoryInMB>=\`4096\`].{Name:name, vCPUs:numberOfCores, MemoryGiB:memoryInMB/1024}" \
                -o table
        }
fi

# ------------------------------------------------------------------------------
# 6. Pricing Reference Note
# ------------------------------------------------------------------------------
print_header "6. Approximate Pricing Guide"
cat << 'EOF'
To check current pricing for virtual machine sizes, AKS, and ACR:

1. Azure Pricing Calculator (Interactive):
   https://azure.microsoft.com/pricing/calculator/
   - Under 'Virtual Machines', search for burstable sizes (e.g. Standard_B2s, ~$0.0416/hr or ~$30/month)
     or general-purpose sizes (e.g. Standard_D2s_v5).
   - Under 'Azure Container Registry', select the 'Basic' tier (~$0.167/day or ~$5/month).
   - Under 'Azure Kubernetes Service', the control plane is Free tier ($0).

2. Azure Retail Prices API (CLI query example):
   # Example: Query retail price for Standard_B2s in eastus
   curl -s "https://prices.azure.com/api/retail/prices?\$filter=serviceName%20eq%20'Virtual%20Machines'%20and%20armSkuName%20eq%20'Standard_B2s'%20and%20armRegionName%20eq%20'eastus'%20and%20priceType%20eq%20'Consumption'" \
     | grep -o '"retailPrice":[0-9.]*' | head -n 1
EOF

echo -e "\n${GREEN}=== Pre-check inspection script completed successfully ===${NC}\n"
