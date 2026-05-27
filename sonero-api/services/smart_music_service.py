import math
import random
from datetime import datetime, timedelta
from sqlalchemy.orm import Session
from sqlalchemy import func
from models import Track, User, ListeningHistory, FocusSession

# Weights for dynamic affinity match score
W1_GENRE_AFFINITY = 0.4
W2_BPM_MATCH = 0.4
W3_BURNOUT = 0.2

def calculate_focus_score(db: Session, session_id: int) -> float:
    """
    Computes the Focus Score (EF) for a given session using the formula:
    EF = (Tiempo de escucha sin interrupción / Tiempo total de la sesión) * Promedio de Instrumentalness de las canciones reproducidas.
    """
    session = db.query(FocusSession).filter(FocusSession.id == session_id).first()
    if not session:
        return 0.0

    # Retrieve listening history entries during this focus session
    # Using ended_at or current time if it hasn't ended
    end_time = session.ended_at or datetime.utcnow()
    history = db.query(ListeningHistory).filter(
        ListeningHistory.user_id == session.user_id,
        ListeningHistory.listened_at >= session.started_at,
        ListeningHistory.listened_at <= end_time
    ).all()

    if not history:
        return 0.0

    # Calculate listening duration without interruptions (non-skipped tracks)
    uninterrupted_time = sum(lh.duration_played for lh in history if not lh.skipped)
    
    # Session duration
    session_duration = (end_time - session.started_at).total_seconds()
    total_played_time = sum(lh.duration_played for lh in history)
    
    # We use the maximum of session duration and total played time as denominator to be safe
    total_session_time = max(session_duration, total_played_time)
    
    if total_session_time <= 0:
        ratio = 0.0
    else:
        ratio = min(1.0, uninterrupted_time / total_session_time)

    # Compute average instrumentalness of played tracks
    instrumentalness_values = [lh.track.instrumentalness for lh in history if lh.track]
    avg_instrumentalness = sum(instrumentalness_values) / len(instrumentalness_values) if instrumentalness_values else 0.0

    # Focus score calculation
    focus_score = ratio * avg_instrumentalness
    return round(focus_score, 4)


def get_optimal_bpm_range(db: Session, user_id: int) -> dict:
    """
    Analyzes historical Focus Sessions to determine the optimal BPM range with the lowest skip rate.
    Compares Baroque/Lo-Fi (60-90 BPM) vs. Techno/Deep House (120-140 BPM).
    """
    # Fetch all listening history of the user during completed focus sessions
    sessions = db.query(FocusSession).filter(
        FocusSession.user_id == user_id,
        FocusSession.ended_at.isnot(None)
    ).all()

    history_items = []
    for s in sessions:
        items = db.query(ListeningHistory).filter(
            ListeningHistory.user_id == user_id,
            ListeningHistory.listened_at >= s.started_at,
            ListeningHistory.listened_at <= s.ended_at
        ).all()
        history_items.extend(items)

    # Group listening histories by BPM ranges
    baroque_plays = [lh for lh in history_items if lh.track and 60 <= lh.track.bpm <= 90]
    techno_plays = [lh for lh in history_items if lh.track and 120 <= lh.track.bpm <= 140]

    # Calculate skip rates
    baroque_skips = [lh for lh in baroque_plays if lh.skipped]
    techno_skips = [lh for lh in techno_plays if lh.skipped]

    baroque_rate = len(baroque_skips) / len(baroque_plays) if baroque_plays else None
    techno_rate = len(techno_skips) / len(techno_plays) if techno_plays else None

    # Determine optimal range (default to Baroque/Lo-Fi 60-90 BPM)
    optimal_range = [60.0, 90.0]
    range_name = "Barroco/Lo-Fi (60-90 BPM)"

    if baroque_rate is not None and techno_rate is not None:
        if techno_rate < baroque_rate:
            optimal_range = [120.0, 140.0]
            range_name = "Techno/Deep House (120-140 BPM)"
    elif techno_rate is not None and baroque_rate is None:
        optimal_range = [120.0, 140.0]
        range_name = "Techno/Deep House (120-140 BPM)"

    return {
        "optimal_range": optimal_range,
        "range_name": range_name,
        "baroque_skip_rate": round(baroque_rate, 4) if baroque_rate is not None else None,
        "techno_skip_rate": round(techno_rate, 4) if techno_rate is not None else None,
    }


