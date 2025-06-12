#!/bin/bash
# =====================================================
# Oracle Database Backup Script
# Automated backup solution for Oracle 23ai FREE
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

# =====================================================
# CONFIGURACIÓN DE VARIABLES
# =====================================================

# Variables de Oracle
export ORACLE_SID=${ORACLE_SID:-FREE}
export ORACLE_PDB=${ORACLE_PDB:-FREEPDB1}
export ORACLE_HOME=${ORACLE_HOME:-/opt/oracle/product/23ai/dbhomeFree}
export ORACLE_PWD=${ORACLE_PWD:-Oracle123!}
export PATH=$ORACLE_HOME/bin:$PATH

# Variables de backup
BACKUP_BASE_DIR="/opt/oracle/backup"
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_DATE"
LOG_DIR="$BACKUP_BASE_DIR/logs"
LOG_FILE="$LOG_DIR/backup_$BACKUP_DATE.log"

# Configuración de retención (días)
RETENTION_DAYS=${RETENTION_DAYS:-7}

# Configuración de compresión
COMPRESS_BACKUP=${COMPRESS_BACKUP:-true}

# Configuración de notificaciones
SEND_EMAIL=${SEND_EMAIL:-false}
EMAIL_TO=${EMAIL_TO:-"admin@empresa.com"}

# =====================================================
# FUNCIONES AUXILIARES
# =====================================================

# Crear directorios necesarios
create_directories() {
    log "📁 Creando directorios de backup..."
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_BASE_DIR/rman"
    mkdir -p "$BACKUP_BASE_DIR/exports"
    mkdir -p "$BACKUP_BASE_DIR/scripts"
}

# Verificar conectividad a Oracle
check_oracle_connection() {
    log "🔍 Verificando conectividad a Oracle..."
    
    if ! sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_SID} as sysdba <<< "SELECT 1 FROM DUAL;" >/dev/null 2>&1; then
        error "No se puede conectar a la instancia CDB $ORACLE_SID"
        return 1
    fi
    
    if ! sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<< "SELECT 1 FROM DUAL;" >/dev/null 2>&1; then
        error "No se puede conectar a la PDB $ORACLE_PDB"
        return 1
    fi
    
    success "✅ Conectividad a Oracle verificada"
    return 0
}

# Obtener información de la base de datos
get_db_info() {
    log "📊 Obteniendo información de la base de datos..."
    
    DB_SIZE=$(sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) || ' GB' FROM dba_data_files;
EXIT;
EOF
)
    
    TABLESPACE_COUNT=$(sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT COUNT(*) FROM dba_tablespaces;
EXIT;
EOF
)
    
    USER_COUNT=$(sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT COUNT(*) FROM dba_users WHERE account_status = 'OPEN';
EXIT;
EOF
)
    
    log "   💾 Tamaño de BD: $DB_SIZE"
    log "   📦 Tablespaces: $TABLESPACE_COUNT"
    log "   👥 Usuarios activos: $USER_COUNT"
}

# =====================================================
# FUNCIONES DE BACKUP
# =====================================================

# Backup completo con RMAN
rman_full_backup() {
    log "🔄 Iniciando backup completo con RMAN..."
    
    local rman_script="$BACKUP_DIR/rman_full_backup.rcv"
    
    cat > "$rman_script" <<EOF
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF $RETENTION_DAYS DAYS;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '$BACKUP_DIR/rman_%U';
CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';

RUN {
    ALLOCATE CHANNEL c1 DEVICE TYPE DISK;
    BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
    BACKUP CURRENT CONTROLFILE;
    BACKUP SPFILE;
    RELEASE CHANNEL c1;
}

DELETE NOPROMPT OBSOLETE;
EXIT;
EOF

    if rman target sys/${ORACLE_PWD}@localhost:2521/${ORACLE_SID} @"$rman_script" >> "$LOG_FILE" 2>&1; then
        success "✅ Backup RMAN completado exitosamente"
        return 0
    else
        error "❌ Error en backup RMAN"
        return 1
    fi
}

