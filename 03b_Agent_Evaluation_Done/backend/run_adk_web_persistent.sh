#!/bin/bash

# ADK Web UI with Persistent Session Storage
# This script fixes the 404 error when viewing evaluation results
# by using SQLite database for session persistence

echo "🚀 Starting ADK Web UI with persistent session storage..."

# Create sessions directory if it doesn't exist
SESSIONS_DIR="$HOME/.adk/sessions"
# SESSIONS_DIR="../../.adk_sessions"                 # local_application_eval/.adk_sessions/
mkdir -p "$SESSIONS_DIR"

# SQLite database file for session persistence
# DB_FILE="$SESSIONS_DIR/adk_web_sessions.db"
DB_FILE="$SESSIONS_DIR/adk_web_sessions.db"    # local_application_eval/.adk_sessions/adk_web_sessions.db
SESSION_URI="sqlite:///$DB_FILE"

echo "🗄️ Session database: $DB_FILE"
echo "📡 Session URI: $SESSION_URI"

# Start ADK Web UI with persistent sessions
echo "🌐 Starting ADK Web UI on http://localhost:8080..."
echo "📊 Evaluation results will now persist across requests!"

adk web \
    --session_service_uri="$SESSION_URI" \
    --host=127.0.0.1 \
    --port=8080 \
    --log_level=info \
    --reload \
    .

echo "🛑 ADK Web UI stopped"
