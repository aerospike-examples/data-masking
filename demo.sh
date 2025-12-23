#!/bin/bash

# ============================================================================
# Aerospike Data Masking Demo Script
# ============================================================================
# This script demonstrates Aerospike's data masking capabilities including:
#   - Role-Based Access Control (RBAC)
#   - Dynamic data masking rules
#   - Masked vs unmasked data access
#   - Write protection on masked bins
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
NETWORK_NAME="datamasking_aerospike-qs"
CONTAINER_NAME="aerospike-masking"
AEROSPIKE_IMAGE="aerospike/aerospike-server-enterprise:8.1.1.0-rc20_1"
TOOLS_IMAGE="aerospike/aerospike-tools"

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}  ℹ $1${NC}"
}

print_command() {
    echo -e "${CYAN}  $ $1${NC}"
}

wait_for_enter() {
    echo ""
    echo -e "${YELLOW}Press ENTER to continue...${NC}"
    read -r
}

run_asadm() {
    local user=$1
    local pass=$2
    shift 2
    docker run --rm -i \
        --network "$NETWORK_NAME" \
        "$AEROSPIKE_IMAGE" \
        asadm -h "$CONTAINER_NAME" -p 3000 -U "$user" -P "$pass" -e "$*"
}

run_aql() {
    local user=$1
    local pass=$2
    shift 2
    docker run --rm -i \
        --network "$NETWORK_NAME" \
        "$TOOLS_IMAGE" \
        aql --user "$user" --password "$pass" --host "$CONTAINER_NAME" --port 3000 -c "$*"
}

# ============================================================================
# DEMO START
# ============================================================================

clear
echo -e "${BOLD}"
echo "    _                        _ _         "
echo "   / \   ___ _ __ ___  ___ _(_) | _____  "
echo "  / _ \ / _ \ '__/ _ \/ __| | | |/ / _ \ "
echo " / ___ \  __/ | | (_) \__ \ | |   <  __/ "
echo "/_/   \_\___|_|  \___/|___/_|_|_|\_\___| "
echo ""
echo "         DATA MASKING DEMO"
echo -e "${NC}"
echo ""
echo -e "${YELLOW}This demo showcases Aerospike's enterprise data masking feature${NC}"
echo -e "${YELLOW}which provides dynamic, policy-based protection for sensitive data.${NC}"
echo ""
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 1: Environment Setup
# ----------------------------------------------------------------------------
print_header "STEP 1: Starting Aerospike Enterprise Server"

print_step "Building and starting Docker Compose environment..."
docker compose build --quiet
docker compose up -d

print_info "Waiting for Aerospike to initialize (10 seconds)..."
sleep 10

print_step "Verifying server is running..."
print_command "asinfo -v build"
docker run --rm \
    --network "$NETWORK_NAME" \
    "$AEROSPIKE_IMAGE" \
    asinfo -h "$CONTAINER_NAME" -p 3000 -U admin -P admin -v build

echo ""
print_info "Aerospike Enterprise is running!"
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 2: RBAC Setup
# ----------------------------------------------------------------------------
print_header "STEP 2: Setting Up Role-Based Access Control (RBAC)"

echo -e "${YELLOW}We'll create three roles with different permissions:${NC}"
echo ""
echo "  ┌──────────────┬─────────────────────────────────────────────┐"
echo "  │ Role         │ Permissions                                 │"
echo "  ├──────────────┼─────────────────────────────────────────────┤"
echo "  │ banking_app  │ read-write, read-masked, write-masked       │"
echo "  │              │ (Can see unmasked data, modify masked bins) │"
echo "  ├──────────────┼─────────────────────────────────────────────┤"
echo "  │ analyst      │ read only                                   │"
echo "  │              │ (Can only see MASKED data)                  │"
echo "  ├──────────────┼─────────────────────────────────────────────┤"
echo "  │ masking_dba  │ masking-admin                               │"
echo "  │              │ (Can create/modify masking rules)           │"
echo "  └──────────────┴─────────────────────────────────────────────┘"
echo ""
wait_for_enter

print_step "Creating roles..."

# Create banking_app role
run_asadm admin admin "enable; manage acl create role banking_app priv read-write"
run_asadm admin admin "enable; manage acl grant role banking_app priv read-masked"
run_asadm admin admin "enable; manage acl grant role banking_app priv write-masked"
print_info "Created role: banking_app"

# Create analyst role
run_asadm admin admin "enable; manage acl create role analyst priv read"
print_info "Created role: analyst"

# Create masking_dba role
run_asadm admin admin "enable; manage acl create role masking_dba priv masking-admin"
print_info "Created role: masking_dba"

echo ""
print_step "Creating users..."

