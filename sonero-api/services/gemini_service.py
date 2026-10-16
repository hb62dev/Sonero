import os
import json
import logging
import httpx
from datetime import datetime, timedelta
from fastapi import BackgroundTasks
from sqlalchemy.orm import Session
from sqlalchemy import func
from models import SystemSetting, PlaybackEvent, Media, SongRating

logger = logging.getLogger("sonero-smart-gemini")

def _get_gemini_api_key(db: Session) -> str | None:
    """Retrieves the Gemini API key from the database settings table or environment."""
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == "gemini_api_key").first()
        if record and record.value and record.value.strip():
            return record.value.strip()
    except Exception as e:
        logger.error(f"Error fetching Gemini API key from DB: {e}")
    
    env_key = os.environ.get("GEMINI_API_KEY")
    if env_key and env_key.strip():
        return env_key.strip()
    return None

def _get_claude_api_key(db: Session) -> str | None:
    """Retrieves the Claude / Anthropic API key from DB or environment."""
    try:
        record = db.query(SystemSetting).filter(
            (SystemSetting.key == "claude_api_key") | (SystemSetting.key == "anthropic_api_key")
        ).first()
        if record and record.value and record.value.strip():
            return record.value.strip()
    except Exception as e:
        logger.error(f"Error fetching Claude API key from DB: {e}")

    env_key = os.environ.get("ANTHROPIC_API_KEY") or os.environ.get("CLAUDE_API_KEY")
    if env_key and env_key.strip():
        return env_key.strip()
    return None

def _get_ai_provider(db: Session) -> str:
    """Returns preferred AI provider: 'gemini' or 'claude' (default: 'gemini')."""
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == "ai_provider").first()
        if record and record.value and record.value.strip().lower() in ("claude", "anthropic"):
            return "claude"
    except Exception as e:
        logger.error(f"Error fetching AI provider from DB: {e}")
    return "gemini"

def _clean_json_text(raw_text: str) -> str:
    """Strips markdown code fence wrappers from JSON output."""
    t = raw_text.strip()
    if t.startswith("```json"):
        t = t[7:]
    elif t.startswith("```"):
        t = t[3:]
    if t.endswith("```"):
        t = t[:-3]
    return t.strip()

def _get_claude_models(db: Session | None = None) -> list[str]:
    """Returns available Claude models ordered by priority (custom model first if set)."""
    custom = None
    if db:
        try:
            rec = db.query(SystemSetting).filter(SystemSetting.key == "claude_model").first()
            if rec and rec.value and rec.value.strip():
                custom = rec.value.strip()
        except Exception:
            pass
    if not custom:
        custom = os.environ.get("CLAUDE_MODEL") or os.environ.get("ANTHROPIC_MODEL")

    defaults = [
        "claude-haiku-5-5",
        "claude-sonnet-5-5",
        "claude-fable-5-1",
        "claude-opus-5-5",
        "claude-haiku-4-5",
        "claude-sonnet-4-6",
        "claude-3-7-sonnet",
        "claude-3-5-haiku-20241022",
        "claude-3-5-sonnet-20241022",
    ]
    if custom and custom.strip():
        c = custom.strip()
        return [c] + [m for m in defaults if m != c]
    return defaults


def _get_gemini_models(db: Session | None = None) -> list[str]:
    """Returns available Gemini models ordered by priority (custom model first if set)."""
    custom = None
    if db:
        try:
            rec = db.query(SystemSetting).filter(SystemSetting.key == "gemini_model").first()
            if rec and rec.value and rec.value.strip():
                custom = rec.value.strip()
        except Exception:
            pass
    if not custom:
        custom = os.environ.get("GEMINI_MODEL")

    defaults = [
        "gemini-3.8-flash",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-3-flash",
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-1.5-flash",
    ]
    if custom and custom.strip():
        c = custom.strip()
        return [c] + [m for m in defaults if m != c]
    return defaults


