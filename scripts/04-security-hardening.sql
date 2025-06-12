-- =====================================================
-- 04-security-hardening.sql - Endurecimiento de seguridad
-- =====================================================

-- Configurar el entorno
ALTER SESSION SET CONTAINER = FREEPDB1;

-- =====================================================
-- CONFIGURACIONES DE SEGURIDAD DE CONTRASEÑAS
-- =====================================================

-- Crear perfil de seguridad estricto
CREATE PROFILE SECURE_PROFILE LIMIT
    SESSIONS_PER_USER 3
    CPU_PER_SESSION UNLIMITED
    CPU_PER_CALL 3000
    CONNECT_TIME 480
    IDLE_TIME 30
    LOGICAL_READS_PER_SESSION UNLIMITED
    LOGICAL_READS_PER_CALL 1000
    PRIVATE_SGA UNLIMITED
    COMPOSITE_LIMIT UNLIMITED
    PASSWORD_LIFE_TIME 90
    PASSWORD_REUSE_TIME 365
    PASSWORD_REUSE_MAX 12
    PASSWORD_VERIFY_FUNCTION ORA12C_STRONG_VERIFY_FUNCTION
    PASSWORD_LOCK_TIME 1
    PASSWORD_GRACE_TIME 7
    FAILED_LOGIN_ATTEMPTS 5;

-- Aplicar el perfil a usuarios existentes (excepto SYS y SYSTEM)
ALTER USER app_dev PROFILE SECURE_PROFILE;
ALTER USER app_user PROFILE SECURE_PROFILE;
ALTER USER app_admin PROFILE SECURE_PROFILE;
ALTER USER app_readonly PROFILE SECURE_PROFILE;
ALTER USER backup_user PROFILE SECURE_PROFILE;

-- =====================================================
-- CONFIGURACIONES DE AUDITORÍA AVANZADA
-- =====================================================

-- Habilitar auditoría unificada
ALTER SYSTEM SET AUDIT_TRAIL = DB,EXTENDED SCOPE = SPFILE;

-- Auditar intentos de login fallidos
AUDIT CREATE SESSION WHENEVER NOT SUCCESSFUL;

-- Auditar operaciones privilegiadas
AUDIT GRANT ANY PRIVILEGE;
AUDIT GRANT ANY ROLE;
AUDIT CREATE USER;
AUDIT ALTER USER;
AUDIT DROP USER;

-- Auditar operaciones DDL críticas
AUDIT CREATE TABLE;
AUDIT DROP TABLE;
AUDIT ALTER TABLE;
AUDIT CREATE INDEX;
AUDIT DROP INDEX;

-- Auditar acceso a tablas sensibles
AUDIT SELECT, INSERT, UPDATE, DELETE ON datos_sensibles BY ACCESS;
AUDIT SELECT, INSERT, UPDATE, DELETE ON usuarios BY ACCESS;

-- =====================================================
-- CONFIGURACIONES DE RED Y CONEXIÓN
-- =====================================================

-- Configurar límites de conexión
ALTER SYSTEM SET PROCESSES = 300;
ALTER SYSTEM SET SESSIONS = 335;

-- Configurar timeout de conexiones inactivas
ALTER SYSTEM SET SQLNET.EXPIRE_TIME = 10;

-- Deshabilitar conexiones remotas no seguras
ALTER SYSTEM SET REMOTE_LOGIN_PASSWORDFILE = EXCLUSIVE;
ALTER SYSTEM SET SEC_RETURN_SERVER_RELEASE_BANNER = FALSE;

-- =====================================================
-- CONFIGURACIONES DE PRIVILEGIOS Y ROLES
-- =====================================================

-- Revocar privilegios públicos innecesarios
REVOKE EXECUTE ON UTL_FILE FROM PUBLIC;
REVOKE EXECUTE ON UTL_TCP FROM PUBLIC;
REVOKE EXECUTE ON UTL_HTTP FROM PUBLIC;
REVOKE EXECUTE ON UTL_SMTP FROM PUBLIC;

-- Solo otorgar estos privilegios a usuarios específicos que los necesiten
GRANT EXECUTE ON UTL_FILE TO app_admin;

-- =====================================================
-- CONFIGURACIONES DE TABLESPACES Y ARCHIVOS
-- =====================================================

-- Configurar autoextend con límites para evitar crecimiento descontrolado
ALTER DATABASE DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/app_data01.dbf' 
AUTOEXTEND ON NEXT 10M MAXSIZE 2G;

