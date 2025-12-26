from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
import docker
import os
import shutil
import subprocess
import json
from typing import List, Optional
import asyncio
from pathlib import Path

app = FastAPI(title="Institutional Edge Orchestrator")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configuration
# PROJECT_ROOT: Ensure we use the path where the HOST project is mounted (/app/host_project)
PROJECT_ROOT = Path(os.environ.get("PROJECT_ROOT", "/app/host_project"))
# HOST_PROJECT_PATH: The actual path on the Windows Host (passed via env)
HOST_PROJECT_PATH = os.environ.get("HOST_PROJECT_PATH", ".")

# Orchestrator Directory (inside container)
ORCHESTRATOR_DIR = Path(__file__).resolve().parent.parent
FRONTEND_DIR = ORCHESTRATOR_DIR / "frontend"

print(f"DEBUG: ORCHESTRATOR_DIR={ORCHESTRATOR_DIR}")
print(f"DEBUG: FRONTEND_DIR={FRONTEND_DIR}")
print(f"DEBUG: Index exists? {(FRONTEND_DIR / 'index.html').exists()}")

INSTANCES_DIR = PROJECT_ROOT / "instances"
BLUEPRINT_DIR = PROJECT_ROOT 

START_PORT_WEB = 81
START_PORT_API = 8001
START_PORT_VNC = 3001
START_PORT_RPYC = 8003 

# Serve Frontend
app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")

class InstanceCreate(BaseModel):
    name: str
    mt5_login: Optional[str] = ""
    mt5_password: Optional[str] = ""
    mt5_server: Optional[str] = "HFMarketsGlobal-Demo"

class InstanceResponse(BaseModel):
    name: str
    status: str
    ports: dict
    urls: dict

def get_docker_client():
    return docker.from_env()

@app.get("/instances", response_model=List[InstanceResponse])
def list_instances():
    client = get_docker_client()
    instances = []
    
    if not INSTANCES_DIR.exists():
        return []
        
    for path in INSTANCES_DIR.iterdir():
        if not path.is_dir():
            continue
            
        instance_name = path.name
        container_name = f"institutional_backend_{instance_name}"
        status = "STOPPED"
        
        try:
            container = client.containers.get(container_name)
            status = container.status.upper()
        except docker.errors.NotFound:
            pass
            
        # Parse ports from .env if possible, for now simplify return
        instances.append({
            "name": instance_name,
            "status": status,
            "ports": {},
            "urls": {
                "dashboard": f"http://localhost:81", # Simplified dynamic check needed
                "vnc": f"http://localhost:3001"
            }
        })
    return instances

@app.get("/")
async def read_index():
    index_path = FRONTEND_DIR / "index.html"
    if not index_path.exists():
         return {"error": f"Index not found at {index_path}"}
    return FileResponse(index_path)

def get_next_ports():
    if not INSTANCES_DIR.exists():
        count = 0
    else:
        existing = [d for d in INSTANCES_DIR.iterdir() if d.is_dir()]
        count = len(existing)
    
    return {
        "web": START_PORT_WEB + count,
        "api": 8002 + (count * 2),
        "vnc": START_PORT_VNC + count,
        "rpyc": 8003 + (count * 2) 
    }

