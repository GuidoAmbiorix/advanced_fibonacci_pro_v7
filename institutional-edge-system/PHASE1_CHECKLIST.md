# ✅ PHASE 1: CRITICAL FIXES - CHECKLIST

**Duration:** 1 semana
**Priority:** 🔴 URGENT
**Status:** Not Started

---

## 📋 PRE-PHASE CHECKLIST

Antes de comenzar, verifica:

- [ ] Git está en estado limpio (`git status`)
- [ ] Tienes backup del código actual
- [ ] Tests existentes están pasando
- [ ] Docker compose funciona (bases de datos)
- [ ] Tienes MT5 demo account para testing

---

## 🎯 SUB-PHASE 1.1: RISK MANAGEMENT OVERHAUL

**Estimated Time:** 3 días
**Files to Modify:** 5
**New Files:** 3
**Tests Required:** 15+

### Day 1: Core Risk Manager Rewrite

#### Morning (4h):
- [ ] **Task 1.1.1:** Crear backup de `risk_manager.py`
  ```bash
  cp backend/app/services/risk_manager.py backend/app/services/risk_manager.py.backup
  ```

- [ ] **Task 1.1.2:** Crear nuevo risk manager con límites correctos
  - Max risk per trade: 1% (no 5%)
  - Risk tiers based on DD
  - Volatility adjustment

- [ ] **Task 1.1.3:** Implementar DrawdownProtection class
  ```python
  class DrawdownProtection:
      def get_risk_multiplier(self, current_dd: float) -> float:
          """
          DD 0-3%: 1.0x (normal risk)
          DD 3-5%: 0.5x (half risk)
          DD 5-10%: 0.25x (quarter risk)
          DD >10%: 0.0x (stop trading)
          """
  ```

#### Afternoon (4h):
- [ ] **Task 1.1.4:** Crear `portfolio_manager.py`
  - Track all open positions
  - Calculate total portfolio risk
  - Enforce 6% max portfolio risk

- [ ] **Task 1.1.5:** Implementar correlation matrix
  ```python
  CORRELATION_MATRIX = {
      ('EURUSD', 'GBPUSD'): 0.85,
      ('EURUSD', 'USDCHF'): -0.92,
      # ...
  }
  ```

**Deliverables Day 1:**
- [ ] `risk_manager.py` reescrito
- [ ] `portfolio_manager.py` creado
- [ ] Correlation logic implementado

---

### Day 2: Testing & Integration

#### Morning (4h):
- [ ] **Task 1.1.6:** Crear test suite para risk manager
  ```
  tests/unit/test_risk_manager.py
  - test_max_risk_per_trade()
  - test_drawdown_multipliers()
  - test_volatility_adjustment()
  - test_consecutive_loss_reduction()
  - test_risk_never_exceeds_limits()
  ```

- [ ] **Task 1.1.7:** Crear test suite para portfolio manager
  ```
  tests/unit/test_portfolio_manager.py
  - test_portfolio_risk_calculation()
  - test_max_portfolio_risk_block()
  - test_correlation_blocking()
  - test_position_limits()
  ```

#### Afternoon (4h):
- [ ] **Task 1.1.8:** Integrar nuevo risk manager con trading_bot.py
  - Replace old risk calculations
  - Add portfolio checks before opening trades

- [ ] **Task 1.1.9:** Update BotConfig model
  ```python
  # Add new fields:
  max_risk_percent: float = 1.0  # Was 5.0
  max_portfolio_risk: float = 6.0
  check_correlation: bool = True
  ```

- [ ] **Task 1.1.10:** Run all tests
  ```bash
  pytest tests/unit/test_risk_manager.py -v
  pytest tests/unit/test_portfolio_manager.py -v
  ```

**Deliverables Day 2:**
- [ ] 15+ unit tests created
- [ ] All tests passing
- [ ] Integration complete

---

### Day 3: Configuration & Validation

