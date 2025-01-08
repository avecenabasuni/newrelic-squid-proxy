#!/bin/bash

# ============================
# New Relic Connection Test Script
# Created by: Avecena Basuni
# Date: January 8, 2025
# License: MIT License
# ============================

# List of New Relic endpoints to test
endpoints=(
  "https://collector.newrelic.com"
  "https://aws-api.newrelic.com"
  "https://cloud-collector.newrelic.com"
  "https://bam.nr-data.net"
  "https://bam-cell.nr-data.net"
  "https://csec.nr-data.net"
  "https://insights-collector.newrelic.com"
  "https://log-api.newrelic.com"
  "https://metric-api.newrelic.com"
  "https://trace-api.newrelic.com"
  "https://infra-api.newrelic.com"
  "https://identity-api.newrelic.com"
  "https://infrastructure-command-api.newrelic.com"
  "https://nrql-lookup.service.newrelic.com"
  "https://mobile-collector.newrelic.com"
  "https://mobile-crash.newrelic.com"
  "https://mobile-symbol-upload.newrelic.com"
  "https://otlp.nr-data.net"
  "https://collector.eu.newrelic.com"
  "https://collector.eu01.nr-data.net"
  "https://aws-api.eu.newrelic.com"
  "https://aws-api.eu01.nr-data.net"
  "https://cloud-collector.eu.newrelic.com"
  "https://bam.eu01.nr-data.net"
  "https://csec.eu01.nr-data.net"
  "https://insights-collector.eu01.nr-data.net"
  "https://log-api.eu.newrelic.com"
  "https://metric-api.eu.newrelic.com"
  "https://trace-api.eu.newrelic.com"
  "https://infra-api.eu.newrelic.com"
  "https://infra-api.eu01.nr-data.net"
  "https://identity-api.eu.newrelic.com"
  "https://infrastructure-command-api.eu.newrelic.com"
  "https://nrql-lookup.service.eu.newrelic.com"
  "https://mobile-collector.eu01.nr-data.net"
  "https://mobile-crash.eu01.nr-data.net"
  "https://mobile-symbol-upload.eu01.nr-data.net"
  "https://otlp.eu01.nr-data.net"
  "https://download.newrelic.com"
)

# Function to check for required dependencies
check_dependencies() {
    local dependencies=("curl")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            echo -e "\033[31mError: $dep is not installed. Please install it before running the script.\033[0m"
            exit 1
        fi
    done
}

# Function to test the connection and count success/failure
test_connection() {
    local url=$1
    echo -n "Testing connection to $url... "
    # Test connection with curl through Squid Proxy
    response=$(curl -s -o /dev/null -w "%{http_code}" -x http://localhost:3128 "$url")
    
    # Check if response code is 200, 404, or 400 (which are acceptable)
    if [[ "$response" -eq 200 || "$response" -eq 404 || "$response" -eq 400 ]]; then
        echo -e "\033[32m Success\033[0m"  # Green color for success
        success_count=$((success_count + 1))
    else
        echo -e "\033[31m Failed (HTTP $response)\033[0m"  # Red color for failure
        fail_count=$((fail_count + 1))
    fi
}

# Initialize success and fail counters
success_count=0
fail_count=0

# Display script metadata
echo -e "\033[1;33m=====================================================\033[0m"
echo -e "\033[1;32mNew Relic Connection Test Script\033[0m"
echo -e "\033[1;34mCreated by: Avecena Basuni\033[0m"
echo -e "\033[1;34mDate: January 8, 2025\033[0m"
echo -e "\033[1;34mLicense: MIT License\033[0m"
echo -e "\033[1;33m=====================================================\033[0m"

# Check if required dependencies are installed
check_dependencies

# Loop through each endpoint and test
echo "Testing connection to New Relic endpoints..."
for endpoint in "${endpoints[@]}"; do
    test_connection "$endpoint"
done

# Final conclusion based on success/fail status
echo
echo -e "\033[1;33m=====================================================\033[0m"
echo "Test results summary:"
echo -e "Successful connections: \033[32m$success_count\033[0m"
echo -e "Failed connections: \033[31m$fail_count\033[0m"
echo -e "\033[1;33m=====================================================\033[0m"