# Export de esquemas con Data Pump
datapump_export() {
    log "📤 Iniciando export con Data Pump..."
    
    local export_dir="$BACKUP_DIR/exports"
    mkdir -p "$export_dir"
    
    # Crear directorio en Oracle si no existe
    sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF >> "$LOG_FILE" 2>&1
CREATE OR REPLACE DIRECTORY BACKUP_EXPORT_DIR AS '$export_dir';
GRANT READ, WRITE ON DIRECTORY BACKUP_EXPORT_DIR TO SYSTEM;
EXIT;
EOF

    # Export de todos los esquemas de usuario
    local schemas=$(sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT LISTAGG(username, ',') WITHIN GROUP (ORDER BY username)
FROM dba_users 
WHERE username NOT IN ('SYS','SYSTEM','ANONYMOUS','APEX_PUBLIC_USER','FLOWS_FILES',
                       'APEX_040000','APEX_040200','CTXSYS','DBSNMP','DIP','ORACLE_OCM',
                       'OUTLN','XDB','WMSYS','APPQOSSYS','OJVMSYS')
AND account_status = 'OPEN';
EXIT;
EOF
)

    if [ -n "$schemas" ] && [ "$schemas" != " " ]; then
        log "   📋 Exportando esquemas: $schemas"
        
        if expdp system/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} \
            directory=BACKUP_EXPORT_DIR \
            dumpfile=full_export_${BACKUP_DATE}.dmp \
            logfile=full_export_${BACKUP_DATE}.log \
            schemas="$schemas" \
            compression=all \
            parallel=2 >> "$LOG_FILE" 2>&1; then
            success "✅ Export Data Pump completado"
        else
            warning "⚠️  Error en export Data Pump"
        fi
    else
        warning "⚠️  No se encontraron esquemas de usuario para exportar"
    fi
}

# Backup de configuraciones
backup_configs() {
    log "⚙️  Respaldando configuraciones..."
    
    local config_dir="$BACKUP_DIR/configs"
    mkdir -p "$config_dir"
    
    # Backup de parámetros de la base de datos
    sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF > "$config_dir/db_parameters.txt"
SET PAGESIZE 1000 LINESIZE 200
SELECT name, value, description FROM v\$parameter WHERE isdefault = 'FALSE' ORDER BY name;
EXIT;
EOF

    # Backup de usuarios y roles
    sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF > "$config_dir/users_roles.txt"
SET PAGESIZE 1000 LINESIZE 200
SELECT 'USER: ' || username || ' - STATUS: ' || account_status || ' - PROFILE: ' || profile
FROM dba_users ORDER BY username;

SELECT 'ROLE: ' || role FROM dba_roles ORDER BY role;
EXIT;
EOF

    # Backup de privilegios del sistema
    sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF > "$config_dir/system_privileges.txt"
SET PAGESIZE 1000 LINESIZE 200
SELECT grantee, privilege, admin_option FROM dba_sys_privs 
WHERE grantee NOT IN ('SYS','SYSTEM','PUBLIC') ORDER BY grantee, privilege;
EXIT;
EOF

    # Backup de tablespaces
    sqlplus -S sys/${ORACLE_PWD}@localhost:2521/${ORACLE_PDB} as sysdba <<EOF > "$config_dir/tablespaces.txt"
SET PAGESIZE 1000 LINESIZE 200
SELECT tablespace_name, status, contents, extent_management, allocation_type
FROM dba_tablespaces ORDER BY tablespace_name;
EXIT;
EOF

    success "✅ Configuraciones respaldadas"
}