ALTER DATABASE DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/app_indexes01.dbf' 
AUTOEXTEND ON NEXT 5M MAXSIZE 1G;

-- =====================================================
-- CONFIGURACIONES DE LOGGING Y MONITOREO
-- =====================================================

-- Habilitar logging suplementario para LogMiner
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY, UNIQUE) COLUMNS;

-- Configurar retención de logs de auditoría
BEGIN
    DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_PROPERTY(
        audit_trail_type => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
        audit_trail_property => DBMS_AUDIT_MGMT.MAX_ARCHIVE_SIZE,
        audit_trail_property_value => 1000 -- 1GB
    );
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠️  No se pudo configurar retención de auditoría: ' || SQLERRM);
END;
/

-- =====================================================
-- TRIGGERS DE SEGURIDAD
-- =====================================================

-- Trigger para auditar cambios en usuarios críticos
CREATE OR REPLACE TRIGGER trg_audit_user_changes
    AFTER INSERT OR UPDATE OR DELETE ON usuarios
    FOR EACH ROW
DECLARE
    v_action VARCHAR2(10);
    v_user VARCHAR2(100);
BEGIN
    v_user := USER;
    
    IF INSERTING THEN
        v_action := 'INSERT';
        INSERT INTO audit_log (tabla, accion, usuario, fecha, datos_nuevos)
        VALUES ('USUARIOS', v_action, v_user, SYSDATE, 
                'ID: ' || :NEW.id_usuario || ', Email: ' || :NEW.correo);
    ELSIF UPDATING THEN
        v_action := 'UPDATE';
        INSERT INTO audit_log (tabla, accion, usuario, fecha, datos_antiguos, datos_nuevos)
        VALUES ('USUARIOS', v_action, v_user, SYSDATE,
                'ID: ' || :OLD.id_usuario || ', Email: ' || :OLD.correo,
                'ID: ' || :NEW.id_usuario || ', Email: ' || :NEW.correo);
    ELSIF DELETING THEN
        v_action := 'DELETE';
        INSERT INTO audit_log (tabla, accion, usuario, fecha, datos_antiguos)
        VALUES ('USUARIOS', v_action, v_user, SYSDATE,
                'ID: ' || :OLD.id_usuario || ', Email: ' || :OLD.correo);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- No fallar la operación principal por errores de auditoría
        NULL;
END;
/

-- Crear tabla de auditoría personalizada
CREATE TABLE audit_log (
    id_audit        NUMBER(12)          CONSTRAINT pk_audit_log PRIMARY KEY,
    tabla           VARCHAR2(50 CHAR)   NOT NULL,
    accion          VARCHAR2(10 CHAR)   NOT NULL,
    usuario         VARCHAR2(100 CHAR)  NOT NULL,
    fecha           DATE                NOT NULL,
    datos_antiguos  VARCHAR2(4000 CHAR),
    datos_nuevos    VARCHAR2(4000 CHAR)
) TABLESPACE APP_DATA;

CREATE SEQUENCE seq_audit_log START WITH 1 INCREMENT BY 1 NOCACHE;

CREATE OR REPLACE TRIGGER trg_audit_log_id
    BEFORE INSERT ON audit_log
    FOR EACH ROW
BEGIN
    IF :NEW.id_audit IS NULL THEN
        :NEW.id_audit := seq_audit_log.NEXTVAL;
    END IF;
END;
/

-- =====================================================
-- CONFIGURACIONES DE RECURSOS Y LÍMITES
-- =====================================================

-- Crear perfil para limitar recursos de usuarios de aplicación
CREATE PROFILE APP_USER_PROFILE LIMIT
    SESSIONS_PER_USER 2
    CPU_PER_SESSION 60000  -- 10 minutos
    CONNECT_TIME 120       -- 2 horas
    IDLE_TIME 15           -- 15 minutos
    LOGICAL_READS_PER_SESSION 100000
    PRIVATE_SGA 50M
    FAILED_LOGIN_ATTEMPTS 3
    PASSWORD_LOCK_TIME 0.5  -- 12 horas
    PASSWORD_LIFE_TIME 60   -- 60 días
    PASSWORD_GRACE_TIME 3;

-- Aplicar perfil restrictivo a usuarios de aplicación
ALTER USER app_user PROFILE APP_USER_PROFILE;

-- =====================================================
-- CONFIGURACIONES DE BACKUP Y RECOVERY
-- =====================================================

-- Configurar RMAN para backups seguros
ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME = 31;