async def _call_claude_api(api_key: str, system_instruction: str, prompt: str, json_mode: bool = True, models: list[str] | None = None) -> str | None:
    """Calls Anthropic Claude API with model fallback."""
    url = "https://api.anthropic.com/v1/messages"
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    system_text = system_instruction
    if json_mode:
        system_text += "\n\nResponde ÚNICAMENTE con código JSON válido. Sin markdown ni texto explicativo."

    target_models = models or _get_claude_models()
    async with httpx.AsyncClient(timeout=35.0) as client:
        for model in target_models:
            payload = {
                "model": model,
                "max_tokens": 4096,
                "system": system_text,
                "messages": [{"role": "user", "content": prompt}]
            }
            try:
                response = await client.post(url, headers=headers, json=payload)
                if response.status_code == 200:
                    data = response.json()
                    content = data.get("content", [])
                    if content:
                        text_blocks = [c.get("text", "") for c in content if c.get("type") == "text"]
                        raw = "".join(text_blocks).strip()
                        if raw:
                            logger.info(f"Respuesta de Claude recibida exitosamente con {model}")
                            return raw
                else:
                    logger.warning(f"Claude {model} retornó código {response.status_code}: {response.text[:200]}")
            except Exception as e:
                logger.warning(f"Error llamando a Claude {model}: {e}")
    return None

async def _call_gemini_api(api_key: str, system_instruction: str, prompt: str, json_mode: bool = True, models: list[str] | None = None) -> str | None:
    """Calls Google Gemini API with fallback across current and flash models."""
    target_models = models or _get_gemini_models()
    payload = {
        "contents": [{"parts": [{"text": f"System Instruction: {system_instruction}\n\n{prompt}"}]}],
    }
    if json_mode:
        payload["generationConfig"] = {"responseMimeType": "application/json"}

    async with httpx.AsyncClient(timeout=35.0) as client:
        for model in target_models:
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
            try:
                response = await client.post(url, json=payload)
                if response.status_code == 200:
                    data = response.json()
                    candidates = data.get("candidates") or data.get("contents")
                    if candidates:
                        parts = candidates[0].get("content", {}).get("parts", [])
                        if not parts and "parts" in candidates[0]:
                            parts = candidates[0]["parts"]
                        if parts:
                            raw = parts[0].get("text", "").strip()
                            if raw:
                                logger.info(f"Respuesta de Gemini recibida exitosamente con {model}")
                                return raw
                else:
                    logger.warning(f"Gemini {model} retornó código {response.status_code}: {response.text[:200]}")
            except Exception as e:
                logger.warning(f"Error llamando a Gemini {model}: {e}")
    return None

async def query_ai(db: Session, system_instruction: str, prompt: str, json_mode: bool = True) -> tuple[str | None, str]:
    """
    Unified AI query function for Sonero.
    Supports both Anthropic Claude and Google Gemini with automatic cross-fallback!
    Returns (raw_text_response, provider_label).
    """
    preferred = _get_ai_provider(db)
    claude_key = _get_claude_api_key(db)
    gemini_key = _get_gemini_api_key(db)

    attempts = []
    if preferred == "claude":
        if claude_key:
            attempts.append(("claude", claude_key))
        if gemini_key:
            attempts.append(("gemini", gemini_key))
    else:
        if gemini_key:
            attempts.append(("gemini", gemini_key))
        if claude_key:
            attempts.append(("claude", claude_key))

    for provider, key in attempts:
        if provider == "claude":
            models = _get_claude_models(db)
            res = await _call_claude_api(key, system_instruction, prompt, json_mode=json_mode, models=models)
            if res:
                return res, "Claude AI"
        elif provider == "gemini":
            models = _get_gemini_models(db)
            res = await _call_gemini_api(key, system_instruction, prompt, json_mode=json_mode, models=models)
            if res:
                return res, "Gemini AI"

    return None, "None"

async def parse_natural_language_context(user_prompt: str, db: Session) -> dict:
    """
    Sends the user's natural language prompt describing their context or mood to the AI (Gemini / Claude)
    to extract recommended ranges for BPM, energy, valence, and instrumental preference.
    Falls back to a keyword-matching heuristic parser if offline or if no API key is set.
    """
    system_instruction = (
        "You are an expert music metadata and recommendation parser. "
        "Analyze the user's prompt describing their situation, activity, mood, or context, "
        "and return recommended music attributes. "
        "You MUST respond ONLY with a valid JSON object matching the following structure:\n"
        "{\n"
        "  \"bpm_range\": [min_bpm, max_bpm],\n"
        "  \"energy_range\": [min_energy, max_energy],\n"
        "  \"valence_range\": [min_valence, max_valence],\n"
        "  \"instrumental\": boolean\n"
        "}\n"
        "Do not include any Markdown wrap, code blocks, or explanatory text. Output raw JSON only."
    )

    raw_text, _ = await query_ai(db, system_instruction, user_prompt, json_mode=True)
    if raw_text:
        try:
            parsed = json.loads(_clean_json_text(raw_text))
            if all(k in parsed for k in ["bpm_range", "energy_range", "valence_range", "instrumental"]):
                return parsed
        except Exception as e:
            logger.warning(f"Error parsing mood JSON from AI: {e}")

    # Fallback if request failed or JSON was invalid
    return _parse_context_offline_fallback(user_prompt)


