#!/usr/bin/env python3
import os
import psycopg2
import time
import requests
import subprocess
import traceback
import sys

# Todas estas variables deben estar inyectadas en el Pod
# mediante el deployment
MAX_DB_READY_RETRIES = int(os.getenv('MAX_DB_READY_RETRIES', '30'))
DB_READY_DELAY = int(os.getenv('DB_READY_DELAY', '2'))
# Odoo tarda 1-3 minutos en primer arranque en hardware embebido.
# 60 intentos × 5 s = 5 minutos de margen.
MAX_INIT_RETRIES = int(os.getenv('MAX_INIT_RETRIES', '60'))
INIT_DELAY = int(os.getenv('INIT_DELAY', '5'))

# Este tipo de variables las entiende odoo-bin
DB_HOST = os.getenv('PGHOST', 'odoo-postgres')
DB_PORT = os.getenv('PGPORT', '5432')
DB_USER = os.getenv('PGUSER', 'odoo')
DB_PASSWORD = os.getenv('PGPASSWORD', 'odoo')
DB_NAME = os.getenv('DB_NAME', 'odoo')
HTTP_PORT = os.getenv('HTTP_PORT', '8069')

ADMIN_USERNAME = os.getenv('ADMIN_USERNAME', 'odoo@example.com')
ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD', 'adm')
MASTER_PASSWORD = os.getenv('MASTER_PASSWORD', 'miadminpasswordodoo')

ODOO_URL = os.getenv('ODOO_URL', 'http://localhost:8069')

# Fichero marcador en volumen persistente: indica que la inicialización
# de la base de datos ya se completó en un arranque anterior.
# Si existe se omite toda la fase de inicialización y Odoo arranca directamente.
DB_INIT_MARKER = os.getenv('DB_INIT_MARKER', '/var/lib/odoo/.db-initialized')

# Fallbacks para escenarios donde /var/lib/odoo raíz no es escribible por el
# usuario del contenedor (bind-mount con permisos host estrictos).
DB_INIT_MARKER_FALLBACKS = [
    '/var/lib/odoo/sessions/.db-initialized',
    '/tmp/.db-initialized',
]
# Puerto exclusivo para el proceso Odoo temporal de inicialización.
# Hardcodeado intencionalmente: no debe ser accesible desde el exterior
# durante la fase de arranque/inicialización de la base de datos.
INIT_HTTP_PORT = "18069"
INIT_ODOO_URL = f"http://localhost:{INIT_HTTP_PORT}"

DB_CREATE_ENDPOINT = f"{INIT_ODOO_URL}/web/database/create"

def print(*args, **kwargs):
    # Asegura que flush=True esté siempre presente
    kwargs['flush'] = True
    return __builtins__.print(*args, **kwargs)

def error_handler(e):
    print("\n" + "="*50)
    print("❌ ERROR FATAL CAPTURADO ❌")
    print(f"Tipo de Error: {type(e).__name__}")
    print(f"Mensaje: {e}")
    traceback.print_exc()
    PAUSE_TIME = 300
    print(f"\nEl proceso dormirá por {PAUSE_TIME} segundos.")
    print("¡Usa 'podman exec' / 'kubectl exec' para entrar y diagnosticar el problema AHORA!")
    print("="*50 + "\n")
    time.sleep(PAUSE_TIME)
    sys.exit(1)

def pg_isready(timeout=2):
    try:
        conn = psycopg2.connect(
            dbname='postgres',
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT,
            connect_timeout=timeout,
        )
        conn.close()
        return True
    except Exception as e:
        print(f"Postgres no accesible: {e}")
        return False

# ── Comprobaciones directas contra PostgreSQL ──────────────────────────────────
# Estas funciones no dependen de que Odoo esté levantado, evitando el problema
# de los timeouts HTTP que impedían crear el DB_INIT_MARKER.

