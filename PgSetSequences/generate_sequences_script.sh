#!/bin/bash

# Script: generate_single_sequences_script.sh
# Description: Discovers all databases and generates ONE SQL script with sequence last values
# Usage: ./generate_single_sequences_script.sh [ -h HOST ] [ -p PORT ] [ -U USER ] [ -d DATABASE ] [ -o FILE ] [ --apply ]

# Default connection parameters
DEFAULT_HOST="localhost"
DEFAULT_PORT="5444"
DEFAULT_USER="postgres"
DEFAULT_DATABASE="postgres"
PGPASS_FILE="../_pgpass"  # Override for testing, ensure this file exists with proper credentials

# Output file
OUTPUT_FILE="restore_all_sequences.sql"
APPLY_CHANGES=false  # If true, will apply changes directly to each database

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h HOST      PostgreSQL host (default: localhost)
    -p PORT      PostgreSQL port (default: 5444)
    -U USER      PostgreSQL user (default: postgres)
    -d DATABASE  Database to connect for discovering databases (default: postgres)
    -o FILE      Output SQL file (default: restore_all_sequences.sql)
    --apply      Apply the changes directly to each database (instead of just generating script)
    --help       Show this help message

The script uses .pgpass file for authentication.
Format of ~/.pgpass: hostname:port:database:username:password

Examples:
    $0                                    # Generate script only
    $0 --apply                           # Generate and apply directly to databases
    $0 -h 192.168.1.100 -p 5444 -U admin  # Connect to remote server
    $0 -o /tmp/all_sequences.sql         # Change output file location
EOF
}

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if psql is available
check_prerequisites() {
    if ! command -v psql &> /dev/null; then
        log_message "ERROR: psql command not found. Please install PostgreSQL client."
        exit 1
    fi
}

