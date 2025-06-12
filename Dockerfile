FROM container-registry.oracle.com/database/free:latest

LABEL maintainer="albinabdiel@gmail.com" \
      description="Oracle Database 23ai FREE con TDE, hardening, backup y scripts automáticos" \
      version="1.0"

ENV ORACLE_PWD=Oracle123! \
    ORACLE_CHARACTERSET=AL32UTF8 \
    ENABLE_ARCHIVELOG=true

USER root

RUN mkdir -p /opt/oracle/scripts/setup \
             /opt/oracle/scripts/startup \
             /opt/oracle/backup/scripts \
             /opt/oracle/admin/wallet \
 && chown -R oracle:oinstall /opt/oracle/scripts \
 && chown -R oracle:oinstall /opt/oracle/backup \
 && chown -R oracle:oinstall /opt/oracle/admin/wallet \
 && chmod -R 755 /opt/oracle/scripts \
 && chmod -R 755 /opt/oracle/backup

COPY scripts/ /opt/oracle/scripts/setup/
COPY config/ /opt/oracle/scripts/startup/
COPY backup/ /opt/oracle/backup/scripts/

RUN chmod +x /opt/oracle/scripts/startup/*.sh \
 && chmod +x /opt/oracle/backup/scripts/*.sh \
 && chmod 644 /opt/oracle/scripts/setup/*.sql

USER oracle

EXPOSE 1521 5500

VOLUME ["/opt/oracle/oradata", "/opt/oracle/backup"]

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=120s \
  CMD /opt/oracle/scripts/startup/healthcheck.sh || exit 1