#### Morning (3h):
- [ ] **Task 1.1.11:** Create configuration profiles
  ```python
  # backend/app/core/config_profiles.py

  CONSERVATIVE = {
      "risk_percent": 0.5,
      "max_trades": 1,
      "min_confluence_score": 8,
      "daily_loss_limit": 2.0,
      "cooldown_minutes": 60,
  }

  MODERATE = {
      "risk_percent": 1.0,
      "max_trades": 2,
      "min_confluence_score": 7,
      "daily_loss_limit": 3.0,
      "cooldown_minutes": 30,
  }

  AGGRESSIVE = {
      "risk_percent": 1.5,
      "max_trades": 3,
      "min_confluence_score": 6,
      "daily_loss_limit": 4.0,
      "cooldown_minutes": 15,
  }
  ```

- [ ] **Task 1.1.12:** Add profile selection to config
  - Update Settings class
  - Validate profile on startup

#### Afternoon (3h):
- [ ] **Task 1.1.13:** Integration test with mock trades
  ```python
  # Test scenario: 10 losing trades in a row
  # Verify: Risk reduces, then stops trading at DD limit
  ```

- [ ] **Task 1.1.14:** Update documentation
  - Document new risk parameters
  - Add examples of risk calculations
  - Warning about changing defaults

- [ ] **Task 1.1.15:** Code review checkpoint
  - Review all changes
  - Verify no regressions
  - Check test coverage (should be >90%)

**Deliverables Day 3:**
- [ ] Config profiles created
- [ ] Integration tests passing
- [ ] Documentation updated
- [ ] Code review complete

---

## 🔐 SUB-PHASE 1.2: SECURITY FIXES

**Estimated Time:** 2 días
**Priority:** 🔴 CRITICAL

### Day 4: Encryption & OAuth2 Fix

#### Morning (4h):
- [ ] **Task 1.2.1:** Create encryption module
  ```python
  # backend/app/core/encryption.py
  from cryptography.fernet import Fernet

  class PasswordEncryption:
      def __init__(self, key: str):
          self.cipher = Fernet(key.encode())

      def encrypt(self, password: str) -> str:
          return self.cipher.encrypt(password.encode()).decode()

      def decrypt(self, encrypted: str) -> str:
          return self.cipher.decrypt(encrypted.encode()).decode()
  ```

- [ ] **Task 1.2.2:** Generate encryption key
  ```bash
  python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
  # Add to .env as ENCRYPTION_KEY
  ```

- [ ] **Task 1.2.3:** Update database schema
  ```sql
  -- Migrate existing passwords
  ALTER TABLE bot_configs
  ADD COLUMN mt5_password_encrypted_v2 TEXT;

  -- Script to encrypt existing passwords
  ```

#### Afternoon (4h):
- [ ] **Task 1.2.4:** Fix OAuth2 state mismatch
  ```typescript
  // frontend/src/services/oauth2AuthEnhanced.ts

  // Issue: State stored in sessionStorage but read from different storage
  // Fix: Consistent storage mechanism

  storeAuthState(state: string) {
      sessionStorage.setItem('oauth_state', state);
      sessionStorage.setItem('oauth_state_timestamp', Date.now());
  }

  validateAuthState(receivedState: string): boolean {
      const storedState = sessionStorage.getItem('oauth_state');
      const timestamp = sessionStorage.getItem('oauth_state_timestamp');

      // Check state matches
      if (storedState !== receivedState) return false;

      // Check not expired (5 min)
      if (Date.now() - timestamp > 300000) return false;

      // Clear after validation
      sessionStorage.removeItem('oauth_state');
      sessionStorage.removeItem('oauth_state_timestamp');

      return true;
  }
  ```

- [ ] **Task 1.2.5:** Test OAuth2 flow
  - Clear browser storage
  - Attempt login
  - Verify no state mismatch
  - Test token refresh

**Deliverables Day 4:**
- [ ] Encryption module created
- [ ] Passwords encrypted in DB
- [ ] OAuth2 bug fixed
- [ ] Auth flow tested

---

### Day 5: Rate Limiting & Production Security

#### Morning (4h):
- [ ] **Task 1.2.6:** Install slowapi
  ```bash
  cd backend
  pip install slowapi
  echo "slowapi" >> requirements.txt
  ```

