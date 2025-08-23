"""
Direct Image Agent that bypasses ADK function calling and uses ImagenTool directly
"""
import json
import re
from typing import Optional, Dict, Any
from story_agent.imagen_tool import ImagenTool


class DirectImageAgent:
    """
    A simplified agent that directly uses ImagenTool to generate images
    without relying on ADK's function calling mechanism.
    """
    
    def __init__(self, project_id: str = None):
        """
        Initialize the DirectImageAgent with ImagenTool
        
        Args:
            project_id: Google Cloud Project ID for image generation
        """
        self.project_id = project_id
        self.imagen_tool = None
        
        if project_id:
            try:
                self.imagen_tool = ImagenTool(project_id=project_id)
                print("✅ DirectImageAgent initialized with ImagenTool")
            except Exception as e:
                print(f"⚠️ Warning: Could not initialize ImagenTool: {e}")
                raise
        else:
            raise ValueError("Project ID is required for DirectImageAgent")
    
    async def generate_image_from_description(self, description: str, character_descriptions: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        """
        Generate an image from a scene description with consistent character appearances
        
        Args:
            description: Scene description for image generation (action and setting)
            character_descriptions: Dict mapping character names to their visual descriptions
            
        Returns:
            Dict containing the image generation results
        """
        if not self.imagen_tool:
            return {
                "success": False,
                "error": "ImagenTool not initialized"
            }
        
        # Create a prompt from the description and character info
        prompt = self._create_prompt_from_description(description, character_descriptions)
        
        try:
            # Use ImagenTool directly
            result_json = await self.imagen_tool.run(
                ctx=None,  # ImagenTool doesn't use context
                prompt=prompt,
                aspect_ratio="16:9",
                number_of_images=1
            )
            
            result = json.loads(result_json)
            return result
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Image generation failed: {str(e)}"
            }
    
    def _create_prompt_from_description(self, description: str, character_descriptions: Optional[Dict[str, str]] = None) -> str:
        """
        Transform a scene description into a proper image generation prompt with consistent characters
        
        Args:
            description: Scene description (action and setting)
            character_descriptions: Dict mapping character names to their visual descriptions
            
        Returns:
            Formatted prompt for image generation
        """
        # LOCKED STYLE - Same for every single image to ensure consistency
        locked_style = (
            "Children's book cartoon illustration with bright vibrant colors, "
            "simple shapes, friendly characters, clean compositions, "
            "appropriate for all ages, consistent character design and proportions"
        )
        
        # Clean up the description
        description = description.strip()
        if not description:
            description = "a cheerful scene"
        
        # Build the scene with character appearances
        scene_parts = []
        
        # Add the scene description first
        scene_parts.append(f"Scene: {description}")
        
        # Then add ALL character descriptions to ensure consistency
        # The AI will understand which characters to include based on the scene description
        if character_descriptions:
            character_details = []
            for name, char_desc in character_descriptions.items():
                character_details.append(f"{name} is {char_desc}")
            
            if character_details:
                scene_parts.append(f"Character reference guide: {'; '.join(character_details)}")
        
        # Combine everything with the locked style
        # Add explicit consistency instructions
        consistency_note = "IMPORTANT: Use the character reference guide to ensure characters look EXACTLY the same in every scene. Maintain consistent art style throughout all images."
        full_prompt = f"{locked_style} {' '.join(scene_parts)}. {consistency_note}"
        
        return full_prompt
