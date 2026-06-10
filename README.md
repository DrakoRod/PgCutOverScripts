# PostgreSQL Logical Replication Monitor

A comprehensive Bash script to monitor logical replication slots across multiple PostgreSQL databases on the same server using pgpass.conf authentication.

## Features

- 🔍 **Multi-database monitoring** - Monitor up to 70+ databases simultaneously
- 📊 **Real-time metrics** - Track replication lag, slot status, and performance indicators
- 🚨 **Automated alerts** - Email notifications for critical conditions
- 📈 **Threshold-based warnings** - Customizable thresholds for lag and slot health
- 🔄 **Continuous monitoring** - Daemon mode for real-time surveillance
- 📝 **Detailed reporting** - Generate comprehensive reports with color-coded output
- 🗄️ **Stale slot detection** - Identify inactive replication slots
- 🔐 **Secure authentication** - Uses PostgreSQL pgpass.conf for password management

## Prerequisites

- PostgreSQL 10+ (with logical replication support)
- Bash 4.0+
- PostgreSQL client tools (psql)
- Sufficient disk space for logs

### Install Dependencies

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install postgresql-client mailutils

# RHEL/CentOS
sudo yum install postgresql mailx

# Arch Linux
sudo pacman -S postgresql mailutils
```

In the database create the next user to generate the process

```sql
CREATE USER rep_monitoring_user IDENTIFIED BY "{superpass}" VALID UNTIL '2026-06-11 17:22:13.799278-06' IN ROLE pg_monitor;
```


## Installation

To install the monitoring lag script do you need follow the next steps: 

### 1. Download the Script

```bash
# Download to /usr/local/bin
sudo curl -o /usr/local/bin/monitor_logical_replication.sh https://github.com/DrakoRod/PgCutOverScripts/blob/main/monitor_logical_replication.sh

# Make it executable
sudo chmod +x /usr/local/bin/monitor_logical_replication.sh
```

Or create the script manually using the provided code.

### 2. Configure pgpass.conf

Create or edit the PostgreSQL password file:


```bash
# Create pgpass.conf in user's home directory
cat > ~/.pgpass.conf <<EOF
# Format: hostname:port:database:username:password
localhost:5432:*:rep_monitoring_user:{superpass}

# Or specify individual databases
localhost:5432:db1:rep_monitoring_user:{superpass}
localhost:5432:db2:rep_monitoring_user:{superpass}
EOF

# Set correct permissions (must be 600)
chmod 600 ~/.pgpass.conf
```

### 3. Configure the Script

Edit the script to customize:

```bash
# Edit configuration variables
vim /usr/local/bin/monitor_logical_replication.sh
```

Key configuration options:

```bash
# Thresholds
WARNING_BACKEND_PERCENT=80        # Warning threshold for backend percentage
CRITICAL_BACKEND_PERCENT=95       # Critical threshold
WARNING_SPILL_PERCENT=70          # Spill file warning threshold
CRITICAL_SPILL_PERCENT=85         # Spill file critical threshold
MAX_LAG_SECONDS=300               # Maximum allowed replication lag in seconds

# Log file location
LOG_FILE="/var/log/postgresql/replication_monitor.log"
```

### 4. Configure Database List

Update the get_databases() function with your database names:

```bash
get_databases() {
    # Option 1: Hardcode database names
    cat <<EOF
customer_db
orders_db
inventory_db
analytics_db
# ... up to 70 databases
EOF
    
    # Option 2: Query all databases automatically
    # PGPASSFILE="$PGPASS_FILE" psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'template0', 'template1') ORDER BY datname;"
}
```

## Usage

### Basic Commands

```
# Run one-time check
./monitor_logical_replication.sh --check

# Run with custom pgpass location
./monitor_logical_replication.sh --check --pgpass /etc/postgresql/.pgpass

# Continuous monitoring (daemon mode)
./monitor_logical_replication.sh --daemon --interval 60