# Create users
run_asadm admin admin "enable; manage acl create user app_service password SecureApp123! roles banking_app"
print_info "Created user: app_service (role: banking_app)"

run_asadm admin admin "enable; manage acl create user analyst_1 password Analyst456! roles analyst"
print_info "Created user: analyst_1 (role: analyst)"

run_asadm admin admin "enable; manage acl create user masking_admin password DBA789! roles masking_dba"
print_info "Created user: masking_admin (role: masking_dba)"

echo ""
print_step "Verifying RBAC configuration..."
run_asadm admin admin "show roles"

wait_for_enter

# ----------------------------------------------------------------------------
# STEP 3: Define Masking Rules
# ----------------------------------------------------------------------------
print_header "STEP 3: Defining Data Masking Rules"

echo -e "${YELLOW}We'll create masking rules for sensitive customer data:${NC}"
echo ""
echo "  ┌────────────┬────────────┬─────────────────────────────────────┐"
echo "  │ Bin        │ Rule Type  │ Behavior                            │"
echo "  ├────────────┼────────────┼─────────────────────────────────────┤"
echo "  │ ssn        │ redact     │ Replace first 7 chars with *        │"
echo "  │            │            │ 123-45-6789 → *******6789           │"
echo "  ├────────────┼────────────┼─────────────────────────────────────┤"
echo "  │ email      │ constant   │ Always show: redacted@example.com   │"
echo "  ├────────────┼────────────┼─────────────────────────────────────┤"
echo "  │ notes      │ constant   │ Always show: [REDACTED]             │"
echo "  └────────────┴────────────┴─────────────────────────────────────┘"
echo ""
wait_for_enter

print_step "Creating masking rules as masking_admin..."

# Create masking rules
run_asadm masking_admin DBA789! "enable; manage masking add redact position 0 length 7 value * namespace test set customers bin ssn"
print_info "Created SSN redaction rule"

run_asadm masking_admin DBA789! "enable; manage masking add constant value redacted@example.com namespace test set customers bin email"
print_info "Created email masking rule"

run_asadm masking_admin DBA789! "enable; manage masking add constant value [REDACTED] namespace test set customers bin notes"
print_info "Created notes masking rule"

echo ""
print_step "Verifying masking rules..."
run_asadm masking_admin DBA789! "show masking namespace test"

wait_for_enter

# ----------------------------------------------------------------------------
# STEP 4: Insert Test Data
# ----------------------------------------------------------------------------
print_header "STEP 4: Inserting Customer Records"

echo -e "${YELLOW}Inserting sample customer data as app_service user...${NC}"
echo ""

print_step "Inserting customer record..."
print_command "INSERT INTO test.customers (PK, name, ssn, email, notes) VALUES (...)"

run_aql app_service SecureApp123! "INSERT INTO test.customers (PK, name, ssn, email, notes) VALUES ('CUST-00001', 'John Smith', '123-45-6789', 'john.smith@acme.com', 'VIP customer - prefers phone contact')"
print_info "Inserted: CUST-00001 - John Smith"

run_aql app_service SecureApp123! "INSERT INTO test.customers (PK, name, ssn, email, notes) VALUES ('CUST-00002', 'Jane Doe', '987-65-4321', 'jane.doe@corp.com', 'Enterprise account - NDA on file')"
print_info "Inserted: CUST-00002 - Jane Doe"

run_aql app_service SecureApp123! "INSERT INTO test.customers (PK, name, ssn, email, notes) VALUES ('CUST-00003', 'Bob Wilson', '555-12-3456', 'bob.wilson@startup.io', 'Referred by Jane Doe - startup discount applied')"
print_info "Inserted: CUST-00003 - Bob Wilson"

echo ""
print_info "Customer records created successfully!"
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 5: Demonstrate Unmasked Access
# ----------------------------------------------------------------------------
print_header "STEP 5: Unmasked Data Access (app_service user)"

echo -e "${YELLOW}The app_service user has 'read-masked' privilege,${NC}"
echo -e "${YELLOW}allowing them to see the ACTUAL unmasked data.${NC}"
echo ""

print_step "Reading customer records as app_service..."
print_command "SELECT * FROM test.customers"
echo ""

run_aql app_service SecureApp123! "SELECT * FROM test.customers"

echo ""
echo -e "${GREEN}✓ Notice: SSN, email, and notes show REAL values${NC}"
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 6: Demonstrate Masked Access
# ----------------------------------------------------------------------------
print_header "STEP 6: Masked Data Access (analyst_1 user)"

echo -e "${YELLOW}The analyst_1 user only has 'read' privilege,${NC}"
echo -e "${YELLOW}so they will see MASKED data for protected bins.${NC}"
echo ""

