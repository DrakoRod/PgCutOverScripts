#!/bin/bash

# Script: generate_all_sequences.sh
# Description: Discovers all databases in PostgreSQL cluster and generates SQL scripts with sequence last values
# Usage: ./generate_all_sequences.sh [ -h HOST ] [ -p PORT ] [ -U USER ] [ -d DATABASE ]

# Default connection parameters
DEFAULT_HOST="localhost"
DEFAULT_PORT="5444"
DEFAULT_USER="postgres"
DEFAULT_DATABASE="postgres"
PGPASS_FILE="../_pgpass"  # Override for testing, ensure this file exists with proper credentials

# Output directory for generated scripts
OUTPUT_DIR="sequences_scripts"

# Function to display usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h HOST      PostgreSQL host (default: localhost)
    -p PORT      PostgreSQL port (default: 5444)
    -U USER      PostgreSQL user (default: postgres)
    -d DATABASE  Database to connect for discovering databases (default: postgres)
    -o DIR       Output directory (default: sequences_scripts)
    --help       Show this help message

The script uses .pgpass file for authentication.
Format of ~/.pgpass: hostname:port:database:username:password

Examples:
    $0                                    # Use default parameters
    $0 -h 192.168.1.100 -p 5444 -U admin  # Connect to remote server
    $0 -o /tmp/seq_scripts               # Change output directory
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

# Function to generate sequence script for a specific database
generate_sequence_script() {
    local db_name=$1
    local db_host=$2
    local db_port=$3
    local db_user=$4
    
    local output_file="${OUTPUT_DIR}/${db_name}_sequences.sql"
    
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
    
    # Create temporary file for sequences
    local temp_sequences="${output_file}.tmp"
    > "$temp_sequences"
    
    # Execute query and generate SQL script content
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
            cat >> "$temp_sequences" << EOF
-- Sequence: ${schemaname}.${sequencename}
-- Last value: ${last_value} (start: ${start_value}, increment: ${increment_by})
SELECT setval('${schemaname}.${sequencename}', ${last_value}, true);

EOF
        fi
    done
    
    # Check if any sequences were found
    if [ -s "$temp_sequences" ]; then
        # Add header to the script
        local final_file="${output_file}"
        cat > "$final_file" << EOF
-- =====================================================
-- Database: ${db_name}
-- Host: ${db_host}:${db_port}
-- User: ${db_user}
-- Generated: $(date '+%Y-%m-%d %H:%M:%S')
-- Description: Script to restore sequence last values
-- =====================================================
-- IMPORTANT: Run this script on the target database
-- to restore the original sequence positions
-- =====================================================

BEGIN;

EOF
        cat "$temp_sequences" >> "$final_file"
        cat >> "$final_file" << EOF

COMMIT;

-- =====================================================
-- Verification query (optional):
-- SELECT schemaname, sequencename, last_value 
-- FROM pg_sequences 
-- WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
-- ORDER BY schemaname, sequencename;
-- =====================================================
EOF
        
        local seq_count=$(grep -c "SELECT setval" "$final_file")
        log_message "  ✓ Generated script with ${seq_count} sequences"
        rm -f "$temp_sequences"
        return 0
    else
        log_message "  ⚠ No sequences found in database: ${db_name}"
        rm -f "$temp_sequences" "$output_file"
        return 1
    fi
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
        log_message "ERROR" "pgpass.conf file not found at $PGPASS_FILE"
        echo "Please create $PGPASS_FILE with proper format:"
        echo "hostname:port:database:username:password"
        echo "Example: localhost:5432:*:monitoring_user:password123"
        exit 1
    fi
    
    # Check file permissions (should be 0600)
    local perms=$(stat -c "%a" "$PGPASS_FILE" 2>/dev/null || stat -f "%Lp" "$PGPASS_FILE" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        log_message "WARNING" "pgpass.conf permissions are $perms, should be 600"
        echo "Run: chmod 600 $PGPASS_FILE"
    fi
}


# Function to generate summary report
generate_summary() {
    local output_dir=$1
    local total_dbs=$2
    local success_count=$3
    
    local summary_file="${output_dir}/summary_report.txt"
    
    cat > "$summary_file" << EOF
========================================
PostgreSQL Sequences Export Summary
========================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Total databases processed: ${total_dbs}
Successful exports: ${success_count}
Failed exports: $((total_dbs - success_count))

Generated files:
EOF
    
    if [ -d "$output_dir" ]; then
        for file in "$output_dir"/*_sequences.sql; do
            if [ -f "$file" ]; then
                local seq_count=$(grep -c "SELECT setval" "$file" 2>/dev/null || echo "0")
                local db_name=$(basename "$file" _sequences.sql)
                echo "  - ${db_name}: ${seq_count} sequences" >> "$summary_file"
            fi
        done
    fi
    
    cat >> "$summary_file" << EOF

========================================
To restore sequences on target database:
psql -h target_host -p target_port -U target_user -d database_name -f sequences_scripts/database_name_sequences.sql
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
                OUTPUT_DIR="$2"
                shift 2
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
    
    # Test connection
    if ! test_connection "$host" "$port" "$user" "$database"; then
        log_message "ERROR: Cannot connect to PostgreSQL cluster"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    if [ ! -d "$OUTPUT_DIR" ]; then
        log_message "ERROR: Cannot create output directory '${OUTPUT_DIR}'"
        exit 1
    fi
    
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
        
        if generate_sequence_script "$db_name" "$host" "$port" "$user"; then
            success_count=$((success_count + 1))
        else
            log_message "  ✗ Failed to generate script for ${db_name}"
        fi
    done
    
    echo "----------------------------------------"
    
    # Generate summary
    generate_summary "$OUTPUT_DIR" "$total_dbs" "$success_count"
    
    # Final report
    log_message "Process completed!"
    log_message "Successfully processed: ${success_count}/${total_dbs} databases"
    log_message "Output directory: ${OUTPUT_DIR}"
    
    # List generated files
    echo ""
    log_message "Generated SQL scripts:"
    if ls "${OUTPUT_DIR}"/*_sequences.sql 2>/dev/null; then
        echo ""
        log_message "To restore all sequences for a specific database, run:"
        echo "PGPASSFILE="$PGPASS_FILE" psql -h ${host} -p ${port} -U ${user} -d database_name -f ${OUTPUT_DIR}/database_name_sequences.sql"
    else
        log_message "No SQL scripts were generated"
    fi
}

# Run main function
main "$@"