def _parse_context_offline_fallback(prompt: str) -> dict:
    """
    Offline heuristic parser using regex/keywords.
    Acts as a fail-safe fallback when Gemini API is offline or key is missing.
    """
    p = prompt.lower()
    
    # Default settings
    bpm_range = [70.0, 110.0]
    energy_range = [0.3, 0.7]
    valence_range = [0.4, 0.7]
    instrumental = False

    # Focus keywords
    focus_words = ["concentra", "focus", "estudia", "study", "program", "code", "work", "trabaj", "analit", "oficina"]
    is_focus = any(w in p for w in focus_words)
    
    # Chill/Slow tempo keywords
    slow_words = ["lofi", "lo-fi", "chill", "relax", "calma", "dormir", "sleep", "slow", "lento", "baja", "paz", "tranqui"]
    is_slow = any(w in p for w in slow_words)

    # Fast/Energy keywords
    fast_words = ["techno", "house", "dance", "ejercicio", "workout", "correr", "run", "energ", "fast", "rapido", "gimnasio", "gym"]
    is_fast = any(w in p for w in fast_words)

    # Mood valence keywords
    sad_words = ["triste", "sad", "frustra", "estresa", "stress", "ansia", "mal", "aburri", "bored"]
    is_sad = any(w in p for w in sad_words)

    happy_words = ["feliz", "happy", "contento", "alegre", "bien", "fiesta", "party", "motiva"]
    is_happy = any(w in p for w in happy_words)

    # Apply heuristics
    if is_focus:
        instrumental = True
        bpm_range = [60.0, 90.0]  # Baroque/Lo-Fi default for focus
        energy_range = [0.2, 0.5]
        valence_range = [0.5, 0.8]

    if is_slow:
        bpm_range = [60.0, 90.0]
        energy_range = [0.1, 0.4]
        valence_range = [0.5, 0.8]

    if is_fast:
        bpm_range = [120.0, 140.0]
        energy_range = [0.7, 1.0]
        valence_range = [0.6, 0.9]

    if is_sad:
        valence_range = [0.0, 0.4]
        energy_range = [0.1, 0.4]

    if is_happy:
        valence_range = [0.6, 1.0]
        energy_range = [0.5, 0.9]

    # Special handling for focus & fast tempo
    if is_focus and is_fast:
        bpm_range = [120.0, 140.0]
        energy_range = [0.6, 0.8]
        instrumental = True

    return {
        "bpm_range": bpm_range,
        "energy_range": energy_range,
        "valence_range": valence_range,
        "instrumental": instrumental,
        "_fallback": True  # Flag to indicate fallback was used
    }


