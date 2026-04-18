# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project: JOSYEL Fleet Intelligence System

Real-time fleet management platform for GPS tracking, fuel theft detection, driver behavior monitoring, and operational cost reduction. Integrates with Wialon telematics backend, targets West African deployment at scale.

## Architecture Overview

### Data Flow
```
Teltonika Devices (FMC130/FMC640)
    ├─ GPS location + heading
    ├─ Fuel level (analog sensor + CAN)
    ├─ Ignition/engine status (CAN)
    └─ Custom parameters (harsh braking, idling, temp)
         │
         ▼
Wialon Cloud (Remote API / Hosting)
    ├─ CAN parser (maps raw OBD2 to parameters)
    ├─ Geofence engine
    ├─ Event rules (fuel drop, geofence, harsh drive)
    └─ Data warehouse (30-day history)
         │
         ▼
JOSYEL Backend (Node.js / Python)
    ├─ Wialon API client (REST polling or webhooks)
    ├─ Fuel theft detection engine (delta + time-series)
    ├─ Alert aggregation & routing
    └─ Authentication + driver/fleet management
         │
         ▼
JOSYEL Dashboard (React)
    ├─ Live map (Leaflet)
    ├─ Real-time fuel gauges + alerts
    ├─ Driver behavior analytics
    └─ Historical reports
```

### Tech Stack
- **Frontend:** React + Leaflet (maps) + Recharts (time-series) + Neon UI kit
- **Backend:** Node.js + Express OR Python + FastAPI (TBD)
- **Database:** PostgreSQL (alert history, fleet config, user accounts)
- **Real-time:** WebSocket via Socket.io OR polling (Wialon every 30s)
- **Hosting:** AWS / Digital Ocean (scalable for West Africa)
- **Telematics:** Wialon (data ingestion, CAN mapping, rule engine)

### Key Components

#### Fuel Theft Detection
- **Algorithm:** Multi-factor:
  - Sudden fuel drop (>5% in <2min) + engine OFF = theft flag
  - Volume variance filtering (exponential smoothing to reduce sensor noise)
  - Location correlation (detect repeat thief patterns)
  - Time-window analysis (flag overnight drops separately from day drops)
- **Threshold Tuning:** Per-vehicle calibration (different tank sizes, sensor types)
- **False Positive Reduction:** Exponential smoothing filter + sensor anomaly detection

#### Alert System
- **Sources:** Wialon webhooks OR polling (Wialon every 30s for events)
- **Processing:** Redis queue + worker threads (reliability + throughput)
- **Routing:** SMS/Push/Email based on alert severity + driver/fleet preferences
- **Deduplication:** 5-minute window to avoid alert spam

#### Driver Monitoring
- **Data:** Harsh braking, idling >10min, speeding, geofence violations
- **Source:** Wialon parses CAN data (acceleration, RPM, location velocity)
- **Scoring:** Simple behavior score (0-100) per driver, weekly trend
- **Edge Case:** Handle multi-driver vehicles (different ignition events)

### Configuration & Calibration
- **Wialon Setup:** CAN mapping stored in Wialon device parameters
- **Fuel Sensor:** Calibrate min/max analog input → fuel % in Wialon UI (once per vehicle type)
- **Thresholds:** Store in backend DB (per-fleet customization)
- **Geofences:** Created/managed via Wialon UI or JOSYEL API

## Development Setup

### Install
```bash
# Backend (Node)
cd backend && npm install

# Frontend
cd frontend && npm install
```

### Environment
Create `.env` files:
```
# backend/.env
WIALON_API_URL=https://hosting.wialon.com/gps/   # or your instance
WIALON_TOKEN=<api_token>
DATABASE_URL=postgresql://user:pass@localhost/josyel
REDIS_URL=redis://localhost:6379
ALERT_SMS_PROVIDER=twilio  # or local stub for dev
JWT_SECRET=<random_key>
```

```
# frontend/.env
REACT_APP_BACKEND_URL=http://localhost:5000
REACT_APP_MAP_PROVIDER=leaflet
```

### Run Locally
```bash
# Terminal 1: Backend API
cd backend && npm run dev   # Starts on :5000, auto-reload

# Terminal 2: Frontend
cd frontend && npm start    # Starts on :3000 (create-react-app default)

# Terminal 3: Worker (alert processing)
cd backend && npm run worker   # Processes Redis queue
```

