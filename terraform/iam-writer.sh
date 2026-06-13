#!/usr/bin/env bash

set -o errexit
set -o nounset

get_input() {

    local __resultvar=$1
    local script=$2
    local regex=$3
    local err_msg=$4
    local temp_val=""

    while [[ ! "$temp_val" =~ $regex ]]; do
        read -p "$script" temp_val
        if [[ ! "$temp_val" =~ $regex ]]; then
            echo "[!] Error: $err_msg"
        fi
    done

    eval "$__resultvar"="$temp_val"
}

echo "Welcome to the IAM creator"

get_input "IAM_TYPE" "Enter the type of IAM you wish to create (User, Group, Role) " ^(user|role|group)$ "Input must be either: role, user or group" 
get_input "NAME"

