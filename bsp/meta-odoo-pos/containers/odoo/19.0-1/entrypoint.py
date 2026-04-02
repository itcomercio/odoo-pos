#!/usr/bin/env python3
import os
import psycopg2
import time
import requests
import subprocess
import signal
import traceback
import sys

# Todas estas variables deben estar inyectadas en el Pod
# mediante el deployment
MAX_DB_READY_RETRIES = int(os.getenv('MAX_DB_READY_RETRIES', '30'))
DB_READY_DELAY = int(os.getenv('DB_READY_DELAY', '2'))
MAX_INIT_RETRIES = int(os.getenv('MAX_INIT_RETRIES', '10'))
INIT_DELAY = int(os.getenv('INIT_DELAY', '2'))

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

# Puerto exclusivo para el proceso Odoo temporal de inicialización.
# Hardcodeado intencionalmente: no debe ser accesible desde el exterior
# durante la fase de arranque/inicialización de la base de datos.
INIT_HTTP_PORT = "18069"
INIT_ODOO_URL = f"http://localhost:{INIT_HTTP_PORT}"

AUTH_ENDPOINT = f"{INIT_ODOO_URL}/web/session/authenticate"
DB_CREATE_ENDPOINT = f"{INIT_ODOO_URL}/web/database/create"

def print(*args, **kwargs):
    # Asegura que flush=True esté siempre presente
    kwargs['flush'] = True
    
    # Llama a la función print original (del módulo builtins)
    return __builtins__.print(*args, **kwargs)

def error_handler(e):
    # --- Manejador de Errores Global ---
    print("\n" + "="*50)
    print("❌ ERROR FATAL CAPTURADO ❌")
    print(f"Tipo de Error: {type(e).__name__}")
    print(f"Mensaje: {e}")
    
    # Imprimir el traceback completo para el diagnóstico
    traceback.print_exc()
    
    # ⏱️ Pausa de 5 minutos (300 segundos)
    PAUSE_TIME = 300
    print(f"\nEl proceso dormirá por {PAUSE_TIME} segundos.")
    print("¡Usa 'kubectl exec' para entrar y diagnosticar el problema AHORA!")
    print("="*50 + "\n")
    
    time.sleep(PAUSE_TIME)
    
    # Después de la pausa, el script termina.
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

def is_db_initialized():
    print("Ver si la base de datos está inicializada")
    headers = {"Content-Type": "application/json"}
    auth_payload = {
        "jsonrpc": "2.0",
        "params": {
            "db": DB_NAME,
            "login": ADMIN_USERNAME,
            "password": ADMIN_PASSWORD
        }
    }
    try:
        response = requests.post(AUTH_ENDPOINT, json=auth_payload, headers=headers)
        if response.status_code != 200:
            if response.status_code == 401:
                print("Error 401: No autorizado. Credenciales incorrectas para el usuario admin.")
            elif response.status_code == 500:
                print("Error 500: Error interno del servidor Odoo al intentar autenticar el usuario admin.")
            else:
                print(f"Error HTTP al autenticar usuario admin: {response.status_code}")
            print("Respuesta del servidor:", response.text)
            return False
        result = response.json().get('result', {})
        uid = result.get("uid")
        is_admin = result.get("is_admin")
        print(f"UID del usuario autenticado: {uid}")
        if is_admin:
            print("El usuario es administrador.")
            return True
        else:
            print("El usuario no es administrador.")
            return False
    except Exception as e:
        print(f"Error autenticando usuario admin: {e}")
        return False

def initialize_db_via_api():
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
    try:
        response = requests.post(DB_CREATE_ENDPOINT, data=payload, headers=headers)
        print("Respuesta de inicialización DB:", response.status_code, response.text)
        if response.status_code == 200:
            print("Base de datos Odoo inicializada vía API.")
        else:
            print(f"Error inicializando la base de datos Odoo vía API: {response.status_code}")
            print("Respuesta:", response.text)
            raise Exception("Falló la inicialización vía API")
    except Exception as e:
        print(f"Excepción al inicializar la base de datos Odoo vía API: {e}")
        raise

