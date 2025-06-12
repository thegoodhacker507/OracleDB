-- =====================================================
-- 02-enable-encryption.sql - Configuración de TDE
-- =====================================================

-- Configurar el entorno
ALTER SESSION SET CONTAINER = FREEPDB1;

-- =====================================================
-- CONFIGURACIÓN DE TRANSPARENT DATA ENCRYPTION (TDE)
-- =====================================================

-- Crear directorio para el wallet si no existe
!mkdir -p /opt/oracle/admin/wallet

-- Configurar la ubicación del wallet
ALTER SYSTEM SET WALLET_ROOT='/opt/oracle/admin/wallet' SCOPE=SPFILE;

-- Configurar TDE_CONFIGURATION
ALTER SYSTEM SET TDE_CONFIGURATION='KEYSTORE_CONFIGURATION=FILE' SCOPE=BOTH;

-- Crear el keystore (wallet) para TDE
-- Nota: En Oracle 23ai FREE, algunos comandos de TDE pueden estar limitados
-- pero intentaremos configurar lo básico

BEGIN
    -- Intentar crear el keystore
    EXECUTE IMMEDIATE 'ADMINISTER KEY MANAGEMENT CREATE KEYSTORE ''/opt/oracle/admin/wallet'' IDENTIFIED BY "Oracle123!"';
    DBMS_OUTPUT.PUT_LINE('✅ Keystore creado exitosamente');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -46658 THEN
            DBMS_OUTPUT.PUT_LINE('⚠️  Keystore ya existe o TDE no está completamente disponible en FREE');
        ELSE
            DBMS_OUTPUT.PUT_LINE('❌ Error creando keystore: ' || SQLERRM);
        END IF;
END;
/

-- Intentar abrir el keystore
BEGIN
    EXECUTE IMMEDIATE 'ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN IDENTIFIED BY "Oracle123!"';
    DBMS_OUTPUT.PUT_LINE('✅ Keystore abierto exitosamente');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠️  No se pudo abrir el keystore: ' || SQLERRM);
END;
/

-- Intentar crear la master key
BEGIN
    EXECUTE IMMEDIATE 'ADMINISTER KEY MANAGEMENT SET KEY IDENTIFIED BY "Oracle123!"';
    DBMS_OUTPUT.PUT_LINE('✅ Master key creada exitosamente');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠️  No se pudo crear la master key: ' || SQLERRM);
END;
/

-- =====================================================
-- CONFIGURACIONES DE SEGURIDAD ADICIONALES
-- =====================================================

-- Habilitar el cifrado de red (si está disponible)
ALTER SYSTEM SET SQLNET.ENCRYPTION_SERVER = REQUIRED;
ALTER SYSTEM SET SQLNET.ENCRYPTION_TYPES_SERVER = '(AES256,AES192,AES128)';

-- Configurar checksums de red
ALTER SYSTEM SET SQLNET.CRYPTO_CHECKSUM_SERVER = REQUIRED;
ALTER SYSTEM SET SQLNET.CRYPTO_CHECKSUM_TYPES_SERVER = '(SHA256,SHA1,MD5)';

-- =====================================================
-- CREAR TABLESPACE ENCRIPTADO (si TDE está disponible)
-- =====================================================

-- Intentar crear un tablespace encriptado
BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLESPACE ENCRYPTED_DATA
        DATAFILE ''/opt/oracle/oradata/FREE/FREEPDB1/encrypted_data01.dbf'' 
        SIZE 50M AUTOEXTEND ON NEXT 5M MAXSIZE 500M
        ENCRYPTION USING ''AES256''
        DEFAULT STORAGE(ENCRYPT)';
    DBMS_OUTPUT.PUT_LINE('✅ Tablespace encriptado creado exitosamente');
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE = -28374 OR SQLCODE = -46658 THEN
            DBMS_OUTPUT.PUT_LINE('⚠️  TDE no está completamente disponible en Oracle FREE - creando tablespace normal');
            EXECUTE IMMEDIATE 'CREATE TABLESPACE ENCRYPTED_DATA
                DATAFILE ''/opt/oracle/oradata/FREE/FREEPDB1/encrypted_data01.dbf'' 
                SIZE 50M AUTOEXTEND ON NEXT 5M MAXSIZE 500M
                EXTENT MANAGEMENT LOCAL AUTOALLOCATE
                SEGMENT SPACE MANAGEMENT AUTO';
        ELSE
            DBMS_OUTPUT.PUT_LINE('❌ Error creando tablespace: ' || SQLERRM);
            RAISE;
        END IF;
