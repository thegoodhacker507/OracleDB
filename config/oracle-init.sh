#!/bin/bash
# =====================================================
# Oracle Database Initialization Script
# =====================================================

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Variables
ORACLE_SID=${ORACLE_SID:-FREE}
ORACLE_PDB=${ORACLE_PDB:-FREEPDB1}
ORACLE_PWD=${ORACLE_PWD:-Oracle123!}
SCRIPTS_DIR="/opt/oracle/scripts/setup"
MAX_WAIT_TIME=600  # 10 minutos máximo de espera

log "🚀 Iniciando Oracle Database 23ai FREE..."
log "   ORACLE_SID: $ORACLE_SID"
log "   ORACLE_PDB: $ORACLE_PDB"

# Iniciar Oracle Database en background
log "📦 Ejecutando runOracle.sh..."
/opt/oracle/runOracle.sh &
ORACLE_PID=$!

# Función para verificar si Oracle está listo
check_oracle_ready() {
    local count=0
    local max_attempts=$((MAX_WAIT_TIME / 10))
    
    log "⏳ Esperando a que Oracle Database esté listo..."
    
    while [ $count -lt $max_attempts ]; do
        # Verificar si el proceso de Oracle sigue corriendo
        if ! kill -0 $ORACLE_PID 2>/dev/null; then
            error "El proceso de Oracle se detuvo inesperadamente"
            return 1
        fi
        
        # Intentar conectarse a la CDB
        if echo "SELECT 1 FROM DUAL;" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_SID} as sysdba >/dev/null 2>&1; then
            success "✅ Conexión a CDB establecida"
            
            # Verificar si la PDB está disponible
            if echo "SELECT 1 FROM DUAL;" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba >/dev/null 2>&1; then
                success "✅ Conexión a PDB establecida"
                return 0
            else
                log "   PDB aún no está lista, esperando..."
            fi
        else
            log "   Oracle aún no está listo, esperando... (intento $((count + 1))/$max_attempts)"
        fi
        
        sleep 10
        count=$((count + 1))
    done
    
    error "Timeout: Oracle no estuvo listo después de $MAX_WAIT_TIME segundos"
    return 1
}

# Esperar a que Oracle esté listo
if ! check_oracle_ready; then
    error "No se pudo establecer conexión con Oracle Database"
    exit 1
fi

# Ejecutar scripts de configuración
log "🔧 Ejecutando scripts de configuración..."

if [ -d "$SCRIPTS_DIR" ] && [ "$(ls -A $SCRIPTS_DIR/*.sql 2>/dev/null)" ]; then
    for script in $SCRIPTS_DIR/*.sql; do
        if [ -f "$script" ]; then
            script_name=$(basename "$script")
            log "   📄 Ejecutando: $script_name"
            
            # Ejecutar el script y capturar la salida
            if sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba @"$script" > /tmp/script_output.log 2>&1; then
                success "   ✅ $script_name ejecutado correctamente"
                
                # Mostrar mensajes importantes del script
                if grep -q "ORA-" /tmp/script_output.log; then
                    warning "   ⚠️  Advertencias en $script_name:"
                    grep "ORA-" /tmp/script_output.log | head -5
                fi
            else
                error "   ❌ Error ejecutando $script_name"
                cat /tmp/script_output.log
                # Continuar con el siguiente script en lugar de fallar completamente
            fi
        fi
    done
else
    warning "No se encontraron scripts SQL en $SCRIPTS_DIR"
fi

# Verificar el estado final de la base de datos
log "🔍 Verificando estado de la base de datos..."

# Verificar tablespaces
log "   📊 Verificando tablespaces..."
echo "SELECT tablespace_name, status FROM dba_tablespaces;" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba

# Verificar usuarios creados
log "   👥 Verificando usuarios..."
echo "SELECT username, account_status FROM dba_users WHERE username NOT IN ('SYS','SYSTEM','ANONYMOUS','APEX_PUBLIC_USER','FLOWS_FILES','APEX_040000','APEX_040200','CTXSYS','DBSNMP','DIP','ORACLE_OCM','OUTLN','XDB') ORDER BY username;" | sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba

success "🎉 Configuración de Oracle Database completada"
log "📡 Base de datos disponible en:"
log "   - Puerto: 2521"
log "   - SID: $ORACLE_SID"
log "   - PDB: $ORACLE_PDB"
log "   - Enterprise Manager: http://localhost:6500/em"

# Mantener el contenedor corriendo y mostrar logs
log "📋 Monitoreando logs de Oracle..."
tail -f /opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log 2>/dev/null || \
tail -f /opt/oracle/diag/rdbms/*/*/trace/alert_*.log 2>/dev/null || \
tail -f /dev/null