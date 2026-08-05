"""Cosas chicas que usa todo el resto: el log y un par de constantes."""
import time

UA = "fatal-lyrics/3.0 (https://github.com/FeroxShark/fatal-lyrics)"
FIELD_SEP = "\x1f"

def log(*args):
    print(time.strftime("%H:%M:%S"), *args, flush=True)
