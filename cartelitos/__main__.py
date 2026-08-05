"""Punto de entrada: `python3 -m cartelitos` (y lo que llama bin/fatal)."""
import sys

from . import daemon, setup, system


def run(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    # lo usa `fatal status`: qué falta instalar y qué se pierde por cada cosa
    if "--check" in argv:
        for line in system.health_lines():
            print(line)
        sys.exit(0)
    if "--setup" in argv:
        try:
            setup.setup()
        except (KeyboardInterrupt, EOFError):
            print("\nok, bye")
        sys.exit(0)
    try:
        daemon.main()
    except KeyboardInterrupt:
        sys.exit(0)


if __name__ == "__main__":
    run()
