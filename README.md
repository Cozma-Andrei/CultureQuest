# CultureQuest

Mobile platform for urban exploration based on proximity and Federated Learning.

## Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter + TensorFlow Lite |
| Backend | FastAPI (Python) |
| Database | MongoDB |
| Cache | Redis |
| Proximity | Custom geofencing (geofence_service) |
| Federated Learning | Flower (flwr) |
| ML Model | MLP → TFLite |

## Structure

```
CultureQuest/
├── backend/        # FastAPI server + Flower FL orchestrator
├── mobile/         # Flutter app (FL client + TFLite inference)
└── docker-compose.yml
```

## Running locally

```bash
# Infrastructure
docker-compose up -d

# Backend
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload

# Mobile
cd mobile
flutter pub get
flutter run
```

## Federated Learning progression

- Phase 1: FedAvg + MLP (initial)
- Phase 2: FedProx (non-IID data)
- Phase 3: FedAdam (faster convergence)
- Phase 4: Secure Aggregation (privacy hardening)