def db_exists():
    """Comprueba si la base de datos Odoo existe a nivel de PostgreSQL."""
    try:
        conn = psycopg2.connect(
            dbname='postgres',
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT,
            connect_timeout=5,
        )
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM pg_database WHERE datname = %s",
                (DB_NAME,)
            )
            exists = cur.fetchone() is not None
        conn.close()
        print(f"DB '{DB_NAME}': {'existe' if exists else 'NO existe'}")
        return exists
    except Exception as e:
        print(f"Error comprobando existencia de DB: {e}")
        return False

def db_schema_initialized():
    """
    Comprueba si la DB Odoo ya tiene el esquema mínimo instalado.
    Detecta la presencia de la tabla ir_module_module, que sólo existe
    cuando 'base' se ha inicializado correctamente.
    """
    try:
        conn = psycopg2.connect(
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            host=DB_HOST,
            port=DB_PORT,
            connect_timeout=5,
        )
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 1
                FROM information_schema.tables
                WHERE table_schema = 'public'
                  AND table_name   = 'ir_module_module'
            """)
            initialized = cur.fetchone() is not None
        conn.close()
        print(f"Esquema Odoo: {'inicializado' if initialized else 'NO inicializado'}")
        return initialized
    except Exception as e:
        print(f"Error comprobando esquema Odoo: {e}")
        return False

# ──────────────────────────────────────────────────────────────────────────────

def initialize_db_via_api():
    """
    Crea la base de datos Odoo usando el endpoint /web/database/create.
    Este endpoint configura el idioma y el país correctamente (es_ES / es).
    La creación puede tardar varios minutos: no se fija un timeout HTTP corto.
    """
    payload = {
        "master_pwd": MASTER_PASSWORD,
        "name": DB_NAME,
        "login": ADMIN_USERNAME,
        "password": ADMIN_PASSWORD,
        "phone": "",
        "lang": "es_ES",
        "country_code": "es",
        "demo": "",
    }
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    print(f"Enviando petición de creación de DB a {DB_CREATE_ENDPOINT} ...")
    print("(esto puede tardar varios minutos — esperar sin interrumpir)")
    # Sin timeout explícito: la creación de DB puede tardar 3-10 minutos.
    response = requests.post(DB_CREATE_ENDPOINT, data=payload, headers=headers)
    print(f"Respuesta de inicialización DB: HTTP {response.status_code}")
    if response.status_code not in (200, 303):
        print(f"Respuesta inesperada ({response.status_code}): {response.text[:500]}")
        raise Exception(f"Falló la inicialización vía API (HTTP {response.status_code})")
    print("Base de datos Odoo inicializada vía API.")

def run_odoo():
    """
    Arranca un proceso Odoo temporal en INIT_HTTP_PORT (18069) y espera
    a que responda en /web/health.

    Mejoras respecto a la versión anterior:
    - MAX_INIT_RETRIES=60, INIT_DELAY=5 → hasta 5 minutos de espera.
    - Duerme ANTES de cada intento (da tiempo a que Odoo arranque).
    - Detecta si el proceso Odoo muere prematuramente y aborta limpiamente.
    """
    CUSTOM_ADDONS = "/home/odoo/.local/custom_addons"
    prepare_custom_addons_path(CUSTOM_ADDONS)

    print(f"Arrancando proceso Odoo temporal en puerto interno {INIT_HTTP_PORT}...")
    process = subprocess.Popen([
        '/odoo/odoo-bin',
        '--db_host', DB_HOST,
        '--db_port', DB_PORT,
        '--db_user', DB_USER,
        '--db_password', DB_PASSWORD,
        '--http-port', INIT_HTTP_PORT,
        '--without-demo', 'True',
        '--addons-path', '/odoo/addons,/home/odoo/.local/custom_addons',
    ], cwd="/odoo")

    print(f"Esperando a que Odoo responda en {INIT_ODOO_URL}/web/health "
          f"(máx {MAX_INIT_RETRIES} intentos × {INIT_DELAY}s) ...")

    for i in range(MAX_INIT_RETRIES):
        # Esperar primero: el proceso necesita tiempo para arrancar
        time.sleep(INIT_DELAY)

        # Comprobar si el proceso murió antes de tiempo
        if process.poll() is not None:
            print(f"❌ El proceso Odoo temporal terminó inesperadamente "
                  f"(código de salida: {process.returncode})")
            sys.exit(1)

        try:
            print(f"  Intento {i+1}/{MAX_INIT_RETRIES}: GET {INIT_ODOO_URL}/web/health")
            r = requests.get(f"{INIT_ODOO_URL}/web/health", timeout=8)
            if r.status_code == 200 and "pass" in r.text.lower():
                print(f"✅ Odoo temporal levantado y saludable (intento {i+1}).")
                return process
        except Exception:
            pass  # Todavía no está listo, seguir intentando

    print(f"❌ Odoo temporal no respondió tras {MAX_INIT_RETRIES} intentos.")
    process.terminate()
    process.wait()
    sys.exit(1)

def prepare_custom_addons_path(custom_path):
    """
    Prepara la carpeta de addons para que Odoo 19 la reconozca como válida.
    Crea un módulo dummy si la carpeta está vacía.
    """
    if not os.path.exists(custom_path):
        os.makedirs(custom_path, exist_ok=True)
        print(f"Carpeta creada: {custom_path}")

    has_modules = False
    for root, dirs, files in os.walk(custom_path):
        if "__manifest__.py" in files:
            has_modules = True
            break

    if not has_modules:
        print("No se detectaron módulos en el PV. Creando módulo dummy de validación...")
        module_dir = os.path.join(custom_path, "path_validator")
        os.makedirs(module_dir, exist_ok=True)
        with open(os.path.join(module_dir, "__init__.py"), "w") as f:
            f.write("# Módulo dummy para validar el path")
        manifest_content = """{
    'name': 'Path Validator',
    'version': '1.0',
    'category': 'Hidden',
    'license': 'LGPL-3',
    'author': 'Odoo Admin',
    'depends': ['base'],
    'installable': True,
    'auto_install': False,
    }"""
        with open(os.path.join(module_dir, "__manifest__.py"), "w") as f:
            f.write(manifest_content)
        print(f"Módulo dummy creado con éxito en {module_dir}")

def marker_candidates():
    """Devuelve rutas de marcador (primaria + fallbacks), sin duplicados."""
    candidates = [DB_INIT_MARKER] + DB_INIT_MARKER_FALLBACKS
    unique = []
    for path in candidates:
        if path and path not in unique:
            unique.append(path)
    return unique

def mark_db_initialized():
    """
    Intenta crear el fichero marcador para que arranques posteriores
    omitan la inicialización.

    Devuelve True si se creó en alguna ruta candidata.
    Devuelve False si no fue posible escribir ningún marcador.
    """
    for marker_path in marker_candidates():
        marker_dir = os.path.dirname(marker_path)
        try:
            os.makedirs(marker_dir, exist_ok=True)
            with open(marker_path, 'w') as f:
                f.write("ok\n")
            print(f"✅ Marcador de inicialización creado: {marker_path}")
            return True
        except PermissionError as e:
            print(f"⚠️ Sin permisos para crear marcador en {marker_path}: {e}")
        except Exception as e:
            print(f"⚠️ Falló creación de marcador en {marker_path}: {e}")

    print("⚠️ No se pudo crear ningún marcador persistente; se continuará con detección por PostgreSQL.")
    return False


def is_first_boot():
    # Si existe cualquier marcador válido, se considera arranque normal.
    for marker_path in marker_candidates():
        if os.path.exists(marker_path):
            return False
    return True

def exec_odoo():
    print("Sustituyendo intérprete Python por Odoo (os.execvp)...")
    try:
        os.chdir("/odoo")
    except OSError as e:
        print(f"Error: No se pudo cambiar el directorio de trabajo a /odoo: {e}")
        sys.exit(1)

    CUSTOM_ADDONS = "/home/odoo/.local/custom_addons"
    prepare_custom_addons_path(CUSTOM_ADDONS)

    os.execvp("/odoo/odoo-bin", [
        "/odoo/odoo-bin",
        "--db_host", DB_HOST,
        "--db_port", DB_PORT,
        "--db_user", DB_USER,
        "--db_password", DB_PASSWORD,
        "-d", DB_NAME,
        '--http-port', HTTP_PORT,
        '--without-demo', 'True',
        '--addons-path', '/odoo/addons,/home/odoo/.local/custom_addons',
        '--no-database-list',
    ])

if __name__ == '__main__':
    try:
        # ── 1. Esperar a que PostgreSQL esté accesible ─────────────────────────
        print(f"Comprobando accesibilidad de PostgreSQL ({MAX_DB_READY_RETRIES} intentos)...")
        for i in range(MAX_DB_READY_RETRIES):
            if pg_isready():
                print("PostgreSQL accesible.")
                break
            print(f"  Intento {i+1}/{MAX_DB_READY_RETRIES}: PostgreSQL no responde, "
                  f"esperando {DB_READY_DELAY}s...")
            time.sleep(DB_READY_DELAY)
        else:
            print("❌ PostgreSQL no está accesible después de varios intentos. Abortando.")
            sys.exit(1)

        # ── 2. Arranque normal: marcador ya existe ─────────────────────────────
        if not is_first_boot():
            print(f"Marcador encontrado ({DB_INIT_MARKER}): "
                  "saltando inicialización, arrancando Odoo directamente.")
            exec_odoo()
            # os.execvp() nunca retorna

        # ── 3. Primer arranque ─────────────────────────────────────────────────
        print("Primer arranque detectado — comprobando estado de la DB...")

        # Fast-path: la DB ya existe e inicializada (p.ej. el contenedor
        # fue recreado pero el volumen persistente tiene los datos).
        if db_exists() and db_schema_initialized():
            print("La DB ya existe y tiene esquema Odoo. "
                  "Intentando crear marcador y arrancando directamente.")
            mark_db_initialized()
            exec_odoo()

        # ── 3a. Arrancar Odoo temporal para la creación de DB vía API ─────────
        print("DB no inicializada. Arrancando Odoo temporal para creación de DB...")
        odoo_proc = run_odoo()

        # ── 3b. Crear la base de datos vía API (incluye localización es_ES) ───
        # Sólo si la DB no existe o el esquema está incompleto.
        if not db_exists() or not db_schema_initialized():
            print("Inicializando DB vía API /web/database/create ...")
            try:
                initialize_db_via_api()
            except Exception as e:
                print(f"❌ Error durante inicialización vía API: {e}")
                odoo_proc.terminate()
                odoo_proc.wait()
                sys.exit(1)

            # Verificar con Postgres que la inicialización realmente funcionó
            print("Verificando inicialización directamente en PostgreSQL...")
            # Dar unos segundos a que Odoo finalice las transacciones pendientes
            time.sleep(5)
            if not db_schema_initialized():
                print("❌ El esquema Odoo no está presente en la DB tras la inicialización. "
                      "Abortando.")
                odoo_proc.terminate()
                odoo_proc.wait()
                sys.exit(1)
        else:
            print("DB ya existe e inicializada (detectado durante el arranque temporal).")

        # ── 3c. Terminar Odoo temporal y crear el marcador ────────────────────
        print("Terminando proceso Odoo temporal...")
        odoo_proc.terminate()
        odoo_proc.wait()

        marker_created = mark_db_initialized()
        if not marker_created:
            print("⚠️ Arranque continuará sin marcador persistente (DB ya verificada).")

        # ── 4. Arrancar Odoo definitivo ────────────────────────────────────────
        exec_odoo()

    except Exception as e:
        error_handler(e)