-- Habilitar block change tracking para backups incrementales más rápidos
BEGIN
    EXECUTE IMMEDIATE 'ALTER DATABASE ENABLE BLOCK CHANGE TRACKING USING FILE ''/opt/oracle/oradata/FREE/change_tracking.f''';
    DBMS_OUTPUT.PUT_LINE('✅ Block Change Tracking habilitado');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠️  No se pudo habilitar Block Change Tracking: ' || SQLERRM);
END;
/

-- =====================================================
-- VISTAS DE MONITOREO DE SEGURIDAD
-- =====================================================

-- Vista para monitorear intentos de login fallidos
CREATE OR REPLACE VIEW v_failed_logins AS
SELECT 
    username,
    timestamp,
    action_name,
    returncode,
    client_id,
    os_username
FROM dba_audit_session 
WHERE action_name = 'LOGON' 
AND returncode != 0
ORDER BY timestamp DESC;

-- Vista para monitorear usuarios bloqueados
CREATE OR REPLACE VIEW v_locked_users AS
SELECT 
    username,
    account_status,
    lock_date,
    expiry_date,
    profile
FROM dba_users 
WHERE account_status LIKE '%LOCKED%'
ORDER BY lock_date DESC;

-- Vista para monitorear privilegios otorgados
CREATE OR REPLACE VIEW v_user_privileges AS
SELECT 
    grantee,
    privilege,
    admin_option,
    grantable
FROM dba_sys_privs 
WHERE grantee NOT IN ('SYS', 'SYSTEM', 'PUBLIC')
ORDER BY grantee, privilege;

-- =====================================================
-- PROCEDIMIENTOS DE SEGURIDAD
-- =====================================================

-- Procedimiento para limpiar logs de auditoría antiguos
CREATE OR REPLACE PROCEDURE cleanup_audit_logs(p_days_old NUMBER DEFAULT 90)
IS
    v_count NUMBER;
BEGIN
    DELETE FROM audit_log 
    WHERE fecha < SYSDATE - p_days_old;
    
    v_count := SQL%ROWCOUNT;
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Eliminados ' || v_count || ' registros de auditoría anteriores a ' || p_days_old || ' días');
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error limpiando logs de auditoría: ' || SQLERRM);
        RAISE;
END;
/

-- Procedimiento para generar reporte de seguridad
CREATE OR REPLACE PROCEDURE security_report
IS
    CURSOR c_failed_logins IS
        SELECT COUNT(*) as failed_count
        FROM v_failed_logins 
        WHERE timestamp > SYSDATE - 1;
    
    CURSOR c_locked_users IS
        SELECT COUNT(*) as locked_count
        FROM v_locked_users;
    
    v_failed_count NUMBER;
    v_locked_count NUMBER;
BEGIN
    OPEN c_failed_logins;
    FETCH c_failed_logins INTO v_failed_count;
    CLOSE c_failed_logins;
    
    OPEN c_locked_users;
    FETCH c_locked_users INTO v_locked_count;
    CLOSE c_locked_users;
    
    DBMS_OUTPUT.PUT_LINE('=== REPORTE DE SEGURIDAD ===');
    DBMS_OUTPUT.PUT_LINE('Fecha: ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('Intentos de login fallidos (últimas 24h): ' || v_failed_count);
    DBMS_OUTPUT.PUT_LINE('Usuarios bloqueados: ' || v_locked_count);
    DBMS_OUTPUT.PUT_LINE('============================');
END;
/

-- =====================================================
-- OTORGAR PERMISOS PARA VISTAS Y PROCEDIMIENTOS
-- =====================================================

GRANT SELECT ON v_failed_logins TO app_admin;
GRANT SELECT ON v_locked_users TO app_admin;
GRANT SELECT ON v_user_privileges TO app_admin;
GRANT EXECUTE ON cleanup_audit_logs TO app_admin;
GRANT EXECUTE ON security_report TO app_admin;

-- =====================================================
-- CONFIGURACIONES FINALES
-- =====================================================

-- Compilar objetos inválidos
BEGIN
    DBMS_UTILITY.COMPILE_SCHEMA(schema => USER, compile_all => FALSE);
END;
/

-- Actualizar estadísticas de las tablas del sistema
BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(
        ownname => USER,
        estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
        method_opt => 'FOR ALL COLUMNS SIZE AUTO',
        cascade => TRUE
    );
END;
/

COMMIT;

-- Mensaje de confirmación
SELECT 'Script 04-security-hardening.sql ejecutado correctamente - ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') AS resultado FROM DUAL;

-- Ejecutar reporte de seguridad inicial
EXEC security_report;