# Function to get all database names from cluster
get_all_databases() {
    local host=$1
    local port=$2
    local user=$3
    local database=$4
    
    local sql_query="
    SELECT datname 
    FROM pg_database 
    WHERE datistemplate = false 
    AND datname NOT IN ('postgres', 'template0', 'template1')
    ORDER BY datname;
    "
    
    # Get list of databases
    local databases=$(PGPASSFILE="$PGPASS_FILE" psql -h "$host" -p "$port" -U "$user" -d "$database" -t -A -c "$sql_query" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to connect to database cluster"
        return 1
    fi
    
    echo "$databases"
}

# Function to generate SQL for a specific database and optionally apply it
process_database_sequences() {
    local db_name=$1
    local db_host=$2
    local db_port=$3
    local db_user=$4
    local output_file=$5
    local apply_changes=$6
    
    log_message "Processing database: ${db_name}"
    
    # SQL query to get all sequences and their last values
    local sql_query="
    SELECT 
        schemaname,
        sequencename,
        last_value,
        increment_by,
        min_value,
        max_value,
        cache_size,
        start_value
    FROM pg_sequences 
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY schemaname, sequencename;
    "
    
# Create temporary file for this database's SQL
local temp_sql=$(mktemp)
    
# Add header for this database
 cat >> "$output_file" << EOF

-- =====================================================
-- DATABASE: ${db_name}
-- =====================================================

\\c ${db_name}

EOF
    
    # Execute query and generate SQL script content
    local sequence_count=0
    PGPASSFILE="$PGPASS_FILE" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -t -A -F "|" -c "$sql_query" 2>/dev/null | while IFS='|' read -r schemaname sequencename last_value increment_by min_value max_value cache_size is_cycled start_value; do
        
        # Skip empty lines
        if [ -z "$sequencename" ] || [ -z "$schemaname" ]; then
            continue
        fi
        
        # Trim whitespace
        schemaname=$(echo "$schemaname" | xargs)
        sequencename=$(echo "$sequencename" | xargs)
        last_value=$(echo "$last_value" | xargs)
        
        # Only add if last_value is numeric and not null
        if [[ "$last_value" =~ ^-?[0-9]+$ ]]; then
            cat >> "$output_file" << EOF
-- Sequence: ${schemaname}.${sequencename}
-- Last value: ${last_value} (start: ${start_value}, increment: ${increment_by})
SELECT setval('"${schemaname}"."${sequencename}"', ${last_value}, true);

EOF
            sequence_count=$((sequence_count + 1))
            log_message "Sequence ${sequence_count} added"
        fi
    done
    
    # # If applying changes directly and sequences were found
    # if [ "$apply_changes" = true ] && [ $sequence_count -gt 0 ]; then
    #     log_message "  Applying changes to database ${db_name}..."
        
    #     # Extract the SQL commands for this database from the output file
    #     local db_sql=$(sed -n "/-- DATABASE: ${db_name}/,/-- DATABASE:/p" "$output_file" | sed '$d')
        
    #     if [ -n "$db_sql" ]; then
    #         if PGPASSFILE="$PGPASS_FILE" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -c "BEGIN; $(echo "$db_sql" | grep -v '^--' | grep -v '^\\c' | tr '\n' ';') COMMIT;" 2>/dev/null; then
    #             log_message "  ✓ Successfully applied ${sequence_count} sequence updates to ${db_name}"
    #         else
    #             log_message "  ✗ Failed to apply updates to ${db_name}"
    #             return 1
    #         fi
    #     fi
    # elif [ $sequence_count -gt 0 ]; then
    #     log_message "  ✓ Added ${sequence_count} sequences to script"
    # else
    #     log_message "  ⚠ No sequences found in database: ${db_name}"
    #     # Remove the database section if no sequences found
    #     sed -i "/-- DATABASE: ${db_name}/,/\\${db_name}/d" "$output_file"
    # fi
    
    echo "" >> "$output_file"
    return 0
}

# Function to test database connection
test_connection() {
    local host=$1
    local port=$2
    local user=$3
    local database=$4
    
    log_message "Testing connection to ${host}:${port} as user ${user}..."
    
    if PGPASSFILE="$PGPASS_FILE" psql -h "$host" -p "$port" -U "$user" -d "$database" -c "SELECT 1" > /dev/null 2>&1; then
        log_message "✓ Connection successful"
        return 0
    else
        log_message "✗ Connection failed"
        return 1
    fi
}

# Function to validate pgpass configuration
validate_pgpass() {
    if [[ ! -f "$PGPASS_FILE" ]]; then
        log_message "ERROR: pgpass.conf file not found at $PGPASS_FILE"
        echo "Please create $PGPASS_FILE with proper format:"
        echo "hostname:port:database:username:password"
        echo "Example: localhost:5432:*:monitoring_user:password123"
        exit 1
    fi
    
    # Check file permissions (should be 0600)
    local perms=$(stat -c "%a" "$PGPASS_FILE" 2>/dev/null || stat -f "%Lp" "$PGPASS_FILE" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        log_message "WARNING: pgpass.conf permissions are $perms, should be 600"
        echo "Run: chmod 600 $PGPASS_FILE"
    fi
}

# Function to generate final summary
generate_summary() {
    local output_file=$1
    local total_dbs=$2
    local success_count=$3
    local applied=$4
    
    local summary_file="${output_file}.summary.txt"
    
    cat > "$summary_file" << EOF
========================================
PostgreSQL Sequences Export Summary
========================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Total databases processed: ${total_dbs}
Successful exports: ${success_count}
Failed exports: $((total_dbs - success_count))
Applied directly to databases: ${applied}

Generated file: ${output_file}

========================================
To restore sequences on target database:
psql -h target_host -p target_port -U target_user -d postgres -f ${output_file}

Or for a specific database only:
psql -h target_host -p target_port -U target_user -d database_name -c "SELECT setval('sequence_name', value, true);"

========================================
EOF
    
    log_message "Summary report generated: ${summary_file}"
}

# Main execution
main() {
    # Parse command line arguments
    local host="$DEFAULT_HOST"
    local port="$DEFAULT_PORT"
    local user="$DEFAULT_USER"
    local database="$DEFAULT_DATABASE"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h)
                host="$2"
                shift 2
                ;;
            -p)
                port="$2"
                shift 2
                ;;
            -U)
                user="$2"
                shift 2
                ;;
            -d)
                database="$2"
                shift 2
                ;;
            -o)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --apply)
                APPLY_CHANGES=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    check_prerequisites
    validate_pgpass
    
    log_message "Starting PostgreSQL sequences export process"
    log_message "Cluster: ${host}:${port} as user ${user}"
    if [ "$APPLY_CHANGES" = true ]; then
        log_message "Mode: APPLY CHANGES DIRECTLY to databases"
    else
        log_message "Mode: GENERATE SCRIPT only"
    fi
    
    # Test connection
    if ! test_connection "$host" "$port" "$user" "$database"; then
        log_message "ERROR: Cannot connect to PostgreSQL cluster"
        exit 1
    fi
    
    # Initialize output file with header
    cat > "$OUTPUT_FILE" << EOF