- [ ] **Task 1.2.7:** Add rate limiting to auth endpoints
  ```python
  # backend/app/api/auth.py
  from slowapi import Limiter
  from slowapi.util import get_remote_address

  limiter = Limiter(key_func=get_remote_address)

  @app.post("/api/auth/login")
  @limiter.limit("5/minute")
  async def login(request: Request, credentials: LoginRequest):
      ...

  @app.post("/api/auth/register")
  @limiter.limit("3/hour")
  async def register(request: Request, user: UserCreate):
      ...
  ```

- [ ] **Task 1.2.8:** Implement JWT refresh token rotation
  ```python
  # backend/app/core/security.py

  def create_refresh_token(user_id: int) -> str:
      """Create refresh token with longer expiry"""

  def rotate_tokens(refresh_token: str) -> Tuple[str, str]:
      """Return new access + refresh tokens, invalidate old refresh"""
  ```

#### Afternoon (4h):
- [ ] **Task 1.2.9:** Production environment config
  ```python
  # .env.example.production

  # Security
  SECRET_KEY=CHANGE_THIS_TO_RANDOM_64_CHAR_STRING
  JWT_SECRET_KEY=CHANGE_THIS_TO_RANDOM_64_CHAR_STRING
  ENCRYPTION_KEY=CHANGE_THIS_TO_FERNET_KEY

  # CORS - Restrict to your domain
  CORS_ORIGINS=https://yourdomain.com

  # Database - Use strong passwords
  POSTGRES_PASSWORD=STRONG_PASSWORD_HERE

  # MT5 - Never commit real credentials
  MT5_LOGIN=DEMO_ACCOUNT
  MT5_PASSWORD=ENCRYPTED_VALUE
  ```

- [ ] **Task 1.2.10:** Security audit
  ```bash
  # Run security checks
  pip install bandit safety
  bandit -r backend/app/
  safety check
  ```

- [ ] **Task 1.2.11:** Update .gitignore
  ```
  # Add to .gitignore
  .env
  .env.local
  .env.production
  *.backup
  backend/app/services/*.backup
  ```

**Deliverables Day 5:**
- [ ] Rate limiting active
- [ ] JWT refresh rotation implemented
- [ ] Production config created
- [ ] Security audit clean
- [ ] Secrets properly managed

---

## ⚙️ SUB-PHASE 1.3: CONFIGURATION DEFAULTS

**Estimated Time:** 1 día

### Day 6: Default Configuration & Validation

#### Morning (4h):
- [ ] **Task 1.3.1:** Update default config in database.py
  ```python
  # backend/app/models/database.py

  class BotConfig(Base):
      # OLD:
      # risk_percent = Column(Float, default=2.0)

      # NEW - Conservative defaults:
      risk_percent = Column(Float, default=0.5)
      max_risk_percent = Column(Float, default=1.0)
      max_trades = Column(Integer, default=1)
      min_confluence_score = Column(Integer, default=8)
      max_spread = Column(Float, default=1.5)
      daily_loss_limit_percent = Column(Float, default=2.0)
      cooldown_minutes = Column(Integer, default=60)
  ```

- [ ] **Task 1.3.2:** Create config validator
  ```python
  # backend/app/core/config_validator.py

  class ConfigValidator:
      def validate(self, config: BotConfig) -> List[str]:
          """Return list of warnings for risky configs"""
          warnings = []

          if config.risk_percent > 1.0:
              warnings.append("⚠️ Risk >1% is aggressive")

          if config.max_trades > 2:
              warnings.append("⚠️ Max trades >2 increases exposure")

          if config.min_confluence_score < 7:
              warnings.append("⚠️ Min score <7 may reduce quality")

          # ... more checks

          return warnings
  ```

#### Afternoon (4h):
- [ ] **Task 1.3.3:** Add validation on bot start
  ```python
  # backend/app/services/trading_bot.py

  async def start(self):
      # Validate config
      validator = ConfigValidator()
      warnings = validator.validate(self.config)

      if warnings:
          for warning in warnings:
              logger.warning(warning)
              await self._log_activity(warning, "warning")
  ```

