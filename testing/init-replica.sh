#!/bin/bash
set -e

echo "Waiting for the primary to be fully ready..."
sleep 10

echo "Configuring PostgreSQL Replica..."

# Configurar parámetros
psql -v ON_ERROR_STOP=1 -d postgres -U "$POSTGRES_USER" <<-EOSQL
    ALTER SYSTEM SET max_worker_processes = 150;
    ALTER SYSTEM SET max_replication_slots = 150;
    ALTER SYSTEM SET max_wal_senders = 150;
    ALTER SYSTEM SET max_logical_replication_workers = 150;
    ALTER SYSTEM SET max_sync_workers_per_subscription = 8;
    SELECT pg_reload_conf();
EOSQL

echo "Restarting PostgreSQL configuration..."
pg_ctl -D "$PGDATA" -m fast -w restart

# Crear 70 bases de datos en replica
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    echo "Creating Database in Replica: $DB_NAME"
    
    # Crear base de datos
    psql -v ON_ERROR_STOP=1 -d postgres -U "$POSTGRES_USER" <<-EOSQL
        CREATE DATABASE $DB_NAME;
EOSQL
    
    # Crear las mismas tablas en replica
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d "$DB_NAME" <<-EOSQL
        CREATE TABLE IF NOT EXISTS table1 (
            id SERIAL PRIMARY KEY,
            data TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        
        CREATE TABLE IF NOT EXISTS table2 (
            id SERIAL PRIMARY KEY,
            description TEXT,
            value INTEGER DEFAULT 0,
            status VARCHAR(20) DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
EOSQL
done

# Esperar un poco para asegurar que todas las bases están listas
sleep 5

# Crear suscripciones para cada base de datos
echo "Creando suscripciones para replicación lógica..."
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    SUB_NAME="sub_${DB_NAME}"
    CONN_STRING="host=postgres-primary port=5432 dbname=${DB_NAME} user=admin password=admin123"
    
    echo "Creando suscripción $SUB_NAME para $DB_NAME"
    
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d "$DB_NAME" <<-EOSQL
        CREATE SUBSCRIPTION $SUB_NAME
        CONNECTION '$CONN_STRING'
        PUBLICATION ${DB_NAME}_pub
        WITH (copy_data = true, enabled = true, create_slot = true);
EOSQL
    
    echo "Suscripción $SUB_NAME creada exitosamente"
done

echo "Replica configuration completed: 70 subscriptions created"