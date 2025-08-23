
import json
from typing import AsyncGenerator

from google.adk.agents import BaseAgent, Event, InvocationContext
from .imagen_tool import ImagenTool


class StoryImageAgent(BaseAgent):
    """A custom agent for generating images directly using ImagenTool."""

    name = "story_image_agent"

    def __init__(self, tool: ImagenTool | None = None) -> None:
        super().__init__()
        self.imagen_tool = tool or ImagenTool()

    async def _run_async_impl(
        self, ctx: InvocationContext
    ) -> AsyncGenerator[Event, None]:
        """Runs the image generation agent."""
        if not ctx.user_content or not ctx.user_content.parts:
            ctx.session.state["image_result"] = {
                "status": "error",
                "message": "No input provided.",
            }
            yield Event(
                type="result", data={"error": "No input provided for image generation."}
            )
            return

        user_message = ctx.user_content.parts[0].text
        try:
            # Handle JSON input
            input_data = json.loads(user_message)
            scene_description = input_data.get("scene_description", "")
            character_descriptions = input_data.get("character_descriptions", {})
        except json.JSONDecodeError:
            # Fallback to plain text
            scene_description = user_message
            character_descriptions = {}

        if not scene_description:
            ctx.session.state["image_result"] = {
                "status": "error",
                "message": "Scene description is missing.",
            }
            yield Event(
                type="result", data={"error": "Scene description is missing."}
            )
            return

        # Build the detailed prompt
        style_prefix = (
            "Outdoor climbing illustration in a casual realistic style with "
            "natural earthy colors, clear mountain and rock features, friendly "
            "climbers in proper gear, simple yet accurate compositions, and "
            "consistent proportions."
        )
        
        prompt = f"{style_prefix} {scene_description}"

        if character_descriptions:
            character_details = ". ".join(
                f"{name}: {desc}" for name, desc in character_descriptions.items()
            )
            prompt += f" Characters: {character_details}"

        try:
            # Directly execute the ImagenTool
            image_result = await self.imagen_tool.run(prompt=prompt)
            
            ctx.session.state["image_result"] = {
                "status": "success",
                "images": image_result,
            }
            yield Event(type="result", data={"image_urls": image_result})

        except Exception as e:
            error_message = f"Image generation failed: {e}"
            ctx.session.state["image_result"] = {
                "status": "error",
                "message": str(e),
            }
            yield Event(type="result", data={"error": error_message})