async def generate_weekly_productivity_report(user_data_summary: dict, db: Session) -> str:
    """
    Sends aggregated user focus session data to the AI (Gemini / Claude) to generate a weekly report.
    Instructs the AI to write a Markdown report with psychological insights and actionable tips.
    Falls back to a local template engine if offline or if no API key is set.
    """
    system_instruction = (
        "You are an expert music psychologist and productivity coach. "
        "Your task is to analyze the user's weekly listening history, focus sessions, and track-specific interactions, "
        "and generate a highly personalized diagnostic report in Markdown format. "
        "You are provided with a structured user data summary containing:\n"
        "- High-level stats (Focus score, sessions, skip rate)\n"
        "- Top Focus Enablers: specific tracks with highest completion rate during focus sessions\n"
        "- Top Distractors: specific tracks skipped very early during focus sessions\n"
        "- Temporal Focus Profile: focus score and skip rate breakdown by morning, afternoon, and evening/night\n"
        "- Genre Focus Correlation: how different music genres correspond to completion rates\n\n"
        "Your report MUST contain the following sections:\n"
        "1. ## 📊 Resumen de Rendimiento Semanal: Aggregated metrics analysis in a structured markdown table.\n"
        "2. ## 🎧 Diagnóstico de Canciones (Facilitadores vs. Distractores): Specifically mention their top enabler and distractor tracks by name/artist. Diagnose if they have song burnout (FC) or cognitive interruptions due to vocal tracks.\n"
        "3. ## ⏰ Patrones Horarios de Concentración: Analyze how their focus scores vary between morning, afternoon, and evening. Note cognitive fatigue dip times.\n"
        "4. ## 🎵 Correlación de Género: Identify which music styles (e.g. ambient, lofi, classical) yield the best focus performance vs. which ones are causing distraction.\n"
        "5. ## 🚀 Plan de Acción Personalizado: Clear, bulleted, actionable tips for next week (optimal BPM targets, handling track burnout, structuring playlist transitions using the Iso-Principle).\n\n"
        "Tone must be motivating, empathetic, professional, and science-backed. Use headers, bold text, lists, and tables. "
        "Do not wrap the response in markdown code blocks (e.g., do not start with ```markdown). Output raw Markdown directly."
    )

    prompt = f"User Data Summary: {json.dumps(user_data_summary)}"
    raw_text, _ = await query_ai(db, system_instruction, prompt, json_mode=False)
    if raw_text and len(raw_text.strip()) > 50:
        return raw_text.strip()

    # Fallback to offline report
    return _generate_report_offline_fallback(user_data_summary)