def get_current_mood_ea(db: Session, user_id: int) -> dict:
    """
    Calculates the user's current mood based on Russell's Circumplex Model of Affect.
    Computes a time-decay weighted average of valence and energy for the last 45 minutes of listening history.
    """
    now = datetime.utcnow()
    time_limit = now - timedelta(minutes=45)

    history = db.query(ListeningHistory).filter(
        ListeningHistory.user_id == user_id,
        ListeningHistory.listened_at >= time_limit
    ).all()

    if not history:
        # Default fallback if there's no recent playback
        return {
            "valence": 0.5,
            "energy": 0.5,
            "quadrant": "Calma/Relajado",
            "description": "Baja Energía, Alta Valencia (Fallback)"
        }

    total_weight = 0.0
    weighted_valence = 0.0
    weighted_energy = 0.0

    for lh in history:
        if not lh.track:
            continue
        
        # Calculate time difference in minutes
        age_minutes = (now - lh.listened_at).total_seconds() / 60.0
        
        # Linear weight decay: 1.0 at 0 minutes ago, 0.0 at 45 minutes ago
        weight = max(0.0, 1.0 - (age_minutes / 45.0))
        
        # Weight can also be scaled by how long they actually listened
        # (e.g. listening to a full song carries more weight than skipping)
        if lh.skipped:
            weight *= 0.2
            
        total_weight += weight
        weighted_valence += lh.track.valence * weight
        weighted_energy += lh.track.energy * weight

    if total_weight <= 0:
        avg_valence = 0.5
        avg_energy = 0.5
    else:
        avg_valence = max(0.0, min(1.0, weighted_valence / total_weight))
        avg_energy = max(0.0, min(1.0, weighted_energy / total_weight))

    # Map to quadrants
    if avg_energy >= 0.5:
        if avg_valence >= 0.5:
            quadrant = "Alta Energía, Alta Valencia"
            description = "Estresado" if avg_valence < 0.5 else "Feliz/Enérgico" # just sanity mapping
            description = "Feliz/Enérgico"
        else:
            quadrant = "Alta Energía, Baja Valencia"
            description = "Estresado/Frustrado"
    else:
        if avg_valence >= 0.5:
            quadrant = "Baja Energía, Alta Valencia"
            description = "Calma/Relajado"
        else:
            quadrant = "Baja Energía, Baja Valencia"
            description = "Triste/Aburrido"

    return {
        "valence": round(avg_valence, 4),
        "energy": round(avg_energy, 4),
        "quadrant": quadrant,
        "description": description
    }


def get_iso_principle_queue(db: Session, user_id: int) -> list[dict]:
    """
    Emotional Equalization (Iso-Principle):
    Starts with the user's current mood (assumed "Stressed" i.e. High Energy, Low Valence).
    Generates a transition queue of 5 songs, where each song gradually:
    - Reduces energy by 10% from the previous step.
    - Increases valence by 5% (+0.05 absolute) from the previous step.
    Aims towards "Calm" (Low Energy, High Valence).
    """
    mood = get_current_mood_ea(db, user_id)
    current_energy = mood["energy"]
    current_valence = mood["valence"]

    # If the user is already calm, or if we want a transition from a stressed state,
    # we initialize the transition curve based on the current state.
    # We retrieve all tracks to match
    tracks = db.query(Track).all()
    if not tracks:
        return []

    queue = []
    used_ids = set()

    for i in range(1, 6):
        # Target formula:
        target_energy = max(0.0, current_energy * (0.9 ** i))
        target_valence = min(1.0, current_valence + (0.05 * i))

        # Find closest track based on Euclidean distance in (valence, energy) space
        best_track = None
        min_distance = float('inf')

        for t in tracks:
            if t.id in used_ids:
                continue
            
            dist = math.sqrt((t.valence - target_valence) ** 2 + (t.energy - target_energy) ** 2)
            if dist < min_distance:
                min_distance = dist
                best_track = t

        if best_track:
            used_ids.add(best_track.id)
            queue.append({
                "step": i,
                "target_energy": round(target_energy, 4),
                "target_valence": round(target_valence, 4),
                "track": {
                    "id": best_track.id,
                    "title": best_track.title,
                    "artist": best_track.artist,
                    "bpm": best_track.bpm,
                    "valence": best_track.valence,
                    "energy": best_track.energy,
                    "instrumentalness": best_track.instrumentalness,
                    "genre": best_track.genre
                },
                "distance": round(min_distance, 4)
            })
        else:
            # Fallback if there aren't enough tracks
            break

    return queue


