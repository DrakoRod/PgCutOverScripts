#!/bin/bash

# Script: monitor_logical_replication.sh
# Description: Monitor logical replication slots across multiple PostgreSQL databases
# Usage: ./monitor_logical_replication.sh [options]

# Configuration
# PGPASS_FILE="$HOME/.pgpass" # Path to pgpass file for authentication
PGPASS_FILE="./_pgpass"  # Override for testing, ensure this file exists with proper credentials
PGUSER="rep_monitoring_user"  # default user. Ensure this user has appropriate permissions for monitoring, in the readme section 
PGHOST="localhost"
PGPORT="5444"   # Adjust on your primary server
LOG_FILE="/tmp/replication_monitor.log" # Or use, but check the permissions /var/log/postgresql/replication_monitor.log
ALERT_EMAIL=""  # Set to empty string to disable email alerts
TEMP_DIR="/tmp/pg_replication_monitor"

# Thresholds (in megabytes and percentages)
WARNING_BACKEND_PERCENT=80
CRITICAL_BACKEND_PERCENT=95
WARNING_SPILL_PERCENT=70
CRITICAL_SPILL_PERCENT=85
MAX_LAG_SECONDS=300  # Maximum allowed replication lag in seconds

# Colors for console output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create temp directory if it doesn't exist
mkdir -p "$TEMP_DIR"

# Logging function
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$timestamp [$level] $message" | tee -a "$LOG_FILE"
}

# Send alert function
send_alert() {
    local subject=$1
    local body=$2
    
    if [[ -n "$ALERT_EMAIL" ]]; then
        echo "$body" | mail -s "$subject" "$ALERT_EMAIL"
        log_message "INFO" "Alert sent to $ALERT_EMAIL: $subject"
    fi
}

# Function to get databases list
get_databases() {
    # You can either hardcode database names or query them
    # Method 1: Hardcoded list (modify as needed)
#    cat <<EOF
#database1
#database2
#database3
#EOF
    
# Method 2: Dynamically get all databases
PGPASSFILE="$PGPASS_FILE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'template0', 'template1') ORDER BY datname;"
}

# Function to check replication slots for a specific database
check_replication_slots() {
    local dbname=$1
    local sql_query=$(cat <<-EOF
        SELECT 
            slot_name,
            slot_type,
            database,
            active,
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) as lag_bytes,
            pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as lag_bytes_raw,
            confirmed_flush_lsn,
            restart_lsn,
            CASE 
                WHEN active THEN 'Active'
                ELSE 'Inactive'
            END as status,
            coalesce(plugin, 'N/A') as plugin,
            coalesce(xmin::text, 'N/A') as xmin
        FROM pg_replication_slots 
        WHERE database = '$dbname'
        ORDER BY slot_name;
EOF
    )
    
    PGPASSFILE="$PGPASS_FILE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$dbname" -t -A -F'|' -c "$sql_query" 2>/dev/null
}

# Function to check lag and performance metrics
check_replication_performance() {
    local dbname=$1
    local sql_query=$(cat <<-EOF
        SELECT 
            slot_name,
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) as lag_bytes,
            pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as lag_bytes_raw,
            extract(epoch from now() - confirmed_flush_lsn_time) as lag_seconds
        FROM pg_replication_slots 
        CROSS JOIN LATERAL (SELECT now() - '2024-01-01' as confirmed_flush_lsn_time) x
        WHERE database = '$dbname';
EOF
    )
    
    # Alternative query for PostgreSQL 10+
    local sql_query_v2=$(cat <<-EOF
        WITH lag AS (
            SELECT 
                slot_name,
                pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) as lag_bytes,
                case 
                    when active then 0
                    else extract(epoch from now() - pg_last_xact_replay_timestamp())
                end as replay_lag
            FROM pg_replication_slots
            WHERE database = '$dbname'
        )
        SELECT 
            slot_name,
            pg_size_pretty(lag_bytes) as lag_pretty,
            lag_bytes,
            replay_lag
        FROM lag;
EOF
    )
    
    PGPASSFILE="$PGPASS_FILE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$dbname" -t -A -F'|' -c "$sql_query_v2" 2>/dev/null
}

# Function to check for stale replication slots
check_stale_slots() {
    local dbname=$1
    local stale_threshold_hours=24
    
    local sql_query=$(cat <<-EOF
        SELECT 
            slot_name,
            database,
            active,
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag_bytes,
            now() - pg_last_xact_replay_timestamp() as inactive_duration
        FROM pg_replication_slots
        WHERE database = '$dbname' 
        AND NOT active
        AND now() - pg_last_xact_replay_timestamp() > interval '$stale_threshold_hours hours';
EOF
    )
    
    PGPASSFILE="$PGPASS_FILE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$dbname" -t -A -F'|' -c "$sql_query" 2>/dev/null
}