def _generate_report_offline_fallback(summary: dict) -> str:
    """
    Generates a structured Markdown report locally using template interpolation.
    Acts as a fail-safe fallback when Gemini API is offline or key is missing.
    """
    avg_focus = summary.get("avg_focus_score", 0.0)
    total_sessions = summary.get("total_sessions", 0)
    total_skips = summary.get("total_skips", 0)
    optimal_bpm = summary.get("optimal_bpm_range", [60, 90])
    skip_rate = summary.get("skip_rate", 0.0)
    dominant_mood = summary.get("dominant_mood", "Calma/Relajado")
    
    bpm_str = f"{int(optimal_bpm[0])}-{int(optimal_bpm[1])} BPM"
    
    # New metrics fallbacks
    top_enablers = summary.get("top_focus_tracks", [])
    top_distractors = summary.get("top_distractor_tracks", [])
    temporal = summary.get("temporal_profile", {})
    genres = summary.get("genre_focus_correlation", [])
    
    # 1. Enablers block
    enablers_text = ""
    if top_enablers:
        for t in top_enablers:
            enablers_text += f"* **{t['title']}** - {t['artist']} (Escuchas: {t['plays']}, Tasa de completado: {t['completion_rate'] * 100:.1f}%)\n"
    else:
        enablers_text = "*No hay suficientes datos de canciones de enfoque esta semana.*"

    # 2. Distractors block
    distractors_text = ""
    if top_distractors:
        for t in top_distractors:
            distractors_text += f"* **{t['title']}** - {t['artist']} (Skips: {t['skips']}, Saltada promedio a los {t['avg_skip_time_seconds']} seg)\n"
    else:
        distractors_text = "*No hay suficientes datos de canciones distractoras esta semana.*"

    # 3. Temporal block table
    temporal_rows = ""
    for k in ["morning", "afternoon", "evening_night"]:
        name = "Mañana (06:00-12:00)" if k == "morning" else "Tarde (12:00-18:00)" if k == "afternoon" else "Noche (18:00-06:00)"
        data = temporal.get(k, {"sessions": 0, "avg_focus_score": 0.0, "total_skips": 0})
        temporal_rows += f"| {name} | {data['sessions']} | {data['avg_focus_score']:.2f} | {data['total_skips']} skips |\n"

    # 4. Genre block table
    genre_rows = ""
    if genres:
        for g in genres[:3]:
            genre_rows += f"| {g['genre'].capitalize()} | {g['plays']} | {g['completion_rate'] * 100:.1f}% | {g['skip_rate'] * 100:.1f}% |\n"
    else:
        genre_rows = "| Sin datos | 0 | 0% | 0% |\n"

    report = f"""# Reporte Semanal de Productividad Musical (Modo Offline)

¡Hola! Hemos procesado tus métricas de consumo musical e índices de concentración durante la última semana. Aquí tienes tu análisis heurístico personalizado.

## 📊 Resumen de Rendimiento Semanal

| Métrica | Valor | Estado / Tendencia |
| :--- | :--- | :--- |
| **Focus Score Promedio** | {avg_focus:.2f} / 1.00 | {'Excelente' if avg_focus >= 0.7 else 'Firme' if avg_focus >= 0.4 else 'Mejorable'} |
| **Sesiones Completadas** | {total_sessions} sesiones | Buen ritmo de trabajo |
| **Interrupciones (Skips)** | {total_skips} skips | { 'Bajo' if total_skips < 5 else 'Moderado' if total_skips < 15 else 'Frecuente' } |
| **Tasa de Descarte (Skip Rate)** | {skip_rate * 100:.1f}% | {'Flujo óptimo' if skip_rate < 0.15 else 'Búsqueda constante' if skip_rate < 0.35 else 'Alta distracción'} |
| **Tempo Óptimo Determinado** | {bpm_str} | Priorizar para enfoque |

---

## 🎧 Diagnóstico de Canciones (Facilitadores vs. Distractores)

### 🟢 Tus principales Facilitadores de Enfoque:
{enablers_text}
*Estas canciones ayudan a tu cerebro a mantener una velocidad de procesamiento estable en el neocórtex, disminuyendo la fatiga auditiva.*

### 🔴 Canciones que interrumpieron tu Concentración:
{distractors_text}
*Se recomienda remover estas pistas de tus listas de reproducción de estudio o trabajo. Al ser saltadas temprano, rompen el foco y fuerzan al cerebro a reorientar la atención.*

---

## ⏰ Patrones Horarios de Concentración

Evaluación de tu rendimiento según el bloque del día:

| Franja Horaria | Sesiones | Focus Score Promedio | Skips Totales |
| :--- | :---: | :---: | :---: |
{temporal_rows}
*Nota: Los picos de desconcentración suelen concentrarse en horarios de la tarde debido al cansancio acumulado.*

---

## 🎵 Correlación de Género

| Género | Reproducciones | Tasa de Completado | Tasa de Descarte (Skip) |
| :--- | :---: | :---: | :---: |
{genre_rows}
*Los géneros con altas tasas de completado fomentan estados de flujo pasivo y concentración de largo plazo.*

---

## 🚀 Plan de Acción Personalizado

* **Inicia tus Bloques con Tempo Barroco/Lo-Fi**: Programa tus primeras 3 canciones de sesión en el rango de {bpm_str} e instrumentales para acelerar la entrada en el estado de flujo.
* **Depuración de Playlists**: Remueve proactivamente las canciones distractoras de tus listas de enfoque, en particular las que tengan una alta tasa de descarte en los primeros 30 segundos.
* **Ajuste de Bloque de Enfoque**: Si tu Focus Score en la tarde es inferior a 0.40, introduce pausas activas de 5 minutos de silencio o una transición gradual (Iso-Principio) de música relajante para restablecer la atención.

---
*Nota: Este informe ha sido redactado por el motor de análisis local fuera de línea al no detectarse una clave API de Gemini válida en el sistema.*
"""
    return report


# ── Creative AI Curation Engine (Activity-driven & Manual) ────────────────────

