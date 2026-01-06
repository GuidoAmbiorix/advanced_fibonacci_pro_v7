
# 📘 Master-Slave Copy Trading Setup Guide

This document outlines the exact steps to configure a **Master-Slave** copy trading enviornment using the Fleet Commander architecture.

## 🎯 Concept
*   **Master**: The "Brain" (Orchestrator) running the strategy logic.
*   **Slave**: A "Worker Node" (Docker Container) running a dumb MT5 terminal that listens for signals.

---

## ✅ Step 1: Define the Master (Orchestrator)

The "Master" is already running inside the Orchestrator. 
*   **Action**: Ensure your `docker-compose.admin.yml` has the Orchestrator service (it does).
*   **Config**: The Master uses the default strategy settings defined in the Dashboard.

## ✅ Step 2: Create the Slave Node (Worker)

You need to spin up a "Body" for the slave to live in. This is done via `docker-compose.nodes.yml`.

1.  Open `docker-compose.nodes.yml`.
2.  Duplicate the `worker-node-1` block for your new account:

```yaml
  worker-node-2:
    build:
      context: .
      dockerfile: nodes/Dockerfile
    container_name: iep-worker-2  <-- UNIQUE NAME
    restart: unless-stopped
    environment:
      - INSTANCE_ROLE=SLAVE
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_PORT=5672
      - POSTGRES_SERVER=postgres
      - DATABASE_URL=postgresql://postgres:postgres@postgres:5432/institutional_edge
      - WORKER_ID=worker-2          <-- UNIQUE ID
      
      # CREDENTIALS (Or use .env)
      - MT5_LOGIN=12345678
      - MT5_PASSWORD=trading_password
      - MT5_SERVER=FundingPips-Demo
    networks:
      - trading_network
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
```

## ✅ Step 3: Configure the Link (Database)

You need to tell the system "Worker 2 should copy Master 1".
*Currently, this is done via a setup script, but later will be in the Dashboard.*

1.  Run the setup script (once created):
    ```bash
    python3 scripts/setup_copy_pool.py
    ```
2.  Follow the prompts:
    *   Select Master: "Institutional Gold Bot"
    *   Select Slave: "Worker-2 (Funding Pips)"
    *   Set Risk: "Multiplier 1.0" (Same risk) or "Fixed Lot 0.1".

## ✅ Step 4: Launch

1.  Start the new node:
    ```bash
    docker-compose -f docker-compose.nodes.yml up -d
    ```
2.  Verify connectivity in Dashboard:
    *   Go to `http://localhost:9000`
    *   Check "Connected Nodes" list.
    *   Confirm "Worker 2" Status is 🟢 ONLINE.

---

## 🚀 Summary Checklist

- [ ] Add `worker-node-X` to `docker-compose.nodes.yml`.
- [ ] Set `MT5_LOGIN`, `MT5_PASSWORD`, `MT5_SERVER` in the environment variables.
- [ ] Run `docker-compose up -d` to start the container.
- [ ] (Future) Link accounts in UI.