- [ ] **Task 1.3.4:** Create migration script for existing configs
  ```python
  # backend/migrations/update_configs_conservative.py

  def migrate_to_conservative():
      """Update all existing configs to safe defaults"""
      db = SessionLocal()
      configs = db.query(BotConfig).all()

      for config in configs:
          if config.risk_percent > 1.0:
              logger.warning(f"Reducing risk for bot {config.id} from {config.risk_percent}% to 1.0%")
              config.risk_percent = 1.0

          # ... more updates

      db.commit()
  ```

- [ ] **Task 1.3.5:** Update frontend config UI
  ```vue
  <!-- frontend/src/views/SettingsView.vue -->

  <!-- Add warnings for risky settings -->
  <div v-if="config.risk_percent > 1.0" class="alert alert-warning">
    ⚠️ Risk above 1% is considered aggressive
  </div>
  ```

- [ ] **Task 1.3.6:** Documentation update
  ```markdown
  # docs/configuration.md

  ## Risk Management Settings

  ### Conservative (Recommended for beginners)
  - Risk: 0.5%
  - Max trades: 1
  - Min score: 8

  ### Moderate (For experienced traders)
  - Risk: 1.0%
  - Max trades: 2
  - Min score: 7

  ### Aggressive (Not recommended)
  - Risk: 1.5%
  - Max trades: 3
  - Min score: 6
  ```

**Deliverables Day 6:**
- [ ] Conservative defaults set
- [ ] Config validator created
- [ ] Migration script ready
- [ ] UI warnings added
- [ ] Documentation updated

---

## ✅ END OF WEEK 1: VALIDATION CHECKLIST

Before moving to Phase 2, verify ALL items:

### Code Quality:
- [ ] All unit tests passing (pytest)
- [ ] Test coverage >90% on risk module
- [ ] No linting errors (flake8/black)
- [ ] Type hints added (mypy clean)
- [ ] Code reviewed by peer (or self-review)

### Functionality:
- [ ] Risk calculation verified with test scenarios
- [ ] Portfolio risk blocking works
- [ ] Correlation blocking works
- [ ] Drawdown protection activates correctly
- [ ] OAuth2 login works without errors
- [ ] Rate limiting blocks excessive requests
- [ ] Config validation shows warnings

### Documentation:
- [ ] CHANGELOG.md updated
- [ ] Risk parameters documented
- [ ] Security changes documented
- [ ] Config examples provided

### Git:
- [ ] All changes committed
- [ ] Meaningful commit messages
- [ ] Branch ready to merge: `phase1-risk-security`
- [ ] Tag created: `v1.0.0-phase1`

### Manual Testing:
- [ ] Start bot with conservative config - works
- [ ] Simulate 10% DD - bot stops trading
- [ ] Open 2 correlated positions - 3rd blocked
- [ ] Exceed daily loss limit - trading stops
- [ ] Login/logout flow - no OAuth errors
- [ ] Change risky config - warnings displayed

---

## 🚨 RED FLAGS - STOP IF:

- [ ] Tests failing and can't fix in 1 day
- [ ] Risk calculations giving wrong values
- [ ] Security vulnerabilities found
- [ ] System crashes or becomes unstable
- [ ] Can't verify fixes are working

**If any red flag:** Pause, debug, don't proceed to Phase 2.

---

## 📊 METRICS TO TRACK:

### Before Phase 1:
```
Max Risk Per Trade: 5.0%
Max Portfolio Risk: Unlimited
Correlation Check: None
DD Protection: Basic (5% threshold)
Security Issues: 3 critical
```

### After Phase 1 (Target):
```
Max Risk Per Trade: 1.0%
Max Portfolio Risk: 6.0%
Correlation Check: Active
DD Protection: Tiered (3%, 5%, 10%)
Security Issues: 0 critical
```

---

## 🎯 DEFINITION OF DONE

Phase 1 is complete when:

1. ✅ All 15+ tasks completed
2. ✅ All tests passing
3. ✅ Manual testing checklist complete
4. ✅ Documentation updated
5. ✅ Code reviewed and approved
6. ✅ Metrics targets achieved
7. ✅ No critical bugs remaining
8. ✅ Stakeholder approval (you!)

**Ready to start Phase 2:** Backtesting

---

**Created:** 2025-12-02
**Last Updated:** 2025-12-02
**Status:** Ready to begin
