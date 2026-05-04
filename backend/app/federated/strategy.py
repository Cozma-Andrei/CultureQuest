import flwr as fl
from flwr.server.strategy import FedAvg
from app.core.config import settings


def build_strategy() -> fl.server.strategy.Strategy:
    """Phase 1: FedAvg. Switch to FedProx when non-IID drift is observed."""
    return FedAvg(
        min_fit_clients=settings.fl_min_clients,
        min_evaluate_clients=settings.fl_min_clients,
        min_available_clients=settings.fl_min_clients,
    )
