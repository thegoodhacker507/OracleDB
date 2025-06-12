#!/bin/bash
# =====================================================
# Oracle Database Health Check Script
# =====================================================

# Variables
ORACLE_SID=${ORACLE_SID:-FREE}
ORACLE_PDB=${ORACLE_PDB:-FREEPDB1}
ORACLE_PWD=${ORACLE_PWD:-Oracle123!}

# Función para verificar la salud de Oracle
check_oracle_health() {
    # Verificar si el listener está corriendo
    if ! pgrep -f tnslsnr > /dev/null; then
        echo "UNHEALTHY: Oracle Listener no está corriendo"
        return 1
    fi

    # Verificar conexión a la CDB
    if ! echo "SELECT 1 FROM DUAL;" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_SID} as sysdba >/dev/null 2>&1; then
        echo "UNHEALTHY: No se puede conectar a la CDB"
        return 1
    fi

    # Verificar conexión a la PDB
    if ! echo "SELECT 1 FROM DUAL;" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba >/dev/null 2>&1; then
        echo "UNHEALTHY: No se puede conectar a la PDB"
        return 1
    fi

    # Verificar que la PDB esté abierta
    local pdb_status=$(echo "SELECT open_mode FROM v\$pdbs WHERE name='${ORACLE_PDB}';" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_SID} as sysdba | grep -E "READ WRITE|READ ONLY")

    if [ -z "$pdb_status" ]; then
        echo "UNHEALTHY: PDB no está abierta"
        return 1
    fi

    echo "HEALTHY: Oracle Database está funcionando correctamente"
    return 0
}

# Ejecutar verificación
check_oracle_health
exit $?
