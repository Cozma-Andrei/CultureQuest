import flwr as fl
from app.core.config import settings
from app.federated.strategy import build_strategy


def start_fl_server() -> None:
    fl.server.start_server(
        server_address=f"{settings.flower_server_host}:{settings.flower_server_port}",
        config=fl.server.ServerConfig(num_rounds=settings.fl_rounds),
        strategy=build_strategy(),
    )


if __name__ == "__main__":
    start_fl_server()
