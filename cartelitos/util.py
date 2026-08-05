"""Cosas chicas que usa todo el resto: el log, los archivos de estado y un par
de constantes."""
import os
import shutil
import stat
import sys
import time

UA = "fatal-lyrics/3.0 (https://github.com/FeroxShark/fatal-lyrics)"
FIELD_SEP = "\x1f"

# Todo lo efímero junto y bajo el runtime del usuario, no en /tmp: /tmp lo
# comparten todas las sesiones y no se limpia al cerrar la sesión, así que un
# PID viejo de otro login quedaba tirado ahí pareciendo válido.
RUN_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "cartelitos")
DAEMON_PID_PATH = os.path.join(RUN_DIR, "daemon.pid")
QS_PID_PATH = os.path.join(RUN_DIR, "qs.pid")
LOG_PATH = os.path.join(RUN_DIR, "daemon.log")
QS_LOG_PATH = os.path.join(RUN_DIR, "qs.log")

# El daemon corre semanas seguidas: sin tope, el log crece hasta donde aguante
# el tmpfs (que es RAM).
LOG_MAX = 5 * 1024 * 1024
_log_target = False   # False = todavía no se miró; None = stdout no es archivo


def run_dir():
    """RUN_DIR, creado si hace falta. Devuelve el path igual si no se pudo crear:
    con el error se topa quien escriba, no acá."""
    try:
        os.makedirs(RUN_DIR, exist_ok=True)
    except OSError:
        pass
    return RUN_DIR


def rotate_log(path, limit=LOG_MAX):
    """Corta el log pasado el tope y deja UN backup (.1).

    Trunca el MISMO inodo (copiar y truncar, como el copytruncate de logrotate)
    en vez de renombrar: el redirect de bin/fatal ya tiene el archivo abierto y
    un rename se lo llevaría puesto — seguiría escribiendo en el backup y el log
    nuevo quedaría vacío para siempre. Por lo mismo bin/fatal redirige con `>>`:
    en modo append cada escritura vuelve al final real, así el truncado no deja
    un agujero de 5 MB.
    """
    try:
        if os.path.getsize(path) <= limit:
            return False
        shutil.copyfile(path, path + ".1")
        with open(path, "r+") as f:
            f.truncate(0)
        return True
    except OSError:
        return False


def _stdout_log():
    """El archivo detrás de stdout, o None si es una terminal o un pipe (correr
    el daemon a mano no tiene nada que rotar)."""
    global _log_target
    if _log_target is not False:
        return _log_target
    _log_target = None
    try:
        fd = sys.stdout.fileno()
        if stat.S_ISREG(os.fstat(fd).st_mode):
            _log_target = os.readlink(f"/proc/self/fd/{fd}")
    except (OSError, ValueError, AttributeError):
        pass
    return _log_target


def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)
    path = _stdout_log()
    if path:
        rotate_log(path)
