#!/bin/bash

echo "=== LIMPIANDO RECURSOS DE REPLICACIÓN ==="

# Eliminar suscripciones en replica
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    SUB_NAME="sub_${DB_NAME}"
    
    echo "Eliminando suscripción $SUB_NAME"
    docker exec postgres-replica psql -U admin -d "$DB_NAME" -c "DROP SUBSCRIPTION IF EXISTS $SUB_NAME;" 2>/dev/null || true
done

# Eliminar slots de replicación en primary
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    SLOT_NAME="${DB_NAME}_sub_${DB_NAME}"
    
    echo "Eliminando slot $SLOT_NAME"
    docker exec postgres-primary psql -U admin -d postgres -c "SELECT pg_drop_replication_slot('$SLOT_NAME');" 2>/dev/null || true
done

# Eliminar publicaciones en primary
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    PUB_NAME="${DB_NAME}_pub"
    
    echo "Eliminando publicación $PUB_NAME"
    docker exec postgres-primary psql -U admin -d "$DB_NAME" -c "DROP PUBLICATION IF EXISTS $PUB_NAME;" 2>/dev/null || true
done

echo "Limpieza completada"