def get_song_burnout(db: Session, track_id: int) -> float:
    """
    Calculates Song Burnout (FC):
    FC = (Plays in last 7 days) / (Skips in last 7 days + 1)
    """
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    
    plays = db.query(ListeningHistory).filter(
        ListeningHistory.track_id == track_id,
        ListeningHistory.listened_at >= seven_days_ago
    ).count()

    skips = db.query(ListeningHistory).filter(
        ListeningHistory.track_id == track_id,
        ListeningHistory.listened_at >= seven_days_ago,
        ListeningHistory.skipped == True
    ).count()

    fc = plays / (skips + 1)
    return round(fc, 4)


def get_user_genre_affinity(db: Session, user_id: int) -> dict[str, float]:
    """
    Calculates user genre affinity based on completed plays.
    Returns a dictionary mapping genre to completion ratio.
    """
    completed_history = db.query(ListeningHistory).filter(
        ListeningHistory.user_id == user_id,
        ListeningHistory.completed == True
    ).all()

    if not completed_history:
        return {}

    genre_counts = {}
    total_completed = 0

    for lh in completed_history:
        if lh.track and lh.track.genre:
            genre = lh.track.genre.strip().lower()
            genre_counts[genre] = genre_counts.get(genre, 0) + 1
            total_completed += 1

    affinity = {}
    if total_completed > 0:
        for g, count in genre_counts.items():
            affinity[g] = count / total_completed

    return affinity


def calculate_match_score(track: Track, ideal_bpm: float, genre_affinity: dict[str, float], burnout: float) -> float:
    """
    Match Score formula:
    Match = (w1 * Afinidad Histórica al género) + (w2 * Coincidencia con Contexto/BPM ideal) - (w3 * FC)
    """
    # 1. Genre Affinity
    genre_key = track.genre.strip().lower() if track.genre else ""
    affinity = genre_affinity.get(genre_key, 0.0)

    # 2. BPM Match (normalized score between 0.0 and 1.0)
    bpm_diff = abs(track.bpm - ideal_bpm)
    # A difference of 100 or more gives a 0.0 match score
    bpm_match = max(0.0, 1.0 - (bpm_diff / 100.0))

    # Match calculation
    score = (W1_GENRE_AFFINITY * affinity) + (W2_BPM_MATCH * bpm_match) - (W3_BURNOUT * burnout)
    return round(score, 4)


def generate_dynamic_queue(
    db: Session, 
    user_id: int, 
    ideal_bpm: float, 
    queue_size: int = 10, 
    burnout_threshold: float = 5.0
) -> list[dict]:
    """
    Generates a dynamic playback queue using Explore vs. Exploit logic (85% Exploit, 15% Explore).
    - Blocks songs with FC (Burnout) > threshold.
    - Exploit: Picks top Match Score songs from the user's listening profile.
    - Explore: Picks tracks with similar BPM/Valence/Energy profiles, discovered by other users but new to this user.
    """
    # 1. Fetch user genre affinities
    genre_affinity = get_user_genre_affinity(db, user_id)

    # 2. Get list of all tracks
    all_tracks = db.query(Track).all()
    if not all_tracks:
        return []

    # 3. Compute FC and Match Scores for candidate pool
    candidates = []
    for t in all_tracks:
        fc = get_song_burnout(db, t.id)
        if fc > burnout_threshold:
            # Block burned-out track
            continue
        
        match_score = calculate_match_score(t, ideal_bpm, genre_affinity, fc)
        candidates.append({
            "track": t,
            "fc": fc,
            "match_score": match_score
        })

    # Sort candidates by match score descending
    candidates.sort(key=lambda x: x["match_score"], reverse=True)

    # Calculate Exploit vs Explore sizes
    num_exploit = max(1, round(queue_size * 0.85))
    num_explore = max(0, queue_size - num_exploit)

    # Determine tracks the user has already listened to
    user_listened = db.query(ListeningHistory.track_id).filter(
        ListeningHistory.user_id == user_id
    ).distinct().all()
    user_listened_ids = {t[0] for t in user_listened}

    # Gather Exploit tracks: top match scores
    exploit_pool = [c for c in candidates]
    exploit_tracks = exploit_pool[:num_exploit]

    # Gather Explore tracks:
    # "Canciones aleatorias con atributos similares descubiertas recientemente por otros usuarios"
    # Which current user has NEVER listened to.
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    
    other_user_plays = db.query(ListeningHistory.track_id).filter(
        ListeningHistory.user_id != user_id,
        ListeningHistory.listened_at >= seven_days_ago
    ).distinct().all()
    other_user_track_ids = [t[0] for t in other_user_plays]

    explore_candidates_ids = [tid for tid in other_user_track_ids if tid not in user_listened_ids]

    explore_pool = []
    # Fallback to any tracks in the database that the user has not listened to
    if not explore_candidates_ids:
        explore_candidates_ids = [t.id for t in all_tracks if t.id not in user_listened_ids]

    # If user has listened to everything, fallback to any tracks in DB
    if not explore_candidates_ids:
        explore_candidates_ids = [t.id for t in all_tracks]

    # Calculate proximity score of explore candidates to ideal BPM
    for c in candidates:
        if c["track"].id in explore_candidates_ids:
            # Add small random variation to simulate discovery
            score_with_noise = c["match_score"] + random.uniform(-0.1, 0.1)
            explore_pool.append({
                "track": c["track"],
                "fc": c["fc"],
                "match_score": c["match_score"],
                "score_with_noise": score_with_noise
            })

    # Sort explore pool by noise-modified scores to ensure randomness and attributes matching
    explore_pool.sort(key=lambda x: x.get("score_with_noise", x["match_score"]), reverse=True)
    explore_tracks = explore_pool[:num_explore]

    # Assemble the final playlist queue
    final_queue = []
    for et in exploit_tracks:
        final_queue.append({
            "type": "Exploit",
            "match_score": et["match_score"],
            "fc": et["fc"],
            "track": {
                "id": et["track"].id,
                "title": et["track"].title,
                "artist": et["track"].artist,
                "bpm": et["track"].bpm,
                "valence": et["track"].valence,
                "energy": et["track"].energy,
                "instrumentalness": et["track"].instrumentalness,
                "genre": et["track"].genre
            }
        })

    for et in explore_tracks:
        final_queue.append({
            "type": "Explore",
            "match_score": et["match_score"],
            "fc": et["fc"],
            "track": {
                "id": et["track"].id,
                "title": et["track"].title,
                "artist": et["track"].artist,
                "bpm": et["track"].bpm,
                "valence": et["track"].valence,
                "energy": et["track"].energy,
                "instrumentalness": et["track"].instrumentalness,
                "genre": et["track"].genre
            }
        })

    return final_queue


