-- =====================================================
-- 01-setup-oracle.sql - Configuración inicial y tablas
-- =====================================================

-- Configuración inicial del sistema
WHENEVER SQLERROR EXIT SQL.SQLCODE;

-- Configurar el entorno
ALTER SESSION SET CONTAINER = FREEPDB1;

-- Configuraciones de seguridad y auditoría
ALTER SYSTEM SET audit_trail = DB SCOPE = SPFILE;
ALTER SYSTEM SET sec_case_sensitive_logon = TRUE;

-- Crear directorio para Data Pump
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/opt/oracle/admin/FREE/dpdump/';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO SYSTEM;

-- =====================================================
-- CREACIÓN DE TABLESPACES PERSONALIZADOS
-- =====================================================

-- Tablespace para datos de aplicación
CREATE TABLESPACE APP_DATA
DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/app_data01.dbf' 
SIZE 100M AUTOEXTEND ON NEXT 10M MAXSIZE 1G
EXTENT MANAGEMENT LOCAL AUTOALLOCATE
SEGMENT SPACE MANAGEMENT AUTO;

-- Tablespace para índices
CREATE TABLESPACE APP_INDEXES
DATAFILE '/opt/oracle/oradata/FREE/FREEPDB1/app_indexes01.dbf' 
SIZE 50M AUTOEXTEND ON NEXT 5M MAXSIZE 500M
EXTENT MANAGEMENT LOCAL AUTOALLOCATE
SEGMENT SPACE MANAGEMENT AUTO;

-- =====================================================
-- CREACIÓN DE TABLAS CON RESTRICCIONES COMPLETAS
-- =====================================================

-- Tabla de departamentos
CREATE TABLE departamentos (
    id_departamento NUMBER(4)       CONSTRAINT pk_departamento PRIMARY KEY,
    nombre          VARCHAR2(50 CHAR)   NOT NULL CONSTRAINT uk_dept_nombre UNIQUE,
    codigo          CHAR(3 CHAR)        NOT NULL CONSTRAINT uk_dept_codigo UNIQUE,
    presupuesto     NUMBER(12,2)        CONSTRAINT ck_dept_presupuesto CHECK (presupuesto > 0),
    activo          CHAR(1 CHAR)        DEFAULT 'S' CONSTRAINT ck_dept_activo CHECK (activo IN ('S', 'N')),
    fecha_creacion  DATE                DEFAULT SYSDATE NOT NULL
) TABLESPACE APP_DATA;

-- Tabla de usuarios con múltiples restricciones
CREATE TABLE usuarios (
    id_usuario      NUMBER(6)           CONSTRAINT pk_usuario PRIMARY KEY,
    nombre          VARCHAR2(50 CHAR)   NOT NULL CONSTRAINT ck_usuario_nombre CHECK (LENGTH(TRIM(nombre)) >= 2),
    apellido        VARCHAR2(50 CHAR)   NOT NULL CONSTRAINT ck_usuario_apellido CHECK (LENGTH(TRIM(apellido)) >= 2),
    correo          VARCHAR2(100 CHAR)  NOT NULL CONSTRAINT uk_usuario_correo UNIQUE
                                        CONSTRAINT ck_usuario_correo CHECK (correo LIKE '%@%.%'),
    telefono        VARCHAR2(15 CHAR)   CONSTRAINT ck_usuario_telefono CHECK (REGEXP_LIKE(telefono, '^[0-9+\-\s()]+$')),
    edad            NUMBER(3)           CONSTRAINT ck_usuario_edad CHECK (edad BETWEEN 18 AND 120),
    salario         NUMBER(10,2)        CONSTRAINT ck_usuario_salario CHECK (salario > 0),
    id_departamento NUMBER(4)           CONSTRAINT fk_usuario_dept REFERENCES departamentos(id_departamento),
    estado          VARCHAR2(10 CHAR)   DEFAULT 'ACTIVO' CONSTRAINT ck_usuario_estado 
                                        CHECK (estado IN ('ACTIVO', 'INACTIVO', 'SUSPENDIDO')),
    fecha_registro  DATE                DEFAULT SYSDATE NOT NULL,
    fecha_nacimiento DATE               CONSTRAINT ck_usuario_fecha_nac CHECK (fecha_nacimiento < SYSDATE)
) TABLESPACE APP_DATA;

