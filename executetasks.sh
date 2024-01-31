#!/usr/bin/env bash

$oclogin
# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install jq."
    exit 1
fi

# Define the JSON file containing input
json_file="cpdtools/taskList.json"

# Check if the JSON file exists
if [ ! -f "$json_file" ]; then
    echo "File $json_file not found."
    exit 1
fi

# Extract keys with value true using jq
true_keys=$(jq -r 'to_entries[] | .key as $parent | .value | to_entries[] | select(.value == true) | "\($parent).\(.key)"' "$json_file")

# Split the string of true keys into an array
IFS=$'\n' read -r -d '' -a keys_array <<<"$true_keys"

# Iterate through the keys array
for key in "${keys_array[@]}"; do
    IFS='.' read -r section script <<< "$key"
    echo "=============================================================="
    echo "Processing key: $script"
    cpdtools/cpst_checktool.sh -c $script
done
