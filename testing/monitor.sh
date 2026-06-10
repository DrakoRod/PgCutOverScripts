#!/bin/bash

echo "=== MONITOREO DE REPLICACIÓN LÓGICA ==="
echo ""

echo "--- PUBLICACIONES EN PRIMARY ---"
docker exec postgres-primary psql -U admin -d postgres -c "SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete FROM pg_publication ORDER BY pubname;"

echo ""
echo "--- SUSCRIPCIONES EN REPLICA ---"
docker exec postgres-replica psql -U admin -d postgres -c "SELECT subname, subenabled, subslotname, subpublications FROM pg_subscription ORDER BY subname;"

echo ""
echo "--- SLOTS DE REPLICACIÓN EN PRIMARY ---"
docker exec postgres-primary psql -U admin -d postgres -c "SELECT slot_name, slot_type, database, active, restart_lsn FROM pg_replication_slots WHERE slot_type = 'logical' ORDER BY slot_name;"

echo ""
echo "--- WORKERS DE REPLICACIÓN ACTIVOS ---"
docker exec postgres-primary psql -U admin -d postgres -c "SELECT pid, application_name, state, sync_state FROM pg_stat_replication WHERE application_name LIKE 'sub_%';"

echo ""
echo "--- CONTEO DE REGISTROS POR BASE DE DATOS ---"
for i in $(seq 1 70); do
    DB_NAME="db_${i}"
    echo "--- $DB_NAME ---"
    docker exec postgres-primary psql -U admin -d "$DB_NAME" -c "SELECT 'table1' as table_name, COUNT(*) as count FROM table1 UNION ALL SELECT 'table2', COUNT(*) FROM table2;"
    echo ""
done