def get_focus_history_query(db: Session, user_id: str, seven_days_ago: datetime):
    """
    Returns a query for ListeningHistory records that occurred during completed focus sessions
    in the last 7 days for the given user.
    """
    return db.query(ListeningHistory).join(
        FocusSession,
        (FocusSession.user_id == ListeningHistory.user_id) &
        (ListeningHistory.listened_at >= FocusSession.started_at) &
        (ListeningHistory.listened_at <= FocusSession.ended_at)
    ).filter(
        ListeningHistory.user_id == user_id,
        ListeningHistory.listened_at >= seven_days_ago,
        FocusSession.ended_at.isnot(None)
    )


def get_top_focus_tracks(db: Session, user_id: str, limit: int = 3) -> list[dict]:
    """
    Finds top tracks played during focus sessions in the last 7 days that have the highest completion rate.
    """
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    focus_history = get_focus_history_query(db, user_id, seven_days_ago).all()
    
    if not focus_history:
        return []
        
    track_stats = {}
    for lh in focus_history:
        if not lh.track:
            continue
        tid = lh.track.id
        if tid not in track_stats:
            track_stats[tid] = {
                "title": lh.track.title,
                "artist": lh.track.artist,
                "plays": 0,
                "completions": 0,
                "duration_played": 0.0
            }
        track_stats[tid]["plays"] += 1
        if lh.completed:
            track_stats[tid]["completions"] += 1
        track_stats[tid]["duration_played"] += lh.duration_played

    sorted_tracks = []
    for tid, stats in track_stats.items():
        if stats["completions"] == 0:
            continue
        comp_rate = stats["completions"] / stats["plays"]
        sorted_tracks.append({
            "id": tid,
            "title": stats["title"],
            "artist": stats["artist"],
            "plays": stats["plays"],
            "completions": stats["completions"],
            "completion_rate": round(comp_rate, 4),
            "total_duration_minutes": round(stats["duration_played"] / 60.0, 2)
        })
        
    # Sort by completion rate descending, and then by total plays descending
    sorted_tracks.sort(key=lambda x: (x["completion_rate"], x["plays"]), reverse=True)
    return sorted_tracks[:limit]


