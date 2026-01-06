from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
import docker
import os
import httpx
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
    role: Optional[str] = "SOLO"
    # Phase 3: Enhanced Onboarding
    max_drawdown: Optional[float] = 10.0
    max_daily_loss: Optional[float] = 5.0
    symbol_suffix: Optional[str] = ""
    symbol_prefix: Optional[str] = ""
    account_type: Optional[str] = "DEMO" # DEMO, LIVE, PROP

class InstanceResponse(BaseModel):
    name: str
    status: str
    ports: dict
    urls: dict

def get_docker_client():
    return docker.from_env()

@app.get("/instances", response_model=List[InstanceResponse])
async def list_instances():
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
        ports = {}
        
        # Read .env for ports
        env_path = path / ".env"
        if env_path.exists():
            with open(env_path) as f:
                for line in f:
                    if "WEB_PORT=" in line:
                         ports['web'] = line.strip().split("=")[1]
                    if "VNC_PORT=" in line:
                         ports['vnc'] = line.strip().split("=")[1]
                    if "API_PORT=" in line:
                        ports['api'] = line.strip().split("=")[1]

        try:
            container = client.containers.get(container_name)
            if container.status == "running":
                status = "RUNNING"
                api_port = ports.get('api')
                if api_port:
                    try:
                        async with httpx.AsyncClient() as http_client:
                            # Use container name as hostname since we are on the same docker network (bot-net)
                            # Backend service always listens on 8000 internally
                            response = await http_client.get(f"http://{container_name}:8000/health", timeout=2)
                            if response.status_code == 200:
                                health_data = response.json()
                                if health_data.get("mt5_status") == "connected":
                                    status = "READY"
                                elif health_data.get("mt5_status") == "connecting":
                                    status = "INITIALIZING (Connecting to MT5...)"
                                elif health_data.get("mt5_status") == "disconnected":
                                    status = "MT5_DISCONNECTED"
                                else:
                                    status = "RUNNING (MT5 Status Unknown)"
                            else:
                                status = "RUNNING (API Unresponsive)"
                    except httpx.RequestError:
                        status = "RUNNING (API Unreachable)"
                    except json.JSONDecodeError:
                        status = "RUNNING (API Malformed Response)"
                else:
                    status = "RUNNING (API Port Missing)"
            else:
                status = container.status.upper()
        except docker.errors.NotFound:
            pass
            
        instances.append({
            "name": instance_name,
            "status": status,
            "ports": ports,
            "urls": {
                "dashboard": f"http://localhost:{ports.get('web', '80')}", 
                "vnc": f"http://localhost:{ports.get('vnc', '3000')}"
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
        
        # Use lightweight instance template (no MT5 - uses shared mt5_shared)
        # Read template and substitute placeholders
        template_path = Path("/app/instance-template.yml")
        with open(template_path, 'r') as f:
            template_content = f.read()
        
        # Substitute all placeholders
        instance_number = len([d for d in INSTANCES_DIR.iterdir() if d.is_dir()]) if INSTANCES_DIR.exists() else 1
        compose_content = template_content.replace("{INSTANCE_NAME}", safe_name)
        compose_content = compose_content.replace("{INSTANCE_NUMBER}", str(instance_number))
        compose_content = compose_content.replace("{API_PORT}", str(ports['api']))
        compose_content = compose_content.replace("{WEB_PORT}", str(ports['web']))
        compose_content = compose_content.replace("{MT5_LOGIN}", item.mt5_login or "")
        compose_content = compose_content.replace("{MT5_PASSWORD}", item.mt5_password or "")
        compose_content = compose_content.replace("{MT5_SERVER}", item.mt5_server or "HFMarketsGlobal-Demo")
        
        # Write substituted content
        with open(target_dir / "docker-compose.yml", 'w') as f:
            f.write(compose_content)
            
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
MT5_SYMBOL_SUFFIX={item.symbol_suffix or ""}
MT5_SYMBOL_PREFIX={item.symbol_prefix or ""}
MAX_DRAWDOWN_PERCENT={item.max_drawdown or 10.0}
MAX_DAILY_LOSS_PERCENT={item.max_daily_loss or 5.0}
ACCOUNT_TYPE={item.account_type or "DEMO"}
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
INSTANCE_ROLE={item.role or "SOLO"}

"""
    
    (target_dir / ".env").write_text(env_content)
    # Backend needs .env too usually
    (target_dir / "backend" / ".env").write_text(env_content)
    
    # Frontend needs VITE_API_URL for the build (Use .env.production for higher priority)
    frontend_env = f"VITE_API_URL=http://localhost:{ports['api']}\n"
    (target_dir / "frontend" / ".env").write_text(frontend_env)
    
    # NOTE: No MT5 config needed - using shared MT5 terminal (mt5_shared)
    
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


@app.post("/instances/{name}/restart")
def restart_instance(name: str, background_tasks: BackgroundTasks):
    """Stop then start an instance"""
    target_dir = INSTANCES_DIR / name
    if not target_dir.exists():
        raise HTTPException(404, "Not found")
    
    def restart_task():
        subprocess.run(["docker-compose", "down"], cwd=target_dir)
        subprocess.run(["docker-compose", "up", "-d"], cwd=target_dir)
    
    background_tasks.add_task(restart_task)
    return {"status": "restarting"}


@app.post("/instances/{name}/rebuild")
def rebuild_instance(name: str, background_tasks: BackgroundTasks):
    """Force rebuild Docker images with --no-cache"""
    target_dir = INSTANCES_DIR / name
    if not target_dir.exists():
        raise HTTPException(404, "Not found")
    
    def rebuild_task():
        # Stop containers first
        subprocess.run(["docker-compose", "down"], cwd=target_dir)
        # Rebuild with no cache
        subprocess.run(["docker-compose", "build", "--no-cache"], cwd=target_dir)
        # Start containers
        subprocess.run(["docker-compose", "up", "-d"], cwd=target_dir)
    
    background_tasks.add_task(rebuild_task)
    return {"status": "rebuilding"}


@app.get("/instances/{name}/logs")
def get_instance_logs(name: str, lines: int = 100, service: str = "backend"):
    """Get container logs"""
    target_dir = INSTANCES_DIR / name
    if not target_dir.exists():
        raise HTTPException(404, "Not found")
    
    container_name = f"institutional_{service}_{name}"
    try:
        result = subprocess.run(
            ["docker", "logs", "--tail", str(lines), container_name],
            capture_output=True, text=True
        )
        return {
            "logs": result.stdout + result.stderr,
            "container": container_name,
            "lines": lines
        }
    except Exception as e:
        return {"error": str(e), "logs": ""}


@app.get("/instances/{name}/metrics")
def get_instance_metrics(name: str):
    """Get CPU/Memory usage via docker stats"""
    client = get_docker_client()
    container_name = f"institutional_backend_{name}"
    
    try:
        container = client.containers.get(container_name)
        stats = container.stats(stream=False)
        
        # Calculate CPU percentage
        cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                   stats['precpu_stats']['cpu_usage']['total_usage']
        system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                      stats['precpu_stats']['system_cpu_usage']
        cpu_percent = (cpu_delta / system_delta) * 100 if system_delta > 0 else 0
        
        # Calculate Memory percentage
        mem_usage = stats['memory_stats'].get('usage', 0)
        mem_limit = stats['memory_stats'].get('limit', 1)
        mem_percent = (mem_usage / mem_limit) * 100 if mem_limit > 0 else 0
        
        return {
            "cpu_percent": round(cpu_percent, 2),
            "memory_percent": round(mem_percent, 2),
            "memory_mb": round(mem_usage / 1024 / 1024, 2),
            "status": container.status
        }
    except docker.errors.NotFound:
        return {"error": "Container not found", "cpu_percent": 0, "memory_percent": 0}
    except Exception as e:
        return {"error": str(e), "cpu_percent": 0, "memory_percent": 0}


@app.get("/instances/{name}/database")
def get_database_info(name: str):
    """List tables and row counts from instance SQLite"""
    import sqlite3
    
    target_dir = INSTANCES_DIR / name
    db_path = target_dir / "backend" / "sql_app.db"
    
    if not db_path.exists():
        # Try data directory
        db_path = target_dir / "data" / f"instance_{name}.db"
    
    if not db_path.exists():
        return {"error": "Database not found", "tables": []}
    
    try:
        conn = sqlite3.connect(str(db_path))
        cursor = conn.cursor()
        
        # Get all tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
        tables = cursor.fetchall()
        
        table_info = []
        for (table_name,) in tables:
            cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
            count = cursor.fetchone()[0]
            table_info.append({"name": table_name, "rows": count})
        
        conn.close()
        return {"tables": table_info, "db_path": str(db_path)}
    except Exception as e:
        return {"error": str(e), "tables": []}


class QueryRequest(BaseModel):
    query: str


@app.post("/instances/{name}/database/query")
def execute_query(name: str, request: QueryRequest):
    """Execute read-only SQL query"""
    import sqlite3
    
    # Security: Only allow SELECT
    query = request.query.strip()
    if not query.upper().startswith("SELECT"):
        raise HTTPException(400, "Only SELECT queries are allowed")
    
    target_dir = INSTANCES_DIR / name
    db_path = target_dir / "backend" / "sql_app.db"
    
    if not db_path.exists():
        db_path = target_dir / "data" / f"instance_{name}.db"
    
    if not db_path.exists():
        raise HTTPException(404, "Database not found")
    
    try:
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        cursor.execute(query)
        rows = [dict(row) for row in cursor.fetchall()]
        conn.close()
        return {"results": rows, "count": len(rows)}
    except Exception as e:
        raise HTTPException(400, f"Query error: {str(e)}")


class BatchRequest(BaseModel):
    names: List[str]


@app.post("/instances/batch/{action}")
def batch_action(action: str, request: BatchRequest, background_tasks: BackgroundTasks):
    """Batch start/stop/restart multiple instances"""
    if action not in ["start", "stop", "restart"]:
        raise HTTPException(400, f"Invalid action: {action}")
    
    results = []
    for name in request.names:
        target_dir = INSTANCES_DIR / name
        if not target_dir.exists():
            results.append({"name": name, "status": "not_found"})
            continue
        
        if action == "start":
            background_tasks.add_task(start_instance_task, target_dir, name)
        elif action == "stop":
            subprocess.run(["docker-compose", "down"], cwd=target_dir)
        elif action == "restart":
            def restart():
                subprocess.run(["docker-compose", "down"], cwd=target_dir)
                subprocess.run(["docker-compose", "up", "-d"], cwd=target_dir)
            background_tasks.add_task(restart)
        
        results.append({"name": name, "status": f"{action}ing"})
    
    return {"action": action, "results": results}