-- =====================================================
-- PostgreSQL Sequences Restoration Script
-- =====================================================
-- Generated: $(date '+%Y-%m-%d %H:%M:%S')
-- Source Cluster: ${host}:${port}
-- User: ${user}
-- Description: Restores last_value for all sequences across all databases
-- =====================================================
-- HOW TO USE:
-- 1. Connect to target PostgreSQL cluster
-- 2. Run this script as superuser:
--    psql -h target_host -p target_port -U postgres -f ${OUTPUT_FILE}
-- =====================================================

BEGIN;

EOF
    
    # Get all databases
    log_message "Retrieving list of databases from cluster..."
    local databases=$(get_all_databases "$host" "$port" "$user" "$database")
    
    if [ -z "$databases" ]; then
        log_message "No user databases found in cluster"
        exit 0
    fi
    
    # Convert to array
    IFS=$'\n' read -rd '' -a db_array <<< "$databases"
    local total_dbs=${#db_array[@]}
    log_message "Found ${total_dbs} database(s): ${db_array[*]}"
    echo ""
    
    # Process each database
    local success_count=0
    local current_db=0
    
    for db_name in "${db_array[@]}"; do
        current_db=$((current_db + 1))
        echo "----------------------------------------"
        log_message "[${current_db}/${total_dbs}] Processing database: ${db_name}"
        
        if process_database_sequences "$db_name" "$host" "$port" "$user" "$OUTPUT_FILE" "$APPLY_CHANGES"; then
            success_count=$((success_count + 1))
        else
            log_message "  ✗ Failed to process ${db_name}"
        fi
    done
    
    # Add footer
    cat >> "$OUTPUT_FILE" << EOF

COMMIT;

-- =====================================================
-- END OF SCRIPT
-- =====================================================
-- Verification query (optional - run manually):
-- SELECT datname, schemaname, sequencename, last_value 
-- FROM pg_database d
-- CROSS JOIN LATERAL (
--    SELECT schemaname, sequencename, last_value 
--    FROM pg_sequences 
--    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
-- ) s
-- WHERE d.datname NOT IN ('template0', 'template1')
-- ORDER BY datname, schemaname, sequencename;
-- =====================================================
EOF
    
    echo "----------------------------------------"
    
    # Generate summary
    generate_summary "$OUTPUT_FILE" "$total_dbs" "$success_count" "$APPLY_CHANGES"
    
    # Final report
    log_message "Process completed!"
    log_message "Successfully processed: ${success_count}/${total_dbs} databases"
    log_message "Output file: ${OUTPUT_FILE}"
    
    if [ "$APPLY_CHANGES" = false ]; then
        echo ""
        log_message "To restore all sequences in a new cluster, run:"
        echo "PGPASSFILE=\"$PGPASS_FILE\" psql -h ${host} -p ${port} -U ${user} -d postgres -f ${OUTPUT_FILE}"
    fi
}

# Run main function
main "$@"