# Function to generate report
generate_report() {
    local report_file="$TEMP_DIR/replication_report_$(date +%Y%m%d_%H%M%S).txt"
    local warning_count=0
    local critical_count=0
    local stale_count=0
    local error_count=0
    
    {
        echo "========================================="
        echo "PostgreSQL Logical Replication Monitor"
        echo "Report Date: $(date)"
        echo "========================================="
        echo
        echo "DATABASE SUMMARY"
        echo "-----------------------------------------"
        
        # Header for table
        printf "%-20s | %-25s | %-10s | %-15s | %-15s\n" "Database" "Slot Name" "Status" "Lag (bytes)" "Lag (seconds)"
        printf "%s\n" "----------------------------------------------------------------------------------------------------"
        
        while IFS= read -r dbname; do
            if [[ -z "$dbname" ]]; then
                continue
            fi

            dbname=$(echo "$dbname" | xargs)
            
            log_message "INFO" "Checking database: $dbname"
            
            # Check connectivity first
            if ! PGPASSFILE="$PGPASS_FILE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d"$dbname" -c "SELECT 1" &>/dev/null; then
                log_message "ERROR" "Cannot connect to database: $dbname"
                printf "%-20s | %-25s | %-10s | %-15s | %-15s\n" "$dbname" "ERROR" "Failed" "N/A" "Connection failed"
                ((error_count++))
                continue
            fi
            
            # Check replication slots
            while IFS='|' read -r slot_name slot_type database active lag_bytes lag_bytes_raw flush_lsn restart_lsn status plugin xmin; do
                if [[ -n "$slot_name" ]]; then
                    # Clean whitespace
                    slot_name=$(echo "$slot_name" | xargs)
                    status=$(echo "$status" | xargs)
                    lag_bytes=$(echo "$lag_bytes" | xargs)
                    
                    # Check lag (simplified for demo)
                    lag_seconds=0
                    if [[ "$lag_bytes_raw" -gt 0 ]]; then
                        lag_seconds=$((lag_bytes_raw / 1024 / 1024))  # Rough estimate: MB to seconds
                    fi
                    
                    # Determine status with colors
                    if [[ "$status" == "Active" ]]; then
                        color=$GREEN
                    else
                        color=$YELLOW
                        ((warning_count++))
                        log_message "WARNING" "Inactive replication slot: $slot_name on database: $dbname"
                    fi
                    
                    # Check for high lag
                    if [[ "$lag_bytes_raw" -gt $((MAX_LAG_SECONDS * 1024 * 1024)) ]]; then
                        color=$RED
                        ((critical_count++))
                        log_message "CRITICAL" "High replication lag on $slot_name: $lag_bytes"
                    fi
                    
                    printf "${color}%-20s | %-25s | %-10s | %-15s | %-15s${NC}\n" \
                        "$dbname" "$slot_name" "$status" "$lag_bytes" "${lag_seconds}s"
                fi
            done < <(check_replication_slots "$dbname")
            
            # Check for stale slots
            while IFS='|' read -r slot_name database active lag_bytes inactive_duration; do
                if [[ -n "$slot_name" ]]; then
                    ((stale_count++))
                    log_message "WARNING" "Stale replication slot detected: $slot_name on $dbname (inactive for $inactive_duration)"
                fi
            done < <(check_stale_slots "$dbname")

            echo ""
            
        done < <(get_databases)
        
        echo
        echo "========================================="
        echo "SUMMARY"
        echo "========================================="
        echo "Total Databases Checked: $(get_databases | wc -l)"
        echo "Databases with Errors: $error_count"
        echo "Warning Conditions: $warning_count"
        echo "Critical Conditions: $critical_count"
        echo "Stale Slots Found: $stale_count"
        echo
        echo "Monitoring Thresholds:"
        echo "- Max acceptable lag: ${MAX_LAG_SECONDS}s"
        echo "- Stale slot threshold: 24 hours"
        
    } | tee "$report_file"
    
    # Send alert if issues found
    if [[ $warning_count -gt 0 ]] || [[ $critical_count -gt 0 ]] || [[ $error_count -gt 0 ]]; then
        local subject="PostgreSQL Replication Alert - $(hostname)"
        local body="Issues detected in logical replication monitoring. Check report: $report_file"
        send_alert "$subject" "$body"
    fi
    
    echo "Report saved to: $report_file"
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

# Function to check required tools
check_dependencies() {
    local deps=("psql" "mail" "stat")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing dependencies: ${missing_deps[*]}"
        echo "Please install: apt-get install postgresql-client mailutils (on Debian/Ubuntu)"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    -c, --check       Run immediate check and report
    -d, --daemon      Run as daemon with continuous monitoring
    -i, --interval N  Monitoring interval in seconds (default: 300)
    -e, --email EMAIL Set alert email address
    -p, --pgpass FILE Path to pgpass.conf file (default: ~/.pgpass.conf)
    -h, --help        Show this help message

Examples:
    $0 --check
    $0 --daemon --interval 60 --email admin@example.com
    $0 --check --pgpass /etc/postgresql/.pgpass

EOF
}

# Function to run continuous monitoring
run_daemon() {
    local interval=$1
    
    log_message "INFO" "Starting daemon mode with interval: ${interval}s"
    
    # Create PID file
    echo $$ > "$TEMP_DIR/monitor.pid"
    
    # Trap exit signals
    trap 'rm -f "$TEMP_DIR/monitor.pid"; log_message "INFO" "Daemon stopped"; exit 0' INT TERM
    
    while true; do
        generate_report
        log_message "INFO" "Sleeping for $interval seconds..."
        sleep "$interval"
    done
}

# Main execution
main() {
    local mode="check"
    local interval=300
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--check)
                mode="check"
                shift
                ;;
            -d|--daemon)
                mode="daemon"
                shift
                ;;
            -i|--interval)
                interval="$2"
                shift 2
                ;;
            -e|--email)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            -p|--pgpass)
                PGPASS_FILE="$2"
                shift 2
                ;;
            -h|--help)
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
    
    # Validate setup
    check_dependencies
    validate_pgpass
    
    # Run appropriate mode
    if [[ "$mode" == "check" ]]; then
        generate_report
    elif [[ "$mode" == "daemon" ]]; then
        run_daemon "$interval"
    fi
}

# Run main function with all arguments
main "$@"