def get_top_distractor_tracks(db: Session, user_id: str, limit: int = 3) -> list[dict]:
    """
    Finds top tracks skipped during focus sessions in the last 7 days.
    """
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    focus_history = get_focus_history_query(db, user_id, seven_days_ago).all()
    
    if not focus_history:
        return []
        
    track_stats = {}
    for lh in focus_history:
        if not lh.track:
            continue
        tid = lh.track.id
        if tid not in track_stats:
            track_stats[tid] = {
                "title": lh.track.title,
                "artist": lh.track.artist,
                "plays": 0,
                "skips": 0,
                "total_skip_time": 0.0
            }
        track_stats[tid]["plays"] += 1
        if lh.skipped:
            track_stats[tid]["skips"] += 1
            track_stats[tid]["total_skip_time"] += (lh.skip_time or 0.0)

    sorted_tracks = []
    for tid, stats in track_stats.items():
        if stats["skips"] == 0:
            continue
        skip_rate = stats["skips"] / stats["plays"]
        avg_skip_time = stats["total_skip_time"] / stats["skips"]
        sorted_tracks.append({
            "id": tid,
            "title": stats["title"],
            "artist": stats["artist"],
            "plays": stats["plays"],
            "skips": stats["skips"],
            "skip_rate": round(skip_rate, 4),
            "avg_skip_time_seconds": round(avg_skip_time, 1)
        })
        
    # Sort by skip rate descending, and then by early skips (low avg skip time)
    sorted_tracks.sort(key=lambda x: (x["skip_rate"], x["skips"]), reverse=True)
    return sorted_tracks[:limit]


def get_temporal_focus_profile(db: Session, user_id: str) -> dict:
    """
    Groups completed focus sessions of the last 7 days by time of day:
    Morning (6am-12pm), Afternoon (12pm-6pm), Evening/Night (6pm-6am).
    """
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    sessions = db.query(FocusSession).filter(
        FocusSession.user_id == user_id,
        FocusSession.started_at >= seven_days_ago,
        FocusSession.ended_at.isnot(None)
    ).all()
    
    profile = {
        "morning": {"sessions": 0, "avg_focus_score": 0.0, "total_skips": 0, "total_duration_minutes": 0.0},
        "afternoon": {"sessions": 0, "avg_focus_score": 0.0, "total_skips": 0, "total_duration_minutes": 0.0},
        "evening_night": {"sessions": 0, "avg_focus_score": 0.0, "total_skips": 0, "total_duration_minutes": 0.0}
    }
    
    temp_scores = {"morning": [], "afternoon": [], "evening_night": []}
    
    for s in sessions:
        hour = s.started_at.hour
        duration = (s.ended_at - s.started_at).total_seconds() / 60.0
        
        if 6 <= hour < 12:
            key = "morning"
        elif 12 <= hour < 18:
            key = "afternoon"
        else:
            key = "evening_night"
            
        profile[key]["sessions"] += 1
        profile[key]["total_skips"] += (s.total_skips if s.total_skips is not None else 0)
        profile[key]["total_duration_minutes"] += duration
        focus_score = s.focus_score if s.focus_score is not None else 0.0
        temp_scores[key].append(focus_score)
        
    for key in profile:
        scores = temp_scores[key]
        profile[key]["avg_focus_score"] = round(sum(scores) / len(scores), 4) if scores else 0.0
        profile[key]["total_duration_minutes"] = round(profile[key]["total_duration_minutes"], 1)
        
    return profile


def get_genre_focus_correlation(db: Session, user_id: str) -> list[dict]:
    """
    Groups track playbacks during focus sessions in the last 7 days by genre.
    """
    seven_days_ago = datetime.utcnow() - timedelta(days=7)
    focus_history = get_focus_history_query(db, user_id, seven_days_ago).all()
    
    if not focus_history:
        return []
        
    genre_stats = {}
    for lh in focus_history:
        if not lh.track or not lh.track.genre:
            continue
        genre = lh.track.genre.strip().lower()
        if genre not in genre_stats:
            genre_stats[genre] = {
                "plays": 0,
                "completions": 0,
                "skips": 0
            }
        genre_stats[genre]["plays"] += 1
        if lh.completed:
            genre_stats[genre]["completions"] += 1
        if lh.skipped:
            genre_stats[genre]["skips"] += 1
            
    correlation = []
    for g, stats in genre_stats.items():
        comp_rate = stats["completions"] / stats["plays"]
        skip_rate = stats["skips"] / stats["plays"]
        correlation.append({
            "genre": g,
            "plays": stats["plays"],
            "completion_rate": round(comp_rate, 4),
            "skip_rate": round(skip_rate, 4)
        })
        
    correlation.sort(key=lambda x: x["completion_rate"], reverse=True)
    return correlation
