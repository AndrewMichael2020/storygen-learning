# -*- coding: utf-8 -*-
"""
New StoryGen Backend - Using Agent-Based Architecture
This version uses the new story_image_agent with full ADK agent capabilities
"""
import os
import json
import asyncio
import logging
from pathlib import Path
from dotenv import load_dotenv

from google.genai.types import Content, Part
from google.adk.runners import InMemoryRunner
from google.adk.sessions.in_memory_session_service import InMemorySessionService

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from story_agent.agent import root_agent as story_agent
from story_image_agent.agent import root_agent as image_agent  # New image agent

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Application constants
APP_NAME = "storygen_new_app"

# Initialize FastAPI app
app = FastAPI(title="StoryGen Backend (New)", description="ADK-powered story generation with agent-based image generation")

# Add CORS middleware to allow frontend connections
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex="https?://.*(localhost|run\.app)(:\d+)?|https?://.*\.run\.app",  # Allow localhost and all Cloud Run domains
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],  # Next.js default ports
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize session service and agents
project_id = os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GOOGLE_CLOUD_PROJECT_ID")

# Initialize agent runners
story_runner = None
image_runner = None

if project_id:
    try:
        # Initialize story agent runner (existing)
        story_runner = InMemoryRunner(app_name=APP_NAME, agent=story_agent)

        # Initialize new image agent runner
        image_runner = InMemoryRunner(app_name=APP_NAME, agent=image_agent)

        print("✅ New Architecture initialized: StoryAgent + CustomImageAgent")
        print(f"🎨 Custom Image Agent ready for direct tool execution")
    except Exception as e:
        print(f"⚠️ Warning: Could not initialize agents: {e}")
        print("📖 Story generation may not work properly")
else:
    print("💡 To enable image generation, set GOOGLE_CLOUD_PROJECT_ID in your .env file")


async def run_new_agent_workflow(websocket: WebSocket, user_id: str, keywords: str):
    """
    New agent-based workflow:
    1. StoryAgent generates structured story with scene data
    2. New ImageAgent generates images for each scene using conversational AI
    3. Stream results to frontend as they're ready
    """
    logger.info(f"🚀 Starting new agent workflow for user {user_id} with keywords: '{keywords}'")

    if not story_runner or not image_runner:
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": "Agent runners not properly initialized"
        }))
        return

    # Step 1: Generate structured story using StoryAgent (same as before)
    story_data = None
    try:
        logger.info("📖 Generating story with StoryAgent...")
        story_session = await story_runner.session_service.create_session(
            app_name=APP_NAME,
            user_id=f"{user_id}_story"
        )
        story_content = Content(role="user", parts=[Part(text=f"Keywords: {keywords}")])

        story_response = ""
        async for event in story_runner.run_async(
            user_id=f"{user_id}_story",
            session_id=story_session.id,
            new_message=story_content
        ):
            if event.content and event.content.parts:
                for part in event.content.parts:
                    if part.text:
                        story_response += part.text

        # Parse the JSON response from StoryAgent
        try:
            # Clean the response - remove markdown code blocks if present
            cleaned_response = story_response.strip()
            if cleaned_response.startswith("```json"):
                cleaned_response = cleaned_response[7:]  # Remove ```json
            if cleaned_response.endswith("```"):
                cleaned_response = cleaned_response[:-3]  # Remove ```
            cleaned_response = cleaned_response.strip()

            story_data = json.loads(cleaned_response)
            logger.info(f"✅ Story generated successfully with {len(story_data.get('scenes', []))} scenes")

            # Reconstruct story text with scene markers for frontend compatibility
            scenes = story_data.get("scenes", [])
            if scenes:
                # Build story text with [SCENE X] markers that frontend expects
                story_with_markers = ""
                for scene in scenes:
                    scene_index = scene.get("index", 1)
                    scene_text = scene.get("text", "")
                    story_with_markers += f"[SCENE {scene_index}]\n{scene_text}\n\n"
                story_text = story_with_markers.strip()
            else:
                # Fallback to the raw story if no scenes
                story_text = story_data.get("story", "")

            await websocket.send_text(json.dumps({
                "type": "story_complete",
                "data": story_text
            }))
            logger.info(f"📤 Sent story text with scene markers to frontend ({len(story_text)} characters)")

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse story JSON: {e}")
            logger.error(f"Raw response: {story_response[:500]}...")
            raise Exception("Story agent returned invalid JSON format")

    except Exception as e:
        logger.error(f"Story generation failed for user {user_id}: {e}")
        await websocket.send_text(json.dumps({"type": "error", "message": f"Story generation failed: {e}"}))
        return

    # Step 2: Generate images using CustomImageAgent
    if story_data and story_data.get("scenes"):
        logger.info("🎨 Starting image generation with CustomImageAgent...")

        # Extract character descriptions from story data
        character_descriptions = {}
        if story_data.get("main_characters"):
            for character in story_data["main_characters"]:
                char_name = character.get("name", "")
                char_desc = character.get("description", "")
                if char_name and char_desc:
                    character_descriptions[char_name] = char_desc
            logger.info(f"📚 Found {len(character_descriptions)} main character(s): {', '.join(character_descriptions.keys())}")

        # Create image session
        image_session = await image_runner.session_service.create_session(
            app_name=APP_NAME,
            user_id=f"{user_id}_image"
        )

        for scene in story_data["scenes"]:
            scene_index = scene.get("index", 1) - 1  # Convert to 0-based index
            scene_description = scene.get("description", "")
            scene_title = scene.get("title", "Unknown")

            try:
                logger.info(f"🖼️ Generating image for scene {scene_index + 1}: {scene_title}")

                logger.info(f"📝 Processing scene description: {scene_description[:100]}...")
                logger.info(f"👥 Using character descriptions: {list(character_descriptions.keys())}")

                # Create content with all necessary data for CustomImageAgent
                prompt_data = {
                    "scene_title": scene_title,
                    "scene_description": scene_description,
                    "character_descriptions": character_descriptions
                }
                image_content = Content(role="user", parts=[Part(text=json.dumps(prompt_data))])

                # Process all events from the custom agent
                image_data_str = ""
                async for event in image_runner.run_async(
                    user_id=f"{user_id}_image",
                    session_id=image_session.id,
                    new_message=image_content
                ):
                    logger.info(f"📥 Event from CustomImageAgent: {event.author if hasattr(event, 'author') else 'unknown'}")
                    if event.content and event.content.parts:
                        for part in event.content.parts:
                            if part.text:
                                image_data_str += part.text

                # After the loop, parse the accumulated string
                if image_data_str:
                    try:
                        image_data = json.loads(image_data_str)
                        logger.info("✅ Parsed image result from agent event")
                    except json.JSONDecodeError:
                        logger.error("❌ Failed to parse image result from agent event")
                else:
                    logger.warning("⚠️ Agent did not yield any content in events")

                if image_data and image_data.get("images"):
                    for img_data in image_data["images"]:
                        image_payload = {
                            "index": scene_index,
                            "scene_title": scene_title,
                            "format": img_data.get("format", "png"),
                            "stored_in_bucket": img_data.get("stored_in_bucket", False)
                        }

                        # Include GCS URL if available
                        if img_data.get("gcs_url"):
                            image_payload["gcs_url"] = img_data["gcs_url"]
                            logger.info(f"✅ Generated image for scene {scene_index + 1} with GCS URL")

                        # Include base64 if available (for fallback)
                        if img_data.get("base64"):
                            image_payload["base64"] = img_data["base64"]

                        await websocket.send_text(json.dumps({
                            "type": "image_generated",
                            "data": image_payload
                        }))
                        logger.info(f"📤 Sent image for scene {scene_index + 1} to frontend")
                else:
                    raise Exception("Image agent did not return valid image data")

            except Exception as e:
                logger.error(f"Image generation failed for scene {scene_index + 1}: {e}")
                # Send error placeholder so frontend knows this slot exists
                error_payload = {
                    "index": scene_index,
                    "scene_title": scene_title,
                    "format": "png",
                    "stored_in_bucket": False,
                    "error": f"Image generation failed: {str(e)}",
                    "placeholder": True
                }
                await websocket.send_text(json.dumps({
                    "type": "image_generated",
                    "data": error_payload
                }))
                logger.info(f"📤 Sent error placeholder for scene {scene_index + 1}")

            # Small delay between images to avoid rate limiting
            if scene_index < len(story_data["scenes"]) - 1:
                await asyncio.sleep(2)

        logger.info("🎨 All image generation completed with New ImageAgent")
    else:
        logger.warning("⚠️ No scenes found in story data, skipping image generation")

    # Send completion notification
    await websocket.send_text(json.dumps({"type": "turn_complete", "turn_complete": True}))