-- Tabla de productos con restricciones de negocio
CREATE TABLE productos (
    id_producto     NUMBER(8)           CONSTRAINT pk_producto PRIMARY KEY,
    codigo_barras   VARCHAR2(20 CHAR)   NOT NULL CONSTRAINT uk_producto_codigo UNIQUE,
    nombre          VARCHAR2(100 CHAR)  NOT NULL,
    descripcion     VARCHAR2(500 CHAR),
    precio          NUMBER(10,2)        NOT NULL CONSTRAINT ck_producto_precio CHECK (precio > 0),
    stock           NUMBER(8)           DEFAULT 0 CONSTRAINT ck_producto_stock CHECK (stock >= 0),
    categoria       VARCHAR2(30 CHAR)   NOT NULL CONSTRAINT ck_producto_categoria 
                                        CHECK (categoria IN ('ELECTRONICA', 'ROPA', 'HOGAR', 'DEPORTES', 'LIBROS')),
    peso_kg         NUMBER(8,3)         CONSTRAINT ck_producto_peso CHECK (peso_kg > 0),
    activo          CHAR(1 CHAR)        DEFAULT 'S' CONSTRAINT ck_producto_activo CHECK (activo IN ('S', 'N')),
    fecha_creacion  DATE                DEFAULT SYSDATE NOT NULL
) TABLESPACE APP_DATA;

-- Tabla de pedidos con restricciones de fechas y estados
CREATE TABLE pedidos (
    id_pedido       NUMBER(10)          CONSTRAINT pk_pedido PRIMARY KEY,
    id_usuario      NUMBER(6)           NOT NULL CONSTRAINT fk_pedido_usuario REFERENCES usuarios(id_usuario),
    fecha_pedido    DATE                DEFAULT SYSDATE NOT NULL,
    fecha_entrega   DATE                CONSTRAINT ck_pedido_fecha_entrega CHECK (fecha_entrega >= fecha_pedido),
    total           NUMBER(12,2)        NOT NULL CONSTRAINT ck_pedido_total CHECK (total > 0),
    estado          VARCHAR2(15 CHAR)   DEFAULT 'PENDIENTE' CONSTRAINT ck_pedido_estado 
                                        CHECK (estado IN ('PENDIENTE', 'PROCESANDO', 'ENVIADO', 'ENTREGADO', 'CANCELADO')),
    direccion       VARCHAR2(200 CHAR)  NOT NULL CONSTRAINT ck_pedido_direccion CHECK (LENGTH(TRIM(direccion)) >= 10),
    comentarios     VARCHAR2(1000 CHAR)
) TABLESPACE APP_DATA;

-- Tabla de detalle de pedidos con restricciones de cantidad y precio
CREATE TABLE detalle_pedidos (
    id_detalle      NUMBER(12)          CONSTRAINT pk_detalle_pedido PRIMARY KEY,
    id_pedido       NUMBER(10)          NOT NULL CONSTRAINT fk_detalle_pedido REFERENCES pedidos(id_pedido) ON DELETE CASCADE,
    id_producto     NUMBER(8)           NOT NULL CONSTRAINT fk_detalle_producto REFERENCES productos(id_producto),
    cantidad        NUMBER(6)           NOT NULL CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0),
    precio_unitario NUMBER(10,2)        NOT NULL CONSTRAINT ck_detalle_precio CHECK (precio_unitario > 0),
    subtotal        NUMBER(12,2)        NOT NULL,
    -- Restricción compuesta para evitar duplicados
    CONSTRAINT uk_detalle_pedido_producto UNIQUE (id_pedido, id_producto),
    -- Restricción calculada para verificar subtotal
    CONSTRAINT ck_detalle_subtotal CHECK (subtotal = cantidad * precio_unitario)
) TABLESPACE APP_DATA;

-- =====================================================
-- ÍNDICES PARA MEJORAR RENDIMIENTO
-- =====================================================

CREATE INDEX idx_usuario_departamento ON usuarios(id_departamento) TABLESPACE APP_INDEXES;
CREATE INDEX idx_usuario_estado ON usuarios(estado) TABLESPACE APP_INDEXES;
CREATE INDEX idx_usuario_correo ON usuarios(correo) TABLESPACE APP_INDEXES;
CREATE INDEX idx_producto_categoria ON productos(categoria) TABLESPACE APP_INDEXES;
CREATE INDEX idx_producto_activo ON productos(activo) TABLESPACE APP_INDEXES;
CREATE INDEX idx_pedido_fecha ON pedidos(fecha_pedido) TABLESPACE APP_INDEXES;
CREATE INDEX idx_pedido_estado ON pedidos(estado) TABLESPACE APP_INDEXES;
CREATE INDEX idx_pedido_usuario ON pedidos(id_usuario) TABLESPACE APP_INDEXES;

