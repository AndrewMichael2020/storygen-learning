"""
ADK Configuration for persistent session storage by using DatabaseSessionService
"""

import os
import tempfile
from pathlib import Path
from google.adk.sessions import DatabaseSessionService, InMemorySessionService

def get_persistent_session_service():
    """
    Create a persistent session service using SQLite database
    This ensures evaluation sessions persist across Web UI requests
    """
    # Create a persistent database file in a temp directory
    db_dir = Path.home() / ".adk" / "sessions"
    db_dir.mkdir(parents=True, exist_ok=True)
    db_file = db_dir / "adk_web_sessions.db"
    
    # Use SQLite database URL
    db_url = f"sqlite:///{db_file}"
    
    print(f"🗄️ Using persistent session storage: {db_url}")
    
    try:
        session_service = DatabaseSessionService(db_url=db_url)
        print("✅ DatabaseSessionService initialized successfully")
        return session_service
    except Exception as e:
        print(f"⚠️ Failed to initialize DatabaseSessionService: {e}")
        print("🔄 Falling back to InMemorySessionService")
        return InMemorySessionService()

def get_session_service():
    """
    Get the appropriate session service based on environment
    """
    # Check if we should force persistent storage
    use_persistent = os.getenv("ADK_USE_PERSISTENT_SESSIONS", "true").lower() == "true"
    
    if use_persistent:
        return get_persistent_session_service()
    else:
        print("🧠 Using InMemorySessionService (sessions won't persist)")
        return InMemorySessionService()