print_step "Reading customer records as analyst_1..."
print_command "SELECT * FROM test.customers"
echo ""

run_aql analyst_1 Analyst456! "SELECT * FROM test.customers"

echo ""
echo -e "${GREEN}✓ Notice the masking applied:${NC}"
echo -e "  • SSN: First 7 characters replaced with *******"
echo -e "  • Email: Shows 'redacted@example.com'"
echo -e "  • Notes: Shows '[REDACTED]'"
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 7: Demonstrate Write Protection
# ----------------------------------------------------------------------------
print_header "STEP 7: Write Protection on Masked Bins"

echo -e "${YELLOW}Users without 'write-masked' privilege cannot${NC}"
echo -e "${YELLOW}modify bins that have masking rules applied.${NC}"
echo ""

print_step "Attempting to update SSN as analyst_1 (should FAIL)..."
print_command "INSERT INTO test.customers (PK, ssn) VALUES ('CUST-00001', '999-99-9999')"
echo ""

# This should fail with ROLE_VIOLATION
run_aql analyst_1 Analyst456! "INSERT INTO test.customers (PK, ssn) VALUES ('CUST-00001', '999-99-9999')" 2>&1 || true

echo ""
echo -e "${GREEN}✓ Write blocked! The analyst cannot modify masked bins.${NC}"
echo ""

print_step "Attempting same update as app_service (should SUCCEED)..."
print_command "INSERT INTO test.customers (PK, ssn) VALUES ('CUST-00001', '111-22-3333')"
echo ""

run_aql app_service SecureApp123! "INSERT INTO test.customers (PK, ssn) VALUES ('CUST-00001', '111-22-3333')"

echo ""
echo -e "${GREEN}✓ Update succeeded! app_service has write-masked privilege.${NC}"
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 8: Verify the Update
# ----------------------------------------------------------------------------
print_header "STEP 8: Verifying the Update"

print_step "Reading updated record as app_service (unmasked)..."
run_aql app_service SecureApp123! "SELECT * FROM test.customers WHERE PK='CUST-00001'"

echo ""
print_step "Reading same record as analyst_1 (masked)..."
run_aql analyst_1 Analyst456! "SELECT * FROM test.customers WHERE PK='CUST-00001'"

echo ""
echo -e "${GREEN}✓ The update is reflected, and masking still applies per user role!${NC}"
wait_for_enter

# ----------------------------------------------------------------------------
# STEP 9: Audit Log
# ----------------------------------------------------------------------------
print_header "STEP 9: Audit Logging"

echo -e "${YELLOW}Aerospike logs masking-related events for compliance:${NC}"
echo -e "  • Masking rule changes"
echo -e "  • Failed write attempts to masked bins"
echo ""

print_step "Recent audit log entries:"
echo ""
docker exec "$CONTAINER_NAME" tail -20 /var/log/aerospike/audit.log 2>/dev/null || echo "  (Audit log entries will appear here)"

wait_for_enter

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
print_header "DEMO COMPLETE!"

echo -e "${BOLD}Summary of Aerospike Data Masking Features:${NC}"
echo ""
echo "  ✅ Dynamic masking - No data duplication required"
echo "  ✅ Role-based access - Same query, different results per user"
echo "  ✅ Write protection - Prevents unauthorized modification"
echo "  ✅ Audit logging - Track all masking operations"
echo "  ✅ Flexible rules - Redact, constant replacement, and more"
echo ""
echo -e "${YELLOW}Key Takeaways:${NC}"
echo "  • Masking happens at read time, original data stays intact"
echo "  • No application code changes needed"
echo "  • Granular control at namespace/set/bin level"
echo "  • Enterprise security for compliance (PCI-DSS, GDPR, HIPAA)"
echo ""
echo -e "${CYAN}Useful commands for further exploration:${NC}"
echo ""
echo "  # Connect as admin to manage roles/users:"
echo "  docker run --rm -it --network $NETWORK_NAME \\"
echo "    $AEROSPIKE_IMAGE \\"
echo "    asadm -h $CONTAINER_NAME -p 3000 -U admin -P admin"
echo ""
echo "  # Connect as analyst to see masked data:"
echo "  docker run --rm -it --network $NETWORK_NAME \\"
echo "    $TOOLS_IMAGE \\"
echo "    aql --user analyst_1 --password Analyst456! --host $CONTAINER_NAME --port 3000"
echo ""
echo "  # View audit log:"
echo "  docker exec $CONTAINER_NAME tail -f /var/log/aerospike/audit.log"
echo ""
echo "  # Cleanup:"
echo "  docker compose down -v"
echo ""
echo -e "${GREEN}Thank you for watching the demo!${NC}"
echo ""

