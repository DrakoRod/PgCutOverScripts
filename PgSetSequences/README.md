# PostgreSQL Sequences Backup & Restore Tool

A bash script to backup all sequence last values from multiple PostgreSQL databases and generate a single restoration script, with optional direct application capability.

## Features

- 🔍 **Auto-discovery**: Automatically finds all user databases in the cluster
- 📦 **Single Output**: Generates one consolidated SQL script for all databases
- 🚀 **Direct Apply**: Option to apply changes directly to source databases
- 🔐 **Secure Authentication**: Uses `.pgpass` file for password management
- 📊 **Detailed Summary**: Provides comprehensive execution reports
- 🛡️ **Safe Transactions**: Wraps all changes in BEGIN/COMMIT blocks

## Prerequisites

- PostgreSQL client (`psql`) installed
- Bash 4.0 or higher
- Read access to `pg_sequences` and `pg_database` system tables
- `.pgpass` file configured for authentication

## Installation

### 1. Download the Script

```bash
curl -O https://your-server/generate_sequences_script.sh
# or
wget https://your-server/generate_sequences_script.sh
```

### 2. Make it Executable

```bash
chmod +x generate_sequences_script.sh
```

### 3. Configure .pgpass File

Create or edit the `.pgpass` file in the script directory (or custom location):

```bash
cat > ../_pgpass << EOF
localhost:5444:postgres:postgres:your_password
localhost:5444:*:monitoring_user:password123
EOF

# Set proper permissions (MUST be 600)
chmod 600 ../_pgpass
```

`.pgpass` format:

```tex
hostname:port:database:username:password
```

- Use `*` as wildcard for database/port
- Location is configurable via `PGPASS_FILE` variable in script

## Usage

### Basic Syntax

```bash
./generate_sequences_script.sh [OPTIONS]
```

### Options

| Option     | Description                         | Default                   |
|------------|-------------------------------------|---------------------------|
| -h HOST    | PostgreSQL host                     | localhost                 |
| -p PORT    | PostgreSQL port                     | 5444                      |
| -U USER    | PostgreSQL user                     | postgres                  |
| -d DATABASE| Database for discovery              | postgres                  |
| -o FILE    | Output SQL file                     | restore_all_sequences.sql |
| --apply    | Apply changes directly to databases | false                     |
| --help     | Show help message                   | (none)                    |

Examples

### 1. Generate Restoration Script Only

```bash
./generate_sequences_script.sh 
```

This creates `restore_all_sequences.sql` that can be imported into a new cluster.

### 2. Generate Script with Custom Parameters

```bash
./generate_sequences_script.sh \
  -h 192.168.1.100 \
  -p 5432 \
  -U admin \
  -o /backups/sequences_20240115.sql
```

### 3. Apply Changes Directly to Databases
```bash
./generate_sequences_script.sh --apply
```

⚠️ Warning: This will modify sequence last values in the source databases.

### 4. Remote Server with Custom pgpass

```bash
PGPASS_FILE="/home/user/.pgpass" ./generate_sequences_script.sh \
  -h production-db.example.com \
  -p 5432 \
  -U replicator
```

## Output Files

### Main SQL Script (`restore_all_sequences.sql`)

```sql
-- =====================================================
-- PostgreSQL Sequences Restoration Script
-- =====================================================
-- Generated: 2024-01-15 10:30:45
-- Source Cluster: localhost:5444
-- Description: Restores last_value for all sequences
-- =====================================================

BEGIN;

-- =====================================================
-- DATABASE: customers_db
-- =====================================================

\c customers_db

-- Sequence: public.users_id_seq
-- Last value: 1024 (start: 1, increment: 1)
SELECT setval('public."users_id_seq"', 1024, true);

-- Sequence: public.orders_id_seq
-- Last value: 550 (start: 1, increment: 1)
SELECT setval('public."orders_id_seq"', 550, true);

-- =====================================================
-- DATABASE: products_db
-- =====================================================

\c products_db

-- Sequence: inventory.products_id_seq
-- Last value: 2048 (start: 1, increment: 1)
SELECT setval('inventory."products_id_seq"', 2048, true);

COMMIT;
```

### Summary Report (`restore_all_sequences.sql.summary.txt`)

```text
========================================
PostgreSQL Sequences Export Summary
========================================
Date: 2024-01-15 10:30:45
Total databases processed: 3
Successful exports: 3
Failed exports: 0
Applied directly to databases: false

Generated file: restore_all_sequences.sql

========================================
To restore sequences on target database:
psql -h target_host -p target_port -U postgres -f restore_all_sequences.sql
========================================
```