@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    """
    WebSocket endpoint for real-time story generation using new agent architecture

    Args:
        websocket: WebSocket connection
        user_id: Unique user identifier
    """
    await websocket.accept()
    logger.info(f"Client #{user_id} connected to NEW backend")

    try:
        # Send connection confirmation
        await websocket.send_text(json.dumps({
            "type": "connected",
            "message": "Connected to StoryGen NEW backend (agent-based)"
        }))

        while True:
            # Receive message from client
            message_json = await websocket.receive_text()
            message = json.loads(message_json)

            message_type = message.get("type")
            data = message.get("data", "")

            if message_type == "generate_story":
                try:
                    # Send processing notification
                    await websocket.send_text(json.dumps({
                        "type": "processing",
                        "message": "Generating story and images with NEW agents..."
                    }))

                    # Run the new agent-based workflow
                    await run_new_agent_workflow(websocket, user_id, data)

                except Exception as e:
                    logger.error(f"Error in new websocket workflow for user {user_id}: {e}")
                    await websocket.send_text(json.dumps({
                        "type": "error",
                        "message": f"NEW workflow failed: {str(e)}"
                    }))

            elif message_type == "ping":
                # Handle ping/keepalive messages
                await websocket.send_text(json.dumps({"type": "pong"}))

            else:
                logger.warning(f"Unknown message type: {message_type}")

    except WebSocketDisconnect:
        logger.info(f"Client #{user_id} disconnected from NEW backend")
    except Exception as e:
        logger.error(f"WebSocket error for user {user_id} on NEW backend: {e}")
        try:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": f"NEW server error: {str(e)}"
            }))
        except:
            pass
    finally:
        logger.info(f"Client #{user_id} connection closed on NEW backend")

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "storygen-backend-new",
        "architecture": "agent-based"
    }

# @app.get("/")
# async def root():
#     """Root endpoint"""
#     return {
#         "message": "StoryGen Backend API (NEW)",
#         "version": "3.0.0",
#         "workflow": "agent-based",
#         "agents": {
#             "story": "story_agent (existing)",
#             "image": "new_image_agent (with tools)"
#         }
#     }

# Serve frontend
STATIC_FILES_DIR = os.environ.get("STATIC_FILES_DIR", "../frontend/out")
try:
    app.mount("/", StaticFiles(directory=STATIC_FILES_DIR, html=True), name="static")
except RuntimeError:
    print("Frontend build not found. Run `npm run build` in the `frontend` directory.")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