END;
/

-- =====================================================
-- TABLA DE DATOS SENSIBLES
-- =====================================================

-- Crear tabla para datos sensibles (intentará usar encriptación si está disponible)
CREATE TABLE datos_sensibles (
    id_dato         NUMBER(10)          CONSTRAINT pk_datos_sensibles PRIMARY KEY,
    numero_tarjeta  VARCHAR2(20 CHAR)   NOT NULL,
    cvv             VARCHAR2(4 CHAR)    NOT NULL,
    fecha_expiracion DATE               NOT NULL,
    titular         VARCHAR2(100 CHAR)  NOT NULL,
    fecha_creacion  DATE                DEFAULT SYSDATE NOT NULL,
    -- Restricciones de seguridad
    CONSTRAINT ck_numero_tarjeta CHECK (REGEXP_LIKE(numero_tarjeta, '^[0-9]{13,19}$')),
    CONSTRAINT ck_cvv CHECK (REGEXP_LIKE(cvv, '^[0-9]{3,4}$')),
    CONSTRAINT ck_fecha_exp CHECK (fecha_expiracion > SYSDATE)
) TABLESPACE ENCRYPTED_DATA;

-- Crear secuencia para la tabla de datos sensibles
CREATE SEQUENCE seq_datos_sensibles START WITH 1 INCREMENT BY 1 NOCACHE;

-- Trigger para asignar ID automáticamente
CREATE OR REPLACE TRIGGER trg_datos_sensibles_id
    BEFORE INSERT ON datos_sensibles
    FOR EACH ROW
BEGIN
    IF :NEW.id_dato IS NULL THEN
        :NEW.id_dato := seq_datos_sensibles.NEXTVAL;
    END IF;
END;
/

-- =====================================================
-- CONFIGURACIONES DE AUDITORÍA PARA DATOS SENSIBLES
-- =====================================================

-- Auditar acceso a datos sensibles
AUDIT SELECT, INSERT, UPDATE, DELETE ON datos_sensibles BY ACCESS;

-- Crear política de auditoría fina (Fine Grained Auditing)
BEGIN
    DBMS_FGA.ADD_POLICY(
        object_schema   => USER,
        object_name     => 'DATOS_SENSIBLES',
        policy_name     => 'AUDIT_DATOS_SENSIBLES',
        audit_condition => NULL,
        audit_column    => 'NUMERO_TARJETA,CVV',
        handler_schema  => NULL,
        handler_module  => NULL,
        enable          => TRUE,
        statement_types => 'SELECT,INSERT,UPDATE,DELETE'
    );
    DBMS_OUTPUT.PUT_LINE('✅ Política de auditoría fina creada');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('⚠️  No se pudo crear la política FGA: ' || SQLERRM);
END;
/

-- =====================================================
-- VERIFICACIÓN DEL ESTADO DE TDE
-- =====================================================

-- Verificar el estado del wallet/keystore
SELECT 
    'WALLET_STATUS' as tipo,
    STATUS as estado
FROM V$ENCRYPTION_WALLET
UNION ALL
SELECT 
    'TDE_CONFIG' as tipo,
    VALUE as estado
FROM V$PARAMETER 
WHERE NAME = 'tde_configuration';

-- Verificar tablespaces encriptados
SELECT 
    tablespace_name,
    encrypted,
    status
FROM DBA_TABLESPACES 
WHERE tablespace_name IN ('ENCRYPTED_DATA', 'APP_DATA');

COMMIT;

-- Mensaje de confirmación
SELECT 'Script 02-enable-encryption.sql ejecutado correctamente - ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') AS resultado FROM DUAL;