-- =====================================================
-- SECUENCIAS PARA GENERAR IDs AUTOMÁTICAMENTE
-- =====================================================

CREATE SEQUENCE seq_departamento START WITH 1 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_usuario START WITH 1000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_producto START WITH 10000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_pedido START WITH 100000 INCREMENT BY 1 NOCACHE;
CREATE SEQUENCE seq_detalle_pedido START WITH 1 INCREMENT BY 1 NOCACHE;

-- =====================================================
-- TRIGGERS PARA ASIGNAR IDs AUTOMÁTICAMENTE
-- =====================================================

CREATE OR REPLACE TRIGGER trg_departamento_id
    BEFORE INSERT ON departamentos
    FOR EACH ROW
BEGIN
    IF :NEW.id_departamento IS NULL THEN
        :NEW.id_departamento := seq_departamento.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_usuario_id
    BEFORE INSERT ON usuarios
    FOR EACH ROW
BEGIN
    IF :NEW.id_usuario IS NULL THEN
        :NEW.id_usuario := seq_usuario.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_producto_id
    BEFORE INSERT ON productos
    FOR EACH ROW
BEGIN
    IF :NEW.id_producto IS NULL THEN
        :NEW.id_producto := seq_producto.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_pedido_id
    BEFORE INSERT ON pedidos
    FOR EACH ROW
BEGIN
    IF :NEW.id_pedido IS NULL THEN
        :NEW.id_pedido := seq_pedido.NEXTVAL;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_detalle_pedido_id
    BEFORE INSERT ON detalle_pedidos
    FOR EACH ROW
BEGIN
    IF :NEW.id_detalle IS NULL THEN
        :NEW.id_detalle := seq_detalle_pedido.NEXTVAL;
    END IF;
END;
/

-- =====================================================
-- DATOS DE EJEMPLO
-- =====================================================

-- Insertar departamentos de ejemplo
INSERT INTO departamentos (nombre, codigo, presupuesto) VALUES ('Tecnología', 'TEC', 50000.00);
INSERT INTO departamentos (nombre, codigo, presupuesto) VALUES ('Ventas', 'VEN', 30000.00);
INSERT INTO departamentos (nombre, codigo, presupuesto) VALUES ('Recursos Humanos', 'RRH', 25000.00);
INSERT INTO departamentos (nombre, codigo, presupuesto) VALUES ('Marketing', 'MKT', 20000.00);

-- Insertar productos de ejemplo
INSERT INTO productos (codigo_barras, nombre, descripcion, precio, stock, categoria, peso_kg) 
VALUES ('1234567890123', 'Laptop Dell XPS 13', 'Laptop ultrabook con procesador Intel i7', 1299.99, 10, 'ELECTRONICA', 1.2);

INSERT INTO productos (codigo_barras, nombre, descripcion, precio, stock, categoria, peso_kg) 
VALUES ('2345678901234', 'Camiseta Nike Dri-FIT', 'Camiseta deportiva de alta tecnología', 29.99, 50, 'ROPA', 0.2);

INSERT INTO productos (codigo_barras, nombre, descripcion, precio, stock, categoria, peso_kg) 
VALUES ('3456789012345', 'Aspiradora Dyson V11', 'Aspiradora inalámbrica de alta potencia', 599.99, 5, 'HOGAR', 2.8);

-- Insertar usuarios de ejemplo
INSERT INTO usuarios (nombre, apellido, correo, telefono, edad, salario, id_departamento, fecha_nacimiento) 
VALUES ('Juan', 'Pérez', 'juan.perez@empresa.com', '+507-6123-4567', 30, 2500.00, 1, DATE '1994-05-15');

INSERT INTO usuarios (nombre, apellido, correo, telefono, edad, salario, id_departamento, fecha_nacimiento) 
VALUES ('María', 'González', 'maria.gonzalez@empresa.com', '+507-6234-5678', 28, 2200.00, 2, DATE '1996-08-22');

INSERT INTO usuarios (nombre, apellido, correo, telefono, edad, salario, id_departamento, fecha_nacimiento) 
VALUES ('Carlos', 'Rodríguez', 'carlos.rodriguez@empresa.com', '+507-6345-6789', 35, 3000.00, 1, DATE '1989-12-10');

COMMIT;

-- Mensaje de confirmación
SELECT 'Script 01-setup-oracle.sql ejecutado correctamente - ' || TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI:SS') AS resultado FROM DUAL;