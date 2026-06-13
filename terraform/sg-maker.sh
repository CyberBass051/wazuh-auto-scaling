#!/usr/bin/env bash

set -o errexit
set -o nounset

get_input() {
    local __resultvar=$1
    local prompt=$2
    local regex=$3
    local error=$4
    local temp_val=""

    if [[ ! "$temp_val" =~ $regex ]]; then
        read -p "$prompt" temp_val
        if [[ ! "$temp_val" =~ $regex ]]; then
            echo "[!] Error: $error"
        fi
    fi

    eval "$__resultvar"="$temp_val"
}

echo "[+] Welcome to the terraform security group creator!]"
read -p "[+] Enter number representing how many security groups you wish to create: " NUM_SG

[[ ! "$NUM_SG" =~ ^[0-9]+$ ]] && { echo "[!] Error: Please enter only numbers"; exit 1; }

for (( x=1; x<=NUM_SG; x++ )); do
    echo "--- Config for SG #$x ---"

    # Use our function for every field
    get_input "SG_RESOURCE_NAME" "Resource Name (e.g. web_sg): " "^[a-z_]+$" "Lowercases and underscores only."
    get_input "SG_NAME"          "SG Display Name (e.g. web-sg): " "^[a-z-]+$" "Lowercases and hyphens only."
    get_input "VPC_ID"           "VPC ID (vpc-xxxx): " "^vpc-[a-f0-9]+$" "Invalid VPC ID format."
    get_input "DESCRIPTION"      "Description: " "^[a-zA-Z0-9_.,;: -]+$" "Invalid characters in description."

    # Step 5: Formatting and Writing
    [[ "$x" -gt 1 ]] && echo "" >> sg.tf

    cat >> sg.tf << EOF
resource "aws_security_group" "$SG_RESOURCE_NAME" {
  name        = "$SG_NAME"
  vpc_id      = "$VPC_ID"
  description = "$DESCRIPTION"
}
EOF

    echo "[+] SG #$x ($SG_RESOURCE_NAME) appended."
done