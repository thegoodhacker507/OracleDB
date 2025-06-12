# Oracle seguro en Docker

## Descripción

Este proyecto proporciona una configuración completa de Oracle Database 23ai FREE en Docker Desktop para Windows 11, con un enfoque en la seguridad y la automatización. Se incluyen medidas de seguridad robustas, como el cifrado, el endurecimiento y las copias de seguridad automatizadas, para garantizar la integridad y la confidencialidad de los datos.

## Requisitos

- Docker Desktop
- Cuenta en Oracle Container Registry
- Cuenta en GitHub

## Objetivos

-   Implementar Oracle Database 23ai Free en un contenedor Docker.
-   Configurar medidas de seguridad avanzadas para proteger la base de datos.
-   Automatizar las copias de seguridad para garantizar la recuperación ante desastres.
-   Documentar el proceso de implementación y configuración para facilitar la replicación y el mantenimiento.

## Estructura del Proyecto

El proyecto se organiza de la siguiente manera:

├── README.md # Documento principal con la guía del proyecto
├── docker-compose.yml # Archivo de configuración de Docker Compose
├── scripts/
│ ├── init.sql # Script de inicialización de la base de datos
│ ├── backup.sh # Script para realizar copias de seguridad
│ └── restore.sh # Script para restaurar copias de seguridad
└── security/
├── pfSense/ # Configuración teórica para pfSense
└── OnionSecurity/ # Configuración teórica para Onion Security


## Guía de Implementación

### Prerrequisitos

Antes de comenzar, asegúrate de tener instalado lo siguiente:

-   [Docker Desktop para Windows](https://www.docker.com/products/docker-desktop/)
-   [Git](https://git-scm.com/) (opcional, pero recomendado para clonar el repositorio)

### Clonar el Repositorio (Opcional)

Si tienes Git instalado, puedes clonar el repositorio para obtener todos los archivos necesarios:

```bash
git clone https://github.com/thegoodhacker507//OracleDB.git
cd OracleDB
docker-compose up -d