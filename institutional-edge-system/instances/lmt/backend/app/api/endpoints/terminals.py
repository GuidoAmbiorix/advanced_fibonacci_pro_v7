from fastapi import APIRouter, HTTPException, BackgroundTasks
from pydantic import BaseModel
from typing import List, Optional
from app.services.terminal_manager import TerminalManager

router = APIRouter()

class TerminalCloneRequest(BaseModel):
    source_path: str
    new_name: str

class TerminalResponse(BaseModel):
    name: str
    path: str
    exe_path: str

@router.get("/", response_model=List[TerminalResponse])
async def list_terminals():
    """
    List all detected MetaTrader 5 terminal installations on the server.
    """
    terminals = TerminalManager.detect_terminals()
    return terminals

@router.post("/clone")
async def clone_terminal(request: TerminalCloneRequest):
    """
    Clone an existing MT5 terminal to create a new instance.
    """
    result = TerminalManager.clone_terminal(request.source_path, request.new_name)
    
    if not result["success"]:
        raise HTTPException(status_code=400, detail=result["error"])
        
    return result

@router.post("/validate")
async def validate_terminal(path: str):
    """
    Check if a given path is a valid MT5 terminal.
    """
    is_valid = TerminalManager.validate_terminal_path(path)
    return {"valid": is_valid, "path": path}
