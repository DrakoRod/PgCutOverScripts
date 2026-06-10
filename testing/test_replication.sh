#!/bin/bash

echo "=== INSERTANDO DATOS DE PRUEBA EN PRIMARY ==="

# Insertar datos en todas las bases de datos del primary
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    echo "Insertando datos en $DB_NAME"
    
    docker exec postgres-primary psql -U admin -d "$DB_NAME" <<-EOSQL
        INSERT INTO table1 (data) VALUES 
            ('Test insert at $(date)'),
            ('Another test at $(date)');
            
        INSERT INTO table2 (description, value) VALUES 
            ('Replication test', 999),
            ('Another replication test', 888);
EOSQL
done

echo "Esperando 5 segundos para replicación..."
sleep 5

echo ""
echo "=== VERIFICANDO DATOS EN REPLICA ==="

# Verificar datos en replica
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    echo "--- Verificando $DB_NAME en replica ---"
    
    COUNT1=$(docker exec postgres-replica psql -U admin -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM table1;")
    COUNT2=$(docker exec postgres-replica psql -U admin -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM table2;")
    
    echo "  table1: $COUNT1 registros"
    echo "  table2: $COUNT2 registros"
    
    # Mostrar últimos registros
    docker exec postgres-replica psql -U admin -d "$DB_NAME" -c "SELECT id, data, created_at FROM table1 ORDER BY id DESC LIMIT 2;"
done

echo "=== PRUEBA COMPLETADA ==="