@app.post("/instances")
async def create_instance(item: InstanceCreate, background_tasks: BackgroundTasks):
    safe_name = "".join(c for c in item.name if c.isalnum() or c in ('_', '-')).lower()
    target_dir = INSTANCES_DIR / safe_name
    
    if target_dir.exists():
        # TODO: Handle existing but broken
        raise HTTPException(status_code=400, detail="Instance already exists")
    
    ports = get_next_ports()
    
    # 1. Create Directory Structure
    target_dir.mkdir(parents=True, exist_ok=True)
    
    # 2. Copy Blueprints
    # We must selective copy to avoid recursion or copying unwanted files
    def ignore_patterns(path, names):
        return ['instances', '.git', '__pycache__', 'node_modules', 'orchestrator', 'backend_data', 'mt5_config', 'sql_app.db']
    
    try:
        shutil.copytree(BLUEPRINT_DIR / "backend", target_dir / "backend", ignore=ignore_patterns)
        shutil.copytree(BLUEPRINT_DIR / "frontend", target_dir / "frontend", ignore=ignore_patterns)
        shutil.copy(BLUEPRINT_DIR / "docker-compose.yml", target_dir / "docker-compose.yml")
    except Exception as e:
        # Cleanup if copy fails
        shutil.rmtree(target_dir)
        raise HTTPException(status_code=500, detail=f"Failed to copy blueprint: {str(e)}")

    # 3. Generate .env
    # Construct Windows path for volumes
    instance_host_path = f"{HOST_PROJECT_PATH}\\instances\\{safe_name}"
    env_content = f"""
APP_NAME="Institutional Edge {safe_name}"
DEBUG=True
SECRET_KEY=secret-{safe_name}
HOST=0.0.0.0
PORT=8000

MT5_LOGIN={item.mt5_login or ""}
MT5_PASSWORD={item.mt5_password or ""}
MT5_SERVER={item.mt5_server or "HFMarketsGlobal-Demo"}
MT5_PATH=C:\\Program Files\\MetaTrader 5\\terminal64.exe

WEB_PORT={ports['web']}
API_PORT={ports['api']}
VNC_PORT={ports['vnc']}
RPYC_PORT={ports['rpyc']}
INSTANCE_NAME={safe_name}

CORS_ORIGINS=*
DATABASE_URL=sqlite:///./sql_app.db
PROJECT_ROOT_HOST={instance_host_path}
JWT_SECRET_KEY=jwt-{safe_name}-secret
"""
    
    (target_dir / ".env").write_text(env_content)
    # Backend needs .env too usually
    (target_dir / "backend" / ".env").write_text(env_content)
    
    # Frontend needs VITE_API_URL for the build (Use .env.production for higher priority)
    frontend_env = f"VITE_API_URL=http://localhost:{ports['api']}\n"
    (target_dir / "frontend" / ".env").write_text(frontend_env)
    
    # 4. Start Instance
    background_tasks.add_task(start_instance_task, target_dir, safe_name)
    
    return {"status": "deploying", "name": safe_name, "ports": ports}

def start_instance_task(target_dir, name):
    print(f"DEBUG: Starting instance {name} in {target_dir}")
    # Docker Compose Up
    try:
        # Check if file exists
        if not (target_dir / "docker-compose.yml").exists():
            print(f"ERROR: docker-compose.yml not found in {target_dir}")
            return

        # Build incrementally (allow cache) - much faster
        print(f"DEBUG: Starting with --build (cached)...")
        # Combine build and up in one command for efficiency
        # 'up --build -d' ensures images are built if missing or changed, but uses cache
        result = subprocess.run(
            ["docker-compose", "up", "-d", "--build"], 
            cwd=target_dir, capture_output=True, text=True
        )
        print(f"DEBUG: docker-compose up stdout: {result.stdout}")
        print(f"DEBUG: docker-compose up stderr: {result.stderr}")
        
        if result.returncode != 0:
             print(f"ERROR: docker-compose up failed with code {result.returncode}")
        print(f"DEBUG: docker-compose up stdout: {result.stdout}")
        print(f"DEBUG: docker-compose up stderr: {result.stderr}")
        if result.returncode != 0:
             print(f"ERROR: docker-compose up failed with code {result.returncode}")
    except Exception as e:
        print(f"Error starting {name}: {e}")

@app.post("/instances/{name}/start")
def start_instance(name: str, background_tasks: BackgroundTasks):
    target_dir = INSTANCES_DIR / name
    print(f"DEBUG: Request to start '{name}'")
    print(f"DEBUG: Checking path '{target_dir}'")
    print(f"DEBUG: Exists? {target_dir.exists()}")
    if not target_dir.exists():
        print(f"DEBUG: Directory content of {INSTANCES_DIR}: {[p.name for p in INSTANCES_DIR.iterdir()]}")
        raise HTTPException(404, f"Instance directory '{name}' not found at {target_dir}")
    background_tasks.add_task(start_instance_task, target_dir, name)
    return {"status": "starting"}

@app.post("/instances/{name}/stop")
def stop_instance(name: str):
    target_dir = INSTANCES_DIR / name
    if not target_dir.exists():
        raise HTTPException(404, "Not found")
    subprocess.run(["docker-compose", "down"], cwd=target_dir)
    return {"status": "stopped"}

@app.post("/instances/{name}/delete")
def delete_instance(name: str):
    target_dir = INSTANCES_DIR / name
    if not target_dir.exists():
        raise HTTPException(404, "Not found")
    subprocess.run(["docker-compose", "down", "-v"], cwd=target_dir)
    shutil.rmtree(target_dir)
    return {"status": "deleted"}