### Tests
```bash
# Backend unit tests
cd backend && npm test

# Backend integration tests (requires Wialon staging)
cd backend && npm run test:integration

# Frontend component tests
cd frontend && npm test

# E2E tests (Cypress, full flow with mock Wialon)
cd frontend && npm run cypress:open
```

### Database
```bash
# Migrations (after schema changes)
cd backend && npm run migrate:latest

# Reset dev database
npm run db:reset   # Careful in production!
```

## Key Design Decisions

### Why Wialon for Backend?
Wialon handles device ingestion (millions of devices), CAN parsing, geofence engine, and data warehouse. Building these from scratch = 6+ months. Using Wialon = focus JOSYEL on UI + smart alerts + business logic.

### Why Not Real-time WebSocket for Dashboard?
Fuel theft detection works at 30-60s granularity (sensor drift, false positives rare at lower intervals). Polling Wialon every 30s costs ~$200/mo vs. continuous WebSocket streaming. MVP uses polling; upgrade to WebSocket if needed for driver behavior real-time scoring.

### Alert Deduplication Window = 5 Minutes
Wialon sensor noise can trigger same alert multiple times in 60s. 5-min window = user sees alert once, but can still click "update" to refresh. Shorter = spam, longer = miss real events.

### PostgreSQL Over NoSQL
Alert history = relational (fleet → vehicle → fuel events → driver actions). Relational queries easier, better audit trail, proven for fleet scale (tested 100K+ vehicles).

## Common Development Tasks

### Add New Alert Type
1. Define trigger logic in `backend/src/alerts/detectors/<alert_type>.js`
2. Add to Wialon event mapping (if CAN-based) or backend rules
3. Add UI icon/color in `frontend/src/components/AlertBadge.js`
4. Test with mock Wialon data in `backend/tests/mock-wialon-data.js`

### Calibrate Fuel Theft Threshold
1. Pull 1 week of fuel data for target vehicle from Wialon
2. Run `backend/scripts/calibrate-fuel.js <vehicle_id>`
3. Adjust `FUEL_LOSS_THRESHOLD_PCT` and `FUEL_DROP_WINDOW_MS` in DB config
4. Test with known theft events (staging only)

### Deploy Backend
```bash
# Build & push Docker image (if using containers)
docker build -t josyel-backend:latest .
docker push <registry>/josyel-backend:latest

# Deploy to production (e.g., AWS ECS)
npm run deploy:prod
```

## Debugging

### Fuel Theft False Positives
Check `backend/logs/fuel-deltas.log` (all fuel changes >2%, with context). If sensor noise:
- Increase smoothing window in DB config
- Verify Wialon sensor calibration for vehicle

### Missing Alerts
1. Check Wialon is pushing data: `curl https://hosting.wialon.com/gps/... -H "Authorization: Bearer $WIALON_TOKEN"`
2. Verify Redis queue isn't backed up: `redis-cli LLEN alert-queue`
3. Check worker logs for parsing errors: `tail backend/logs/worker.log`

### API Rate Limits
Wialon limits ~1000 req/min per account. If hitting limits:
- Use webhooks instead of polling (cheaper, faster)
- Increase polling interval from 30s to 60s
- Batch requests via `gdata_get` endpoint

## Deployment Checklist (MVP)

- [ ] Wialon account provisioned + devices configured
- [ ] Backend API tested against Wialon staging
- [ ] Fuel theft thresholds calibrated for target vehicles
- [ ] Dashboard mockups approved by client
- [ ] Push notification provider (Twilio/Firebase) configured
- [ ] PostgreSQL backups tested
- [ ] SSL certificates (Let's Encrypt)
- [ ] Monitoring (error logging, alert latency dashboards)

## Notes for Future Instances

- JOSYEL is a greenfield project; MVP focuses on fuel theft detection + live tracking
- Wialon API docs: https://sdk.wialon.com/wiki/en/sidebar/remoteapi/overview
- Teltonika device manuals available in `/docs/devices/` (as added)
- Client pitch materials in `/pitches/` (architecture diagrams, ROI models)
- West Africa deployment = plan for unstable internet; offline mode queues alerts locally