async def curate_ai_mixes(db: Session, force: bool = False) -> dict:
    """
    Curates creative, non-templated playlists using Gemini based on the user's
    real activity, listening patterns, time of day, and ratings.
    """
    from services.mixes import save_mix

    if not _get_gemini_api_key(db) and not _get_claude_api_key(db):
        return {
            "success": False,
            "message": "Configura tu API Key de Gemini o Claude en Ajustes para generar playlists con IA.",
            "mixes": []
        }

    # 1. User ratings (likes and dislikes)
    ratings = db.query(SongRating).all()
    liked_songs = [f"{r.title} - {r.artist}" for r in ratings if r.rating == 1 and r.title]
    disliked_songs = [f"{r.title} - {r.artist}" for r in ratings if r.rating == -1 and r.title]
    disliked_artists = list(set([r.artist.strip() for r in ratings if r.rating == -1 and r.artist]))

    # 2. Recent playback activity (last 14 days, especially recent sessions)
    now = datetime.utcnow()
    recent_cutoff = now - timedelta(days=14)
    recent_events = (
        db.query(PlaybackEvent, Media)
        .join(Media, PlaybackEvent.media_id == Media.id)
        .filter(PlaybackEvent.start_time >= recent_cutoff)
        .order_by(PlaybackEvent.start_time.desc())
        .limit(80)
        .all()
    )

    completed_tracks = []
    skipped_tracks = []
    for evt, media in recent_events:
        entry = f"{media.title} (Artista: {media.artist or 'Desconocido'}, Género: {media.genre or 'General'})"
        if evt.completed or (evt.duration_watched and evt.duration_watched > 45):
            completed_tracks.append(entry)
        else:
            skipped_tracks.append(entry)

    completed_sample = list(dict.fromkeys(completed_tracks))[:20]
    skipped_sample = list(dict.fromkeys(skipped_tracks))[:15]

    current_hour = now.hour
    time_label = "Madrugada" if current_hour < 6 else "Mañana" if current_hour < 12 else "Tarde" if current_hour < 19 else "Noche"

    # 3. Available local library candidate songs
    all_media = db.query(Media).filter(Media.type == "music").order_by(func.random()).limit(80).all()
    library_candidates = [
        {"media_id": m.id, "title": m.title, "artist": m.artist or "Desconocido", "genre": m.genre or ""}
        for m in all_media
    ]

    user_context = {
        "momento_actual": f"{time_label} (Hora local aproximada: {current_hour}:00)",
        "canciones_escuchadas_completas_recientes": completed_sample,
        "canciones_saltadas_recientes": skipped_sample,
        "canciones_con_me_gusta": liked_songs[:15],
        "canciones_con_no_me_gusta_PROHIBIDAS": disliked_songs[:20],
        "artistas_descartados_PROHIBIDOS": disliked_artists[:10],
        "candidatos_biblioteca_local": library_candidates,
    }

    system_instruction = (
        "Eres el DJ y Curador Musical de Inteligencia Artificial exclusivo de Sonero.\n"
        "Tu misión es diseñar recomendaciones de playlists ÚNICAS, FRESCAS y LIBRES, sin ningún esquema prefabricado.\n\n"
        "REGLAS OBLIGATORIAS:\n"
        "1. PROHIBIDO usar títulos o conceptos genéricos o prefabricados como 'Mix Diario', 'Tus Favoritas', 'Mix de Mañana'. "
        "Inventa nombres creativos, conceptuales y atractivos para cada lista (por ejemplo: 'Inmersión Nocturna de Código', "
        "'Fiebre de Baterías y Distorsión', 'Caminata Urbana Relajada', 'Rarezas Ocultas de tu Colección').\n"
        "2. En el campo 'reason', explica al usuario la razón auténtica y personalizada por la que creaste esta lista basándote "
        "en su actividad real (por ejemplo: 'Notamos que hoy escuchaste varias canciones instrumentales seguidas sin saltar ninguna; "
        "esta lista amplía esa concentración con temas de ritmo similar').\n"
        "3. PROHIBICIÓN ESTRICTA: NUNCA incluyas ninguna canción o artista que figure en 'canciones_con_no_me_gusta_PROHIBIDAS' "
        "o 'artistas_descartados_PROHIBIDOS'.\n"
        "4. En cada lista incluye entre 6 y 15 canciones. Para cada canción, usa preferentemente un 'media_id' de "
        "'candidatos_biblioteca_local'. También puedes sugerir descubrimientos musicales nuevos poniendo 'title' y 'artist' "
        "para canciones afines que enriquezcan la lista.\n"
        "5. Devuelve entre 2 y 4 playlists bien diferenciadas en atmósfera y estilo.\n"
        "6. Responde EXCLUSIVAMENTE con un JSON válido sin markdown ni texto extra:\n"
        "{\n"
        "  \"mixes\": [\n"
        "    {\n"
        "      \"title\": \"Título creativo\",\n"
        "      \"description\": \"Descripción de 1 o 2 oraciones de la atmósfera\",\n"
        "      \"reason\": \"Por qué te la recomendamos hoy\",\n"
        "      \"items\": [\n"
        "        {\"media_id\": 1, \"note\": \"Motivo breve de selección\"},\n"
        "        {\"title\": \"Canción\", \"artist\": \"Artista\", \"note\": \"Descubrimiento nuevo\"}\n"
        "      ]\n"
        "    }\n"
        "  ]\n"
        "}"
    )

    prompt = f"Contexto del Usuario y Biblioteca:\n{json.dumps(user_context, ensure_ascii=False)}"

    raw_text, provider_label = await query_ai(db, system_instruction, prompt, json_mode=True)
    if not raw_text:
        logger.error("No se pudo obtener respuesta de la IA (Gemini / Claude).")
        return {
            "success": False,
            "message": "No se pudo generar la recomendación con la IA en este momento. Revisa tu conexión y clave API de Gemini o Claude.",
            "mixes": []
        }

    try:
        clean_text = _clean_json_text(raw_text)
        parsed_json = json.loads(clean_text)
    except Exception as e:
        logger.error(f"Error parseando JSON de {provider_label}: {e}. Texto recibido: {raw_text[:300]}")
        return {
            "success": False,
            "message": f"Error al procesar la respuesta estructurada de {provider_label}.",
            "mixes": []
        }

    created_mixes = []
    for m in parsed_json.get("mixes", []):
        title = (m.get("title") or "").strip()
        items = m.get("items", [])
        if not title or not items:
            continue
        
        saved = save_mix(
            db,
            title=title,
            items=items,
            description=m.get("description"),
            reason=m.get("reason"),
            source="agent",
            author=provider_label,
            kind="ai_curated"
        )
        created_mixes.append({"id": saved.id, "title": saved.title, "count": len(saved.items)})

    play_setting = db.query(SystemSetting).filter(SystemSetting.key == "plays_since_last_curation").first()
    if not play_setting:
        play_setting = SystemSetting(key="plays_since_last_curation", value="0")
        db.add(play_setting)
    else:
        play_setting.value = "0"

    time_setting = db.query(SystemSetting).filter(SystemSetting.key == "last_ai_curation_timestamp").first()
    now_iso = datetime.utcnow().isoformat()
    if not time_setting:
        time_setting = SystemSetting(key="last_ai_curation_timestamp", value=now_iso)
        db.add(time_setting)
    else:
        time_setting.value = now_iso
    db.commit()

    return {
        "success": True,
        "count": len(created_mixes),
        "mixes": created_mixes,
        "message": f"Se crearon {len(created_mixes)} playlists personalizadas con IA."
    }


