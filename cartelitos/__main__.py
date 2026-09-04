"""Punto de entrada: `python3 -m cartelitos` (y lo que llama bin/fatal)."""
import sys

from . import daemon, offsets, setup, system


def _sync_reset(who):
    """`fatal sync reset [artista|all]`. Sin nombre, el artista que suena.

    Va por acá y no por el daemon a propósito: lo aprendido vive en un archivo,
    así que se puede mirar y borrar sin que haya nada corriendo. Ojo con lo
    otro: el daemon vivo se enteró de esto recién en el próximo cambio de tema
    (su `session_offset` ya tiene adentro el offset viejo del artista)."""
    if who == "all":
        n = len(offsets.all_offsets())
        if n == 0:
            print("nothing learned yet, nothing to forget")
            return 0
        try:
            answer = input(f"forget the offsets of all {n} artists? [y/N] ")
        except (KeyboardInterrupt, EOFError):
            print()
            return 1
        if answer.strip().lower() not in ("y", "yes"):
            print("left alone")
            return 1
        offsets.reset_all()
        print(f"forgot {n} artist offset(s)")
        return 0
    if not who:
        track = system.playerctl_state()
        who = (track or {}).get("artist") or ""
        if not who:
            print("nothing playing — name the artist: fatal sync reset \"<artist>\"")
            return 1
    if offsets.reset(who):
        print(f"forgot the offset of {who}")
        return 0
    print(f"nothing learned about {who}")
    return 1


def run(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    # lo usa `fatal status`: qué falta instalar y qué se pierde por cada cosa
    if "--check" in argv:
        for line in system.health_lines():
            print(line)
        sys.exit(0)
    if "--sync-show" in argv:
        for line in offsets.show_lines():
            print(line)
        sys.exit(0)
    if "--sync-reset" in argv:
        rest = argv[argv.index("--sync-reset") + 1:]
        sys.exit(_sync_reset(rest[0].strip() if rest else ""))
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
