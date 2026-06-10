#!/bin/bash
set -e

echo "Configuring PostgreSQL Primary..."

# Configurar parámetros de replicación
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    ALTER SYSTEM SET wal_level = logical;
    ALTER SYSTEM SET max_worker_processes = 150;
    ALTER SYSTEM SET max_replication_slots = 150;
    ALTER SYSTEM SET max_wal_senders = 150;
    ALTER SYSTEM SET max_logical_replication_workers = 150;
    ALTER SYSTEM SET max_sync_workers_per_subscription = 8;
EOSQL

echo "Reloading PostgreSQL configuration..."
pg_ctl -D "$PGDATA" -m fast -w restart

# Crear 70 bases de datos
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    echo "Creating Database: $DB_NAME"
    
    # Crear base de datos
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE DATABASE $DB_NAME;
EOSQL
    
    # Crear tablas en la base de datos
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d "$DB_NAME" <<-EOSQL
        -- Tabla 1
        CREATE TABLE IF NOT EXISTS table1 (
            id SERIAL PRIMARY KEY,
            data TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Tabla 2
        CREATE TABLE IF NOT EXISTS table2 (
            id SERIAL PRIMARY KEY,
            description TEXT,
            value INTEGER DEFAULT 0,
            status VARCHAR(20) DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        -- Insertar datos iniciales
        INSERT INTO table1 (data) VALUES 
            ('Initial data 1 for $DB_NAME'),
            ('Initial data 2 for $DB_NAME'),
            ('Initial data 3 for $DB_NAME');
            
        INSERT INTO table2 (description, value) VALUES 
            ('Description 1 for $DB_NAME', 100),
            ('Description 2 for $DB_NAME', 200),
            ('Description 3 for $DB_NAME', 300);
        
        -- Crear publicación para replicación lógica
        CREATE PUBLICATION ${DB_NAME}_pub FOR TABLE table1, table2;
EOSQL
    
    echo "Database $DB_NAME created successfully with tables and publication."
done

echo "Primary configuration completed: 70 databases created"