def check_activity_and_maybe_curate(db: Session, background_tasks: BackgroundTasks):
    """
    Checks user activity since last AI curation. If threshold is reached and
    cooldown has elapsed, schedules an AI curation in the background.
    Zero activity = Zero executions.
    """
    try:
        if not _get_gemini_api_key(db) and not _get_claude_api_key(db):
            return

        play_setting = db.query(SystemSetting).filter(SystemSetting.key == "plays_since_last_curation").first()
        if not play_setting:
            play_setting = SystemSetting(key="plays_since_last_curation", value="1")
            db.add(play_setting)
            current_plays = 1
        else:
            current_plays = int(play_setting.value or "0") + 1
            play_setting.value = str(current_plays)
        db.commit()

        MIN_PLAYS = 6
        COOLDOWN_MINUTES = 45

        if current_plays < MIN_PLAYS:
            return

        last_time_setting = db.query(SystemSetting).filter(SystemSetting.key == "last_ai_curation_timestamp").first()
        now = datetime.utcnow()
        if last_time_setting and last_time_setting.value:
            try:
                last_time = datetime.fromisoformat(last_time_setting.value)
                if (now - last_time) < timedelta(minutes=COOLDOWN_MINUTES):
                    return
            except Exception:
                pass

        play_setting.value = "0"
        if not last_time_setting:
            last_time_setting = SystemSetting(key="last_ai_curation_timestamp", value=now.isoformat())
            db.add(last_time_setting)
        else:
            last_time_setting.value = now.isoformat()
        db.commit()

        background_tasks.add_task(_run_background_curation)
        logger.info(f"Disparador de actividad de IA activado tras {current_plays} reproducciones.")
    except Exception as e:
        logger.error(f"Error checking activity for AI curation: {e}")


async def _run_background_curation():
    """Background worker for activity-driven curation."""
    from database import SessionLocal
    db = SessionLocal()
    try:
        await curate_ai_mixes(db, force=False)
    except Exception as e:
        logger.error(f"Error in background AI curation worker: {e}")
    finally:
        db.close()