# Show help
./monitor_logical_replication.sh --help
```

### Command Line Options

| Option | Description | Default | 
| --- | --- | --- |
| `-c`, `--check` | Run immediate check and generate report	Default mode | - |
| `-d`, `--daemon` |	Run as daemon with continuous monitoring	| - |
| `-i`, `--interval N` |	Monitoring interval in seconds (daemon mode)	| 300 |
| `-p`, `--pgpass FILE` |	Path to pgpass.conf file	| ~/.pgpass.conf |
| `-h`, `--help` |	Show help message	| - |

## Monitoring Metrics

The script monitors the following metrics:

### Replication Slots

- Slot name and type (logical/physical)
- Active/Inactive status
- Current database
- Plugin type (pgoutput, wal2json, etc.)
- Xmin horizon

### Lag Metrics
- Lag in bytes (human-readable format)
- Lag in raw bytes
- Estimated lag in seconds
- Replay lag time

### Health Indicators
- Stale slot detection (>24 hours inactive)
- Connection errors
- Warning and critical condition counts

### Output Examples

Console Output (Color-coded)

```bash
=========================================
PostgreSQL Logical Replication Monitor
Report Date: 2024-01-15 14:30:25
=========================================

DATABASE SUMMARY
-----------------------------------------
Database             | Slot Name                | Status     | Lag (bytes)    | Lag (seconds)
----------------------------------------------------------------------------------------------------
customer_db          | customer_slot_1         | Active     | 0 bytes        | 0s
orders_db            | orders_east_slot        | Active     | 2.5 MB         | 2s
inventory_db         | inventory_slot          | Inactive   | 125 MB         | 45s
analytics_db         | analytics_slot          | Active     | 0 bytes        | 0s

=========================================
SUMMARY
=========================================
Total Databases Checked: 70
Databases with Errors: 0
Warning Conditions: 1
Critical Conditions: 0
Stale Slots Found: 0
```

### Log File Output

```bash
tail -f /var/log/postgresql/replication_monitor.log

2024-01-15 14:30:25 [INFO] Starting PostgreSQL Replication Monitor
2024-01-15 14:30:25 [INFO] Checking database: customer_db
2024-01-15 14:30:26 [WARNING] Inactive replication slot: inventory_slot on database: inventory_db
2024-01-15 14:30:30 [INFO] Report saved to: /tmp/pg_replication_monitor/replication_report_20240115_143030.txt
```

## Automation
### Cron Job Setup

Run checks every 5 minutes via cron:

```bash
# Edit crontab
crontab -e

# Add this line
*/5 * * * * /usr/local/bin/monitor_logical_replication.sh --check --email dba@company.com >> /var/log/pg_monitor_cron.log 2>&1
```

### Systemd Service (Daemon Mode)

Create a systemd service for continuous monitoring:

```bash 
# Create service file
sudo cat > /etc/systemd/system/pg-replication-monitor.service <<EOF
[Unit]
Description=PostgreSQL Logical Replication Monitor
After=network.target postgresql.service

[Service]
Type=simple
User=postgres
ExecStart=/usr/local/bin/monitor_logical_replication.sh --daemon --interval 300 --email dba@company.com
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable pg-replication-monitor
sudo systemctl start pg-replication-monitor

# Check status
sudo systemctl status pg-replication-monitor
```

## Troubleshooting

### Common Issues

#### 1. Connection Failures

```text
Error: Cannot connect to database: dbname
```

**Solution**:
- Verify pgpass.conf exists and has correct permissions (600)
- Test connection manually: `PGPASSFILE=~/.pgpass.conf psql -h localhost -d dbname -c "SELECT 1"`
- Check PostgreSQL is running: `sudo systemctl status postgresql`

#### 2. Permission Denied

```text
pgpass.conf permissions are 644, should be 600
```

**Solution**:
```bash
chmod 600 ~/.pgpass.conf
```

#### 3. Missing psql Client
```text
Error: Missing dependencies: psql
```
**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get install postgresql-client

# RHEL/CentOS
sudo yum install postgresql
```

### 4. Mail Not Working
```text
send-mail: Cannot open mail:25
```

**Solution**:
- Configure mail transfer agent (postfix, sendmail, etc.)
- Or disable email alerts by setting `ALERT_EMAIL=""`