def run_odoo():
    print(f"Arrancando proceso Odoo temporal (inicializacion) en puerto interno {INIT_HTTP_PORT}...")

    process = subprocess.Popen([
        '/odoo/odoo-bin',
        '--db_host', DB_HOST,
        '--db_port', DB_PORT,
        '--db_user', DB_USER,
        '--db_password', DB_PASSWORD,
        '--http-port', INIT_HTTP_PORT,
        '--without-demo', 'True',
        '--addons-path', '/odoo/addons,/home/odoo/.local/custom_addons'
    ],
    cwd="/odoo"
    )

    print(f"\nEsperamos a que Odoo esté disponible en {INIT_ODOO_URL}/web/health, intentos -> {MAX_INIT_RETRIES} ...")
    for i in range(MAX_INIT_RETRIES):
        try:
            print(f"\nIntentando {INIT_ODOO_URL}/web/health ...")
            r = requests.get(f"{INIT_ODOO_URL}/web/health", timeout=8)
            if r.status_code == 200 and "pass" in r.text:
                print(f"Odoo temporal levantado y saludable en puerto {INIT_HTTP_PORT}.")
                return process
        except Exception:
            pass
        time.sleep(INIT_DELAY)

    print("Odoo temporal no está accesible por HTTP después de varios intentos.")
    process.terminate()
    process.wait()
    exit(1)

def prepare_custom_addons_path(custom_path):
    """
    Prepara la carpeta de addons para que Odoo 19 la reconozca como válida.
    Crea un módulo dummy si la carpeta está vacía.
    """
    # 1. Asegurarnos de que la carpeta base existe
    if not os.path.exists(custom_path):
        os.makedirs(custom_path, exist_ok=True)
        print(f"Carpeta creada: {custom_path}")

    # 2. Verificar si hay módulos válidos (buscando archivos __manifest__.py)
    has_modules = False
    for root, dirs, files in os.walk(custom_path):
        if "__manifest__.py" in files:
            has_modules = True
            break

    # 3. Si no hay módulos, creamos el "Path Validator"
    if not has_modules:
        print("No se detectaron módulos en el PV. Creando módulo dummy de validación...")
        module_dir = os.path.join(custom_path, "path_validator")
        os.makedirs(module_dir, exist_ok=True)
        
        # Crear __init__.py
        with open(os.path.join(module_dir, "__init__.py"), "w") as f:
            f.write("# Módulo dummy para validar el path")
            
        # Crear __manifest__.py (Estructura Odoo 19)
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

def exec_odoo():
    print("Sustituyendo interprete python por Odoo.")
    try:
        os.chdir("/odoo")
        print("Directorio de trabajo actual cambiado a /odoo")
    except OSError as e:
        # Es buena práctica manejar el error si el directorio no existe
        print(f"Error: No se pudo cambiar el directorio de trabajo a /odoo. {e}")
        # Puedes decidir si terminar el programa o continuar
        return

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
        '--no-database-list'
    ])

if __name__ == '__main__':
    try:
        # 1. Esperar a que la DB esté accesible
        print(f"Comprobar si PostgreSQL es accesible {MAX_DB_READY_RETRIES} intentos")
        for i in range(MAX_DB_READY_RETRIES):
            if pg_isready():
                print("PostgreSQL accesible.")
                break
            else:
                print("Esperando 2 segundos a que PostgreSQL esté accesible...")
                time.sleep(DB_READY_DELAY)
        else:
            print("PostgreSQL no está accesible después de varios intentos. Abortando.")
            exit(1)

        # 2. Arrancar Odoo como proceso hijo para inicialización/check
        odoo_proc = run_odoo()

        # 3. Comprobar si la base está inicializada
        if is_db_initialized():
            print("Base de datos Odoo inicializada (usuario admin accesible).")
            # Terminamos el Odoo hijo, lanzamos Odoo definitivo como proceso padre
            odoo_proc.terminate()
            odoo_proc.wait()
            exec_odoo()
        else:
            print("Base de datos NO inicializada. Inicializando vía API...")
            try:
                initialize_db_via_api()
                print("Inicialización completada, reiniciando Odoo...")
                # Terminamos el hijo, y lanzamos Odoo como proceso padre
                odoo_proc.terminate()
                odoo_proc.wait()
                exec_odoo()
            except Exception as e:
                print("Error durante inicialización vía API:", e)
                odoo_proc.terminate()
                odoo_proc.wait()
                exit(1)
    except Exception as e:
            error_handler(e)

