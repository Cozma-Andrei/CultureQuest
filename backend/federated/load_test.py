#!/usr/bin/env python3
"""
Load test for the FL aggregation endpoint (POST /api/federated/model/update).

Tests N concurrent model update submissions and reports throughput and latency.
Results saved to federated/results/load_test.json.

Run from backend/:
    python3 federated/load_test.py
or inside Docker:
    docker exec -it culturequest_backend python3 federated/load_test.py
"""
import asyncio, httpx, time, json, os, statistics

BASE_URL      = os.environ.get("BASE_URL", "http://localhost:8000")
TEST_EMAIL    = "loadtest@example.com"
TEST_PASSWORD = "loadtest123"
RESULTS_DIR   = os.path.join(os.path.dirname(__file__), "results")
CONCURRENCY_LEVELS = [1, 5, 10, 20]


async def get_or_create_token(client: httpx.AsyncClient) -> str:
    r = await client.post("/api/auth/login",
        json={"email": TEST_EMAIL, "password": TEST_PASSWORD})
    if r.status_code == 200:
        return r.json()["access_token"]
    r = await client.post("/api/auth/register", json={
        "email": TEST_EMAIL, "password": TEST_PASSWORD,
        "name": "Load Test", "interests": ["art", "history"],
    })
    r.raise_for_status()
    return r.json()["access_token"]


async def get_global_model(client: httpx.AsyncClient) -> tuple[int, list]:
    r = await client.get("/api/federated/model/global")
    r.raise_for_status()
    d = r.json()
    return d["round"], d["weights"]


async def _one_update(client: httpx.AsyncClient, token: str,
                      round_num: int, weights: list) -> dict:
    t0 = time.perf_counter()
    try:
        r = await client.post(
            "/api/federated/model/update",
            json={"round": round_num, "weights": weights, "num_samples": 50},
            headers={"Authorization": f"Bearer {token}"},
            timeout=20.0,
        )
        lat = time.perf_counter() - t0
        ok  = r.status_code == 200
        return {"ok": ok, "latency": lat,
                "error": None if ok else r.json().get("detail", r.text)[:120]}
    except Exception as e:
        return {"ok": False, "latency": time.perf_counter() - t0, "error": str(e)}


async def run_batch(n: int, token: str, round_num: int, weights: list) -> dict:
    async with httpx.AsyncClient(base_url=BASE_URL) as client:
        t0      = time.perf_counter()
        results = await asyncio.gather(*[
            _one_update(client, token, round_num, weights) for _ in range(n)
        ])
        total = time.perf_counter() - t0

    ok  = [r for r in results if r["ok"]]
    err = [r for r in results if not r["ok"]]
    lat = sorted(r["latency"] for r in results)

    print(f"\n  [{n:>2} cereri simultane]")
    print(f"    Timp total : {total:.2f}s")
    print(f"    Succes     : {len(ok)}/{n}")
    print(f"    Throughput : {n / total:.1f} req/s")
    print(f"    Latență avg: {statistics.mean(lat)*1000:.0f}ms")
    print(f"    Latență p95: {lat[max(0, int(len(lat)*0.95)-1)]*1000:.0f}ms")
    if err:
        print(f"    Erori ({len(err)}): {err[0]['error']}")

    return {
        "n_concurrent"    : n,
        "success"         : len(ok),
        "errors"          : len(err),
        "total_seconds"   : round(total, 3),
        "throughput_rps"  : round(n / total, 2),
        "latency_mean_ms" : round(statistics.mean(lat) * 1000, 1),
        "latency_p95_ms"  : round(lat[max(0, int(len(lat)*0.95)-1)] * 1000, 1),
        "error_sample"    : err[0]["error"] if err else None,
    }


async def main():
    print(f"=== CultureQuest FL Load Test  ({BASE_URL}) ===")
    os.makedirs(RESULTS_DIR, exist_ok=True)

    async with httpx.AsyncClient(base_url=BASE_URL) as client:
        print("\nAutentificare...")
        token = await get_or_create_token(client)
        print("  token obținut")

        print("Se preia modelul global...")
        round_num, weights = await get_global_model(client)
        print(f"  round={round_num}, layers={len(weights)}")

    all_results = []
    for n in CONCURRENCY_LEVELS:
        result = await run_batch(n, token, round_num, weights)
        all_results.append(result)
        await asyncio.sleep(0.5)

    out = os.path.join(RESULTS_DIR, "load_test.json")
    with open(out, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\nRezultate salvate în {out}")


if __name__ == "__main__":
    asyncio.run(main())