## Restoring Sequences in a New Cluster

### Method 1: Full Restoration (All Databases)

```bash
psql -h new-cluster-host \
     -p 5432 \
     -U postgres \
     -f restore_all_sequences.sql
```

### Method 2: Restore Specific Database Only
```bash
# Extract and restore only the customers_db section
sed -n '/-- DATABASE: customers_db/,/-- DATABASE:/p' restore_all_sequences.sql | \
  psql -h new-cluster-host -p 5432 -U postgres -d customers_db
```


### Method 3: Restore Single Sequence
```bash
psql -h new-cluster-host -p 5432 -U postgres -d customers_db -c \
  "SELECT setval('public.users_id_seq', 1024, true);"
```

## Verification

### Check Restored Values

After restoration, verify the sequence values:

```sql
-- For a specific database
\c your_database_name

SELECT schemaname, sequencename, last_value 
FROM pg_sequences 
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, sequencename;
```

### Cross-Database Verification

```sql
SELECT 
    datname,
    schemaname,
    sequencename,
    last_value 
FROM pg_database d
CROSS JOIN LATERAL (
    SELECT schemaname, sequencename, last_value 
    FROM pg_sequences 
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
) s
WHERE d.datname NOT IN ('template0', 'template1')
ORDER BY datname, schemaname, sequencename;
```

## Troubleshooting

### Common Issues

#### 1. Connection Failed

```text
ERROR: Failed to connect to database cluster
```

**Solution**:
- Verify `.pgpass` file exists and has correct permissions (600)
- Check PostgreSQL is running: `pg_isready -h localhost -p 5444`
- Validate credentials in `.pgpass`

#### 2. psql Command Not Found

```text
ERROR: psql command not found
```

**Solution**:

```bash
# Ubuntu/Debian
sudo apt-get install postgresql-client

# RHEL/CentOS
sudo yum install postgresql

# MacOS
brew install libpq
```


#### 3. Permission Denied on .pgpass

```text
WARNING: pgpass.conf permissions are 644, should be 600
```
**Solution**:
```bash
chmod 600 ../_pgpass
```

#### 4. No Sequences Found
```text
⚠ No sequences found in database: test_db
```

**Solution**:
- Verify database actually has sequences
- Check user has permission to read `pg_sequences`
- Ensure sequences are in non-system schemas

## Security Considerations

1. `.pgpass` Permissions: Always set to `600` (owner read/write only)
2. Network Security: Use SSH tunneling for remote connections
3. Audit Trail: Script logs all actions with timestamps
4. Transaction Safety: All changes are wrapped in transactions
5. Minimal Privileges: User only needs `SELECT` on system tables for backup


## Best Practices

### For Backup (Recommended)

```bash
# Generate script only, don't apply
./generate_sequences_script.sh -o /backups/sequences_$(date +%Y%m%d).sql

# Store in version control or backup system
git add /backups/sequences_*.sql
```

### For Migration

1. Backup source sequences:

```bash
./generate_sequences_script.sh -o /tmp/source_sequences.sql
```

2. Transfer file to new cluster:

```bash
scp /tmp/source_sequences.sql user@new-cluster:/tmp/
```

3. Restore on new cluster:

```bash
psql -h new-cluster -f /tmp/source_sequences.sql
```

## For Disaster Recovery

```bash
# Backup before any major operation
./generate_sequences_script.sh -o /backups/pre_migration_$(date +%Y%m%d_%H%M%S).sql

# Perform migration...
# If rollback needed:
psql -f /backups/pre_migration_*.sql
```

## Script Customization

### Modify Default Values

Edit the script to change defaults:

```bash
DEFAULT_HOST="localhost"
DEFAULT_PORT="5444"
DEFAULT_USER="postgres"
DEFAULT_DATABASE="postgres"
PGPASS_FILE="../_pgpass"
OUTPUT_FILE="restore_all_sequences.sql"
```

### Exclude Specific Databases

Modify the `get_all_databases()` function:

```bash
local sql_query="
SELECT datname 
FROM pg_database 
WHERE datistemplate = false 
AND datname NOT IN ('postgres', 'template0', 'template1', 'monitoring_db', 'test_db')
ORDER BY datname;
"
```

## Contributing

Feel free to submit issues and enhancement requests!
