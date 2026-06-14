from fastapi.testclient import TestClient

from main import app

client = TestClient(app)


def test_root():
    response = client.get("/")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "version" in body


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"healthy": True}


def test_metrics():
    response = client.get("/metrics")
    assert response.status_code == 200
