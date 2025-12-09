"""
Google Gemini AI Service
Interact with Google Generative AI for text generation and insights.
"""

import google.generativeai as genai
import logging
from typing import List, Dict, Optional, Any
from app.core.config import settings

logger = logging.getLogger(__name__)

class GeminiService:
    """Service to interact with Google Gemini AI"""
    
    def __init__(self):
        self.api_key = settings.GEMINI_API_KEY
        self.model_name = settings.GEMINI_MODEL
        self._setup_client()
        
    def _setup_client(self):
        """Initialize the Gemini client if API key is available"""
        if self.api_key:
            try:
                genai.configure(api_key=self.api_key)
                self.model = genai.GenerativeModel(self.model_name)
                self.is_configured = True
                logger.info(f"Gemini AI configured with model: {self.model_name}")
            except Exception as e:
                logger.error(f"Failed to configure Gemini AI: {e}")
                self.is_configured = False
        else:
            logger.warning("GEMINI_API_KEY not found. Gemini service disabled.")
            self.is_configured = False

    async def generate_text(self, prompt: str, temperature: float = 0.7) -> Optional[str]:
        """
        Generate text response from Gemini
        
        Args:
            prompt: The input prompt
            temperature: Creativity/Randomness (0.0 to 1.0)
            
        Returns:
            Generated text or None if failed
        """
        if not self.is_configured:
            logger.warning("Attempted to use Gemini service but it's not configured.")
            return None
            
        try:
            # Note: Gemini Python client creates a synchronous call, but we can wrap it or treat it as blocking for now
            # For pure async, we'd use run_in_executor, but this is fine for basic integration
            response = self.model.generate_content(
                prompt,
                generation_config=genai.types.GenerationConfig(
                    temperature=temperature
                )
            )
            return response.text
        except Exception as e:
            logger.error(f"Gemini generation error: {e}")
            return None

    async def generate_event_insights(self, event_data: Dict) -> Optional[str]:
        """
        Generate insights for an event description or plan.
        
        Args:
            event_data: Dictionary containing event title, description, etc.
            
        Returns:
            Insight text
        """
        if not self.is_configured:
            return None
            
        prompt = f"""
        Analyze the following event details and provide 3 key insights or suggestions for improvement:
        
        Title: {event_data.get('title')}
        Description: {event_data.get('description')}
        Category: {event_data.get('category')}
        
        Focus on:
        1. Audience Engagement
        2. Clarity of Purpose
        3. Potential Reach
        """
        
        return await self.generate_text(prompt)

# Global instance
gemini_service = GeminiService()
