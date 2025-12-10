from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional, List
from app.services import gemini_service
from app.core.config import settings

router = APIRouter()

class GenerateTextRequest(BaseModel):
    prompt: str
    context: Optional[str] = None

class GenerateEventInsightRequest(BaseModel):
    event_data: dict
    insight_type: str = "general"

@router.post("/generate", response_model=dict)
async def generate_text(request: GenerateTextRequest):
    """
    Generate text using Gemini AI
    """
    try:
        if not settings.GEMINI_API_KEY:
             raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Gemini API is not configured"
            )
            
        response = await gemini_service.generate_text(request.prompt)
        return {"result": response}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )

@router.post("/insight", response_model=dict)
async def generate_event_insight(request: GenerateEventInsightRequest):
    """
    Generate insights for an event using Gemini AI
    """
    try:
        if not settings.GEMINI_API_KEY:
             raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Gemini API is not configured"
            )

        response = await gemini_service.generate_event_insight(
            request.event_data, 
            request.insight_type
        )
        return {"result": response}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )
