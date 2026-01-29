"""
V3 Trading System - Deep RL Portfolio Optimizer Service
Uses Actor-Critic RL for dynamic portfolio allocation
"""

import asyncio
import json
from datetime import datetime
from typing import List, Dict, Optional
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import redis.asyncio as redis
import structlog
import os

# Configure logging
log = structlog.get_logger()

# ==================== Configuration ====================

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))

STATE_DIM = 50  # Portfolio state dimension
ACTION_DIM = 4  # Risk per symbol (4 symbols)
HIDDEN_DIM = 128
LR_ACTOR = 0.0001
LR_CRITIC = 0.001
GAMMA = 0.99  # Discount factor

# ==================== Actor-Critic Networks ====================

class ActorNetwork(nn.Module):
    """Policy network (outputs actions)"""

    def __init__(self, state_dim: int, action_dim: int, hidden_dim: int = 128):
        super(ActorNetwork, self).__init__()

        self.fc1 = nn.Linear(state_dim, hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, hidden_dim)
        self.fc3 = nn.Linear(hidden_dim, action_dim)

        self.relu = nn.ReLU()
        self.sigmoid = nn.Sigmoid()  # Output 0-1 (risk percentages)

    def forward(self, state):
        x = self.relu(self.fc1(state))
        x = self.relu(self.fc2(x))
        x = self.sigmoid(self.fc3(x))  # 0-1 range
        return x * 0.5  # Scale to 0-0.5% risk

class CriticNetwork(nn.Module):
    """Value network (estimates state value)"""

    def __init__(self, state_dim: int, hidden_dim: int = 128):
        super(CriticNetwork, self).__init__()

        self.fc1 = nn.Linear(state_dim, hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, hidden_dim)
        self.fc3 = nn.Linear(hidden_dim, 1)

        self.relu = nn.ReLU()

    def forward(self, state):
        x = self.relu(self.fc1(state))
        x = self.relu(self.fc2(x))
        value = self.fc3(x)
        return value

# ==================== DRL Agent ====================

class DRLPortfolioAgent:
    """Actor-Critic RL Agent for portfolio optimization"""

    def __init__(self, state_dim: int, action_dim: int):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        # Networks
        self.actor = ActorNetwork(state_dim, action_dim, HIDDEN_DIM).to(self.device)
        self.critic = CriticNetwork(state_dim, HIDDEN_DIM).to(self.device)

        # Optimizers
        self.actor_optimizer = optim.Adam(self.actor.parameters(), lr=LR_ACTOR)
        self.critic_optimizer = optim.Adam(self.critic.parameters(), lr=LR_CRITIC)

        log.info("drl_agent_initialized", device=str(self.device))

    def get_action(self, state: np.ndarray) -> np.ndarray:
        """Get action (risk allocation) from current state"""
        state_tensor = torch.FloatTensor(state).unsqueeze(0).to(self.device)

        with torch.no_grad():
            action = self.actor(state_tensor)

        return action.cpu().numpy()[0]

    def train_step(self, state: np.ndarray, action: np.ndarray, reward: float, next_state: np.ndarray, done: bool):
        """Single training step (Actor-Critic update)"""
        state_tensor = torch.FloatTensor(state).unsqueeze(0).to(self.device)
        next_state_tensor = torch.FloatTensor(next_state).unsqueeze(0).to(self.device)
        action_tensor = torch.FloatTensor(action).unsqueeze(0).to(self.device)
        reward_tensor = torch.FloatTensor([reward]).to(self.device)

        # Critic update
        value = self.critic(state_tensor)
        next_value = self.critic(next_state_tensor)

        td_target = reward_tensor + GAMMA * next_value * (1 - int(done))
        td_error = td_target - value

        critic_loss = td_error.pow(2).mean()

        self.critic_optimizer.zero_grad()
        critic_loss.backward()
        self.critic_optimizer.step()

        # Actor update
        predicted_action = self.actor(state_tensor)
        actor_loss = -self.critic(state_tensor).mean()  # Policy gradient

        self.actor_optimizer.zero_grad()
        actor_loss.backward()
        self.actor_optimizer.step()

        return critic_loss.item(), actor_loss.item()

    def save(self, filepath: str):
        """Save model"""
        torch.save({
            'actor_state_dict': self.actor.state_dict(),
            'critic_state_dict': self.critic.state_dict(),
        }, filepath)
        log.info("drl_model_saved", filepath=filepath)

    def load(self, filepath: str):
        """Load model"""
        checkpoint = torch.load(filepath, map_location=self.device)
        self.actor.load_state_dict(checkpoint['actor_state_dict'])
        self.critic.load_state_dict(checkpoint['critic_state_dict'])
        log.info("drl_model_loaded", filepath=filepath)