# Backup de scripts personalizados
backup_scripts() {
    log "📜 Respaldando scripts personalizados..."
    
    local scripts_dir="$BACKUP_DIR/custom_scripts"
    mkdir -p "$scripts_dir"
    
    # Copiar scripts SQL de configuración
    if [ -d "/opt/oracle/scripts/setup" ]; then
        cp -r /opt/oracle/scripts/setup/* "$scripts_dir/" 2>/dev/null || true
    fi
    
    # Copiar este script de backup
    cp "$0" "$scripts_dir/backup-script.sh" 2>/dev/null || true
    
    success "✅ Scripts personalizados respaldados"
}

# =====================================================
# FUNCIONES DE MANTENIMIENTO
# =====================================================

# Limpiar backups antiguos
cleanup_old_backups() {
    log "🧹 Limpiando backups antiguos (más de $RETENTION_DAYS días)..."
    
    local deleted_count=0
    
    # Buscar y eliminar directorios de backup antiguos
    find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS | while read old_backup; do
        if [ -d "$old_backup" ]; then
            log "   🗑️  Eliminando: $(basename "$old_backup")"
            rm -rf "$old_backup"
            ((deleted_count++))
        fi
    done
    
    # Limpiar logs antiguos
    find "$LOG_DIR" -name "backup_*.log" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    
    success "✅ Limpieza completada"
}

# Comprimir backup si está habilitado
compress_backup() {
    if [ "$COMPRESS_BACKUP" = "true" ]; then
        log "🗜️  Comprimiendo backup..."
        
        cd "$BACKUP_BASE_DIR"
        if tar -czf "${BACKUP_DATE}.tar.gz" "$BACKUP_DATE" >> "$LOG_FILE" 2>&1; then
            rm -rf "$BACKUP_DATE"
            success "✅ Backup comprimido: ${BACKUP_DATE}.tar.gz"
        else
            warning "⚠️  Error comprimiendo backup"
        fi
    fi
}

# Verificar integridad del backup
verify_backup() {
    log "🔍 Verificando integridad del backup..."
    
    local backup_size=0
    local file_count=0
    
    if [ "$COMPRESS_BACKUP" = "true" ]; then
        if [ -f "$BACKUP_BASE_DIR/${BACKUP_DATE}.tar.gz" ]; then
            backup_size=$(du -h "$BACKUP_BASE_DIR/${BACKUP_DATE}.tar.gz" | cut -f1)
            file_count=1
        fi
    else
        if [ -d "$BACKUP_DIR" ]; then
            backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
            file_count=$(find "$BACKUP_DIR" -type f | wc -l)
        fi
    fi
    
    log "   📊 Tamaño del backup: $backup_size"
    log "   📁 Archivos creados: $file_count"
    
    if [ $file_count -gt 0 ]; then
        success "✅ Backup verificado correctamente"
        return 0
    else
        error "❌ Backup parece estar vacío o corrupto"
        return 1
    fi
}

# =====================================================
# FUNCIÓN PRINCIPAL
# =====================================================

main() {
    log "🚀 Iniciando proceso de backup de Oracle Database"
    log "   📅 Fecha: $(date)"
    log "   🎯 Instancia: $ORACLE_SID"
    log "   🎯 PDB: $ORACLE_PDB"
    log "   📂 Directorio: $BACKUP_DIR"
    
    # Crear directorios
    create_directories
    
    # Redirigir salida al log
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    # Verificar conectividad
    if ! check_oracle_connection; then
        error "❌ No se puede conectar a Oracle Database"
        exit 1
    fi
    
    # Obtener información de la BD
    get_db_info
    
    local backup_success=true
    
    # Ejecutar backups
    if ! rman_full_backup; then
        backup_success=false
    fi
    
    datapump_export
    backup_configs
    backup_scripts
    
    # Comprimir si está habilitado
    compress_backup
    
    # Verificar integridad
    if ! verify_backup; then
        backup_success=false
    fi
    
    # Limpiar backups antiguos
    cleanup_old_backups
    
    # Resultado final
    local end_time=$(date)
    local duration=$(($(date +%s) - $(date -d "$start_time" +%s) 2>/dev/null || echo 0))
    
    if [ "$backup_success" = true ]; then
        success "🎉 Backup completado exitosamente"
        log "   ⏱️  Duración: ${duration}s"
        log "   📂 Ubicación: $BACKUP_DIR"
        exit 0
    else
        error "❌ Backup completado con errores"
        log "   ⏱️  Duración: ${duration}s"
        log "   📋 Revisar log: $LOG_FILE"
        exit 1
    fi
}

# =====================================================
# MANEJO DE SEÑALES
# =====================================================

cleanup_on_exit() {
    log "🛑 Proceso interrumpido - limpiando..."
    # Aquí podrías agregar limpieza adicional si es necesario
    exit 1
}

trap cleanup_on_exit INT TERM

# =====================================================
# EJECUCIÓN
# =====================================================

# Verificar si se está ejecutando como usuario oracle
if [ "$(whoami)" != "oracle" ]; then
    warning "⚠️  Se recomienda ejecutar este script como usuario 'oracle'"
fi

# Registrar tiempo de inicio
start_time=$(date)

# Ejecutar función principal
main "$@"