import json
import logging
import httpx
from sqlalchemy.orm import Session
from models import SystemSetting

logger = logging.getLogger("sonero-smart-gemini")

def _get_gemini_api_key(db: Session) -> str | None:
    """Retrieves the Gemini API key from the system settings table in the database."""
    try:
        record = db.query(SystemSetting).filter(SystemSetting.key == "gemini_api_key").first()
        return record.value if record else None
    except Exception as e:
        logger.error(f"Error fetching Gemini API key from DB: {e}")
        return None

async def parse_natural_language_context(user_prompt: str, db: Session) -> dict:
    """
    Sends the user's natural language prompt describing their context or mood to the Gemini API
    to extract recommended ranges for BPM, energy, valence, and instrumental preference.
    Falls back to a keyword-matching heuristic parser if offline or if no API key is set.
    """
    api_key = _get_gemini_api_key(db)
    
    if not api_key:
        logger.info("No Gemini API key found in DB. Using offline heuristic parser.")
        return _parse_context_offline_fallback(user_prompt)

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"
    
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

    prompt = f"System Instruction: {system_instruction}\n\nUser Prompt: {user_prompt}"

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt}
                ]
            }
        ],
        "generationConfig": {
            "responseMimeType": "application/json"
        }
    }

    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload)
            if response.status_code == 200:
                data = response.json()
                text = data["contents"][0]["parts"][0]["text"].strip()
                # Clean up any markdown blocks if Gemini accidentally returned them
                if text.startswith("```json"):
                    text = text[7:]
                if text.endswith("```"):
                    text = text[:-3]
                text = text.strip()
                
                parsed_json = json.loads(text)
                # Verify schema
                if all(k in parsed_json for k in ["bpm_range", "energy_range", "valence_range", "instrumental"]):
                    return parsed_json
                else:
                    logger.warning("Gemini JSON response missing schema fields. Falling back.")
            else:
                logger.error(f"Gemini API returned status code {response.status_code}: {response.text}")
    except Exception as e:
        logger.error(f"Failed to query Gemini API: {e}")

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
    Sends aggregated user focus session data to Gemini to generate a weekly report.
    Instructs Gemini to write a Markdown report with psychological insights and actionable tips.
    Falls back to a local template engine if offline or if no API key is set.
    """
    api_key = _get_gemini_api_key(db)
    
    if not api_key:
        logger.info("No Gemini API key found in DB. Using local template report generator.")
        return _generate_report_offline_fallback(user_data_summary)

    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={api_key}"
    
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

    prompt = f"System Instruction: {system_instruction}\n\nUser Data Summary: {json.dumps(user_data_summary)}"

    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt}
                ]
            }
        ]
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(url, json=payload)
            if response.status_code == 200:
                data = response.json()
                text = data["contents"][0]["parts"][0]["text"].strip()
                return text
            else:
                logger.error(f"Gemini API returned status code {response.status_code}: {response.text}")
    except Exception as e:
        logger.error(f"Failed to query Gemini API for report: {e}")

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