# ==================== Portfolio Service ====================

class PortfolioService:
    """Main DRL portfolio optimization service"""

    def __init__(self):
        self.agent = DRLPortfolioAgent(STATE_DIM, ACTION_DIM)
        self.redis_client: Optional[redis.Redis] = None
        self.symbols = ["EURUSD", "GBPUSD", "USDCAD", "XAUUSD"]

    async def connect_redis(self):
        """Connect to Redis"""
        self.redis_client = await redis.from_url(
            f"redis://{REDIS_HOST}:{REDIS_PORT}",
            encoding="utf-8",
            decode_responses=True
        )
        await self.redis_client.ping()
        log.info("redis_connected", host=REDIS_HOST, port=REDIS_PORT)

    def extract_state(self, portfolio_data: Dict) -> np.ndarray:
        """
        Extract state vector from portfolio data
        State includes: positions, returns, volatility, correlations, metrics
        """
        state = []

        # Current positions (4 symbols)
        positions = portfolio_data.get("positions", {})
        for symbol in self.symbols:
            state.append(positions.get(symbol, 0.0))

        # 20-period returns (4 symbols × 20 periods = 80 values → compress to 20)
        returns = portfolio_data.get("returns", {})
        for symbol in self.symbols:
            symbol_returns = returns.get(symbol, [0.0] * 20)
            # Use last 5 returns only to save space
            state.extend(symbol_returns[-5:])

        # Volatility (4 symbols)
        volatility = portfolio_data.get("volatility", {})
        for symbol in self.symbols:
            state.append(volatility.get(symbol, 0.0))

        # Portfolio metrics (5 values)
        metrics = portfolio_data.get("metrics", {})
        state.append(metrics.get("sharpe", 0.0))
        state.append(metrics.get("sortino", 0.0))
        state.append(metrics.get("max_dd", 0.0))
        state.append(metrics.get("win_rate", 0.5))
        state.append(metrics.get("profit_factor", 1.0))

        # Pad to STATE_DIM
        while len(state) < STATE_DIM:
            state.append(0.0)

        return np.array(state[:STATE_DIM], dtype=np.float32)

    async def optimize_portfolio(self, portfolio_data: Dict) -> Dict:
        """
        Get DRL-optimized portfolio allocation
        """
        # Extract state
        state = self.extract_state(portfolio_data)

        # Get action from actor network
        action = self.agent.get_action(state)

        # Map action to risk percentages
        risk_per_symbol = {
            symbol: float(risk) for symbol, risk in zip(self.symbols, action)
        }

        # Fixed confluence thresholds (in v3.1, could be learned)
        confluence_threshold = {symbol: 6.0 for symbol in self.symbols}

        # All symbols allowed (in v3.1, could be learned)
        allow_trading = {symbol: True for symbol in self.symbols}

        result = {
            "risk_per_symbol": risk_per_symbol,
            "confluence_threshold": confluence_threshold,
            "allow_trading": allow_trading,
            "confidence": 0.75,  # Mock confidence
            "timestamp": datetime.utcnow().isoformat()
        }

        # Cache in Redis (1-hour TTL)
        cache_key = "portfolio:optimal_allocation"
        await self.redis_client.setex(
            cache_key,
            3600,
            json.dumps(result)
        )

        log.info("portfolio_optimized", risk=risk_per_symbol)

        return result

    async def heartbeat(self):
        """Send heartbeat to Redis"""
        while True:
            try:
                await self.redis_client.setex("heartbeat:drl", 120, "alive")
            except Exception as e:
                log.error("heartbeat_failed", error=str(e))

            await asyncio.sleep(60)

# ==================== Main ====================

async def main():
    """Main entry point"""
    log.info("drl_service_starting")

    service = PortfolioService()
    await service.connect_redis()

    # Load pre-trained model if exists
    model_path = "/app/models/drl_agent.pth"
    if os.path.exists(model_path):
        service.agent.load(model_path)
    else:
        log.warning("no_pretrained_model_found")

    # Start background tasks
    tasks = [
        asyncio.create_task(service.heartbeat())
    ]

    log.info("drl_service_running")

    # Wait for tasks
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
