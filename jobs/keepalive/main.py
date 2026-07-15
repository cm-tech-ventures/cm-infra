"""Cloud Run Job leve: SELECT 1 em cada banco Supabase da lista, para evitar
que o free-tier pause o projeto por inatividade (CMV-53).

Lista de DSNs vem da env KEEPALIVE_DB_DSNS (Secret Manager), separadas por ';'.
Falha (exit != 0) em qualquer DSN inválida/inacessível — o Cloud Run marca a
execução como failed e o alerta de Cloud Monitoring dispara (ver
modules/monitoring-alert-email).
"""
import os
import sys
import psycopg2

DSN_SEPARATOR = ";"


def redact(dsn: str) -> str:
    # Nunca logar credencial: só o host, para diagnóstico.
    if "@" in dsn:
        return dsn.split("@", 1)[1]
    return dsn


def main() -> int:
    raw = os.environ.get("KEEPALIVE_DB_DSNS", "")
    dsns = [d.strip() for d in raw.split(DSN_SEPARATOR) if d.strip()]
    if not dsns:
        print("KEEPALIVE_DB_DSNS vazio — nada para verificar.", file=sys.stderr)
        return 1

    failures = []
    for dsn in dsns:
        host = redact(dsn)
        try:
            conn = psycopg2.connect(dsn, connect_timeout=10)
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
                    cur.fetchone()
                print(f"OK  {host}")
            finally:
                conn.close()
        except Exception as exc:
            print(f"FAIL {host}: {exc}", file=sys.stderr)
            failures.append(host)

    if failures:
        print(f"{len(failures)}/{len(dsns)} banco(s) falharam: {failures}", file=sys.stderr)
        return 1

    print(f"{len(dsns)}/{len(dsns)} banco(s) OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
