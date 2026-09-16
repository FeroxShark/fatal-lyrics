"""Mood del tema: determinístico, sin red, sin IA (feedback_ia_sin_creditos:
1) determinista antes que 2) modelo local antes que 3) API opt-in — acá sólo
la parte 1). Lo consume el modo CRT para elegir el set del tema (tanda 6,
corrida 1 + 3)."""
import re
import unicodedata

# Piso/techo de rms ABSOLUTOS (no percentil del propio tema) para mapear
# `energy` a 0..1 comparable ENTRE temas. Calibrados contra los ~300 perfiles
# reales en ~/.cache/cartelitos/audio: la media de rms por tema cae en
# [0.0005, 0.209], con p10≈0.011 y p90≈0.131. 0.02 deja abajo del piso a los
# temas más bajitos (baladas, lofi) y 0.15 arriba del techo sólo a los
# masters más comprimidos (por encima del p90 real); un tema mediano
# (mean≈0.09, la mediana real) cae cerca de 0.5.
ENERGY_RMS_FLOOR = 0.02
ENERGY_RMS_CEIL = 0.15

# Léxico chico es/en, minúsculas y sin tildes (se normaliza lo que se mide
# contra esto, no hace falta duplicar acentuado/sin acento acá).
POSITIVE = {
    "amor", "amo", "amas", "ama", "amamos", "feliz", "felicidad", "alegria",
    "alegre", "fiesta", "bailar", "baile", "sol", "luz", "brillar",
    "brillante", "suerte", "victoria", "ganar", "ganamos", "libre",
    "libertad", "vida", "vivir", "sonrisa", "sonreir", "reir", "risa",
    "esperanza", "sueno", "suenos", "paraiso", "cielo", "estrellas",
    "magia", "hermoso", "hermosa", "bello", "bella", "dulce", "calido",
    "calida", "abrazo", "beso", "besos", "juntos", "juntas", "eterno",
    "eterna", "fuerte", "fuerza", "gloria", "paz", "dorado", "dorada",
    "love", "loving", "happy", "happiness", "joy", "joyful", "party",
    "dance", "dancing", "sun", "shine", "shining", "bright", "lucky",
    "luck", "victory", "win", "winning", "free", "freedom", "life",
    "alive", "smile", "laugh", "hope", "dream", "dreams", "paradise",
    "heaven", "stars", "magic", "beautiful", "sweet", "warm", "hug",
    "kiss", "kisses", "together", "forever", "strong", "strength",
    "glory", "peace", "golden",
}

NEGATIVE = {
    "odio", "odiar", "muerte", "muerto", "muerta", "morir", "dolor",
    "doloroso", "triste", "tristeza", "llorar", "lagrimas", "solo", "sola",
    "soledad", "miedo", "temor", "guerra", "sangre", "herida", "heridas",
    "perdido", "perdida", "oscuridad", "oscuro", "oscura", "infierno",
    "pesadilla", "veneno", "traicion", "mentira", "mentiras", "roto",
    "rota", "romper", "dano", "danio", "sufrir", "sufrimiento", "rabia",
    "furia", "ira", "culpa", "vacio", "vacia", "fantasma", "cadenas",
    "preso", "presa", "llanto", "adios", "despedida",
    "hate", "hatred", "death", "dead", "die", "dying", "pain", "painful",
    "sad", "sadness", "cry", "crying", "tears", "alone", "lonely",
    "loneliness", "fear", "afraid", "war", "blood", "wound", "wounded",
    "lost", "darkness", "dark", "hell", "nightmare", "poison", "betrayal",
    "lie", "lies", "broken", "break", "hurt", "suffer", "suffering",
    "rage", "fury", "anger", "guilt", "empty", "emptiness", "ghost",
    "chains", "prisoner", "goodbye", "farewell",
}

_WORD_RE = re.compile(r"[a-z]+")


def _words(text):
    normalized = unicodedata.normalize("NFKD", text or "")
    ascii_only = normalized.encode("ascii", "ignore").decode("ascii").lower()
    return _WORD_RE.findall(ascii_only)


def valence(lines):
    """-1..1: (pos - neg) / max(pos + neg, 6). `lines` = lista de textos."""
    pos = neg = 0
    for line in lines or []:
        for w in _words(line):
            if w in POSITIVE:
                pos += 1
            elif w in NEGATIVE:
                neg += 1
    return (pos - neg) / max(pos + neg, 6)


def energy(profile_summary, bpm):
    """0..1, comparable ENTRE temas. Con perfil `known`: rms medio de lo
    escuchado mapeado linealmente entre ENERGY_RMS_FLOOR y ENERGY_RMS_CEIL
    (no classify_level: ésa es un percentil DENTRO del propio tema y nunca
    pasa de ~0.35-0.40 aunque el tema entero sea fuerte). Si no hay perfil y
    hay bpm: clamp((bpm-70)/110). Sin nada de eso: 0.5 (ni arriba ni abajo).

    No se mezcla con bpm cuando hay perfil: `profile_summary` no trae bpm/conf
    (TrackProfile.summary() sólo copia rms/cen), así que no hay confianza de
    bpm con la que ponderar acá adentro."""
    if profile_summary and profile_summary.get("known"):
        rms = profile_summary.get("rms") or []
        heard = [v for v in rms if v > 0.0]
        if heard:
            mean_rms = sum(heard) / len(heard)
            span = ENERGY_RMS_CEIL - ENERGY_RMS_FLOOR
            return max(0.0, min(1.0, (mean_rms - ENERGY_RMS_FLOOR) / span))
    if bpm and bpm > 0:
        return max(0.0, min(1.0, (bpm - 70.0) / 110.0))
    return 0.5


def brightness(profile_summary):
    """0..1: media de `cen` del perfil si known, 0.5 si no."""
    if profile_summary and profile_summary.get("known"):
        cen = profile_summary.get("cen") or []
        if cen:
            return sum(cen) / len(cen)
    return 0.5


def mood_for(lines, profile_summary, bpm):
    known = bool(profile_summary and profile_summary.get("known"))
    return {
        "cmd": "mood",
        "valence": round(valence(lines), 3),
        "energy": round(energy(profile_summary, bpm), 3),
        "bright": round(brightness(profile_summary), 3),
        "known": known,
    }
