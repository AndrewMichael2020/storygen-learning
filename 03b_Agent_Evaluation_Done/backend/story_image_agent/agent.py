"""
Custom ADK Image Generation Agent for StoryGen
Uses BaseAgent pattern for full control over tool execution
"""
import os
import json
import logging
from typing import AsyncGenerator
from google.adk.agents import BaseAgent
from google.adk.events.event import Event
from google.adk.agents.invocation_context import InvocationContext
from story_image_agent.imagen_tool import ImagenTool
from google.genai.types import Content, Part

logger = logging.getLogger(__name__)

# Initialize the ImagenTool
project_id = os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GOOGLE_CLOUD_PROJECT_ID")

if not project_id:
    print("⚠️ Warning: No Google Cloud Project ID found. Set GOOGLE_CLOUD_PROJECT_ID in your .env file")
    imagen_tool = None
else:
    try:
        imagen_tool = ImagenTool(project_id=project_id)
        print("✅ ImagenTool initialized for Custom Image Agent")
    except Exception as e:
        print(f"⚠️ Warning: Could not initialize ImagenTool: {e}")
        imagen_tool = None


class CustomImageAgent(BaseAgent):
    """
    Custom agent for image generation using direct tool execution.
    This bypasses the LLM agent limitations and directly calls the ImagenTool.
    """
    
    # Pydantic field declarations
    imagen_tool: ImagenTool = None
    
    model_config = {"arbitrary_types_allowed": True}
    
    def __init__(self, name: str = "story_image_agent"):
        """Initialize the CustomImageAgent"""
        super().__init__(
            name=name,
            imagen_tool=imagen_tool,
            sub_agents=[]  # No sub-agents needed
        )
        self.imagen_tool = imagen_tool
    
    async def _run_async_impl(self, ctx: InvocationContext) -> AsyncGenerator[Event, None]:
        """
        Core implementation that directly calls the ImagenTool for every request.
        """
        if not self.imagen_tool:
            logger.error(f"[{self.name}] ImagenTool not available")
            # Store error in session state
            ctx.session.state["image_result"] = json.dumps({
                "success": False,
                "error": "ImagenTool not initialized"
            })
            # Must yield at least once for async generator
            yield Event(author=self.name, content=None)
            return
        
        # Get the user's request from the invocation context's user_content
        user_message = ""
        if ctx.user_content and ctx.user_content.parts:
            for part in ctx.user_content.parts:
                if part.text:
                    user_message += part.text
        
        # Try to parse as JSON first (if coming from main_new.py)
        scene_description = ""
        character_descriptions = {}
        
        try:
            if user_message.startswith("{"):
                prompt_data = json.loads(user_message)
                scene_description = prompt_data.get("scene_description", "")
                character_descriptions = prompt_data.get("character_descriptions", {})
            else:
                # Fallback to using the message as scene description
                scene_description = user_message
        except json.JSONDecodeError:
            # If not JSON, treat as plain text description
            scene_description = user_message
        
        if not scene_description:
            logger.error(f"[{self.name}] No scene description provided in message: {user_message[:100]}")
            # Store error in session state
            ctx.session.state["image_result"] = json.dumps({
                "success": False,
                "error": "No scene description provided"
            })
            # Must yield at least once for async generator
            yield Event(author=self.name, content=None)
            return
        
        logger.info(f"[{self.name}] Generating image for: {scene_description[:100]}...")
        
        # Build the prompt for ImagenTool
        style_prefix = "Children's book cartoon illustration with bright vibrant colors, simple shapes, friendly characters."
        
        # Include character descriptions for consistency
        if character_descriptions:
            char_details = []
            for name, desc in character_descriptions.items():
                char_details.append(f"{name} is {desc}")
            char_context = " Character descriptions: " + "; ".join(char_details)
        else:
            char_context = ""
        
        full_prompt = f"{style_prefix} Scene: {scene_description}.{char_context}"
        
        try:
            # Call the ImagenTool directly
            result_json = await self.imagen_tool.run(
                ctx=None,  # ImagenTool doesn't use context
                prompt=full_prompt,
                aspect_ratio="16:9",
                number_of_images=1
            )
            
            logger.info(f"[{self.name}] ImagenTool returned: {result_json[:200]}...")
            
            # Store the result in session state for main.py to access
            ctx.session.state["image_result"] = result_json
            
            logger.info(f"[{self.name}] ✅ Image generation completed successfully")
            
            # Yield an event to indicate completion, including the result json
            yield Event(
                author=self.name,
                content=Content(parts=[Part(text=result_json)])
            )
            
        except Exception as e:
            error_result = json.dumps({
                "success": False,
                "error": f"Image generation failed: {str(e)}"
            })
            
            logger.error(f"[{self.name}] Image generation failed: {e}")
            
            # Store error result
            ctx.session.state["image_result"] = error_result
            
            # Yield an event to indicate completion (even for errors)
            yield Event(
                author=self.name,
                content=Content(parts=[Part(text=error_result)])
            )


# Create the root agent instance
root_agent = CustomImageAgent(name="story_image_agent")

print("🎨 Custom Image Generation Agent initialized with direct tool control")
