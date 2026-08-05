"""Punto de entrada: `python3 -m cartelitos` (y lo que llama bin/fatal)."""
import sys

from . import daemon, setup


def run(argv=None):
    argv = sys.argv[1:] if argv is None else argv
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
