#!/bin/bash

# Change the directory to the location where your *_sequences.sql files are located
DIRECTORIO="."

# Colors output
VERDE='\033[0;32m'
ROJO='\033[0;31m'
NC='\033[0m' # Sin color

echo "=== Searching files *_sequences.sql in $DIRECTORIO ==="
echo

# Contador de archivos encontrados
CONTADOR=0

# Recorrer todos los archivos que terminan en _sequences.sql
for archivo in "$DIRECTORIO"/*_sequences.sql; do
    # Verificar si existe al menos un archivo (evitar error cuando no hay matches)
    if [ ! -f "$archivo" ]; then
        echo -e "${ROJO}No se encontraron archivos *_sequences.sql en $DIRECTORIO${NC}"
        exit 1
    fi

    # Extract the filename without the path
    nombre_archivo=$(basename "$archivo")

    # Extract the database name by removing the suffix _sequences.sql
    # Using sed to remove the suffix _sequences.sql
    base_datos=$(echo "$nombre_archivo" | sed 's/_sequences\.sql$//')

    # Verify if the database name was successfully extracted
    if [ -z "$base_datos" ]; then
        echo -e "${ROJO}Error: Failed to extract database name from: $nombre_archivo${NC}"
        continue
    fi

    echo -e "${VERDE}File found:${NC} $nombre_archivo"
    echo -e "${VERDE}Database detected:${NC} $base_datos"
    echo -e "${VERDE}Executing:${NC} psql -h localhost -d $base_datos -f $archivo"
    echo "---"

    # execute the SQL file using psql
    psql -h localhost -d "$base_datos" -f "$archivo"

    # Verificar si el comando fue exitoso
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}✓ Success: $nombre_archivo the file imported to $base_datos${NC}"
    else
        echo -e "${ROJO}✗ Error: Failed to import $nombre_archivo to $base_datos${NC}"
    fi

    echo "----------------------------------------"
    CONTADOR=$((CONTADOR + 1))
done

echo
echo -e "${VERDE}=== Process completed ===${NC}"
echo "Total of files processed: $CONTADOR"