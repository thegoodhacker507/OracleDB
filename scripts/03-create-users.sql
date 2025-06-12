-- =====================================================
-- 03-create-users.sql - Creación de usuarios y roles
-- =====================================================

-- Configurar el entorno
ALTER SESSION SET CONTAINER = FREEPDB1;

-- =====================================================
-- CREACIÓN DE ROLES PERSONALIZADOS
-- =====================================================

-- Rol para desarrolladores
CREATE ROLE APP_DEVELOPER;
GRANT CREATE SESSION TO APP_DEVELOPER;
GRANT CREATE TABLE TO APP_DEVELOPER;
GRANT CREATE VIEW TO APP_DEVELOPER;
GRANT CREATE PROCEDURE TO APP_DEVELOPER;
GRANT CREATE SEQUENCE TO APP_DEVELOPER;
GRANT CREATE TRIGGER TO APP_DEVELOPER;
GRANT CREATE SYNONYM TO APP_DEVELOPER;

-- Rol para usuarios de aplicación (solo lectura/escritura de datos)
CREATE ROLE APP_USER;
GRANT CREATE SESSION TO APP_USER;

-- Rol para administradores de aplicación
CREATE ROLE APP_ADMIN;
GRANT APP_DEVELOPER TO APP_ADMIN;
GRANT CREATE USER TO APP_ADMIN;
GRANT ALTER USER TO APP_ADMIN;
GRANT DROP USER TO APP_ADMIN;

-- Rol para usuarios de solo lectura
CREATE ROLE APP_READONLY;
GRANT CREATE SESSION TO APP_READONLY;

-- =====================================================
-- CREACIÓN DE USUARIOS DE APLICACIÓN
-- =====================================================

-- Usuario desarrollador principal
CREATE USER app_dev 
IDENTIFIED BY "DevPass123!"
DEFAULT TABLESPACE APP_DATA
TEMPORARY TABLESPACE TEMP
QUOTA UNLIMITED ON APP_DATA
QUOTA UNLIMITED ON APP_INDEXES;

GRANT APP_DEVELOPER TO app_dev;
GRANT RESOURCE TO app_dev;

-- Usuario para la aplicación (conexión desde aplicaciones)
CREATE USER app_user 
IDENTIFIED BY "AppUser123!"
DEFAULT TABLESPACE APP_DATA
TEMPORARY TABLESPACE TEMP
QUOTA 100M ON APP_DATA;

GRANT APP_USER TO app_user;

-- Usuario administrador de la aplicación
CREATE USER app_admin 
IDENTIFIED BY "AdminPass123!"
DEFAULT TABLESPACE APP_DATA
TEMPORARY TABLESPACE TEMP
QUOTA UNLIMITED ON APP_DATA