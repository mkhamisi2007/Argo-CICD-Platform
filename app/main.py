import os

from fastapi import FastAPI
from prometheus_fastapi_instrumentator import Instrumentator

APP_VERSION = os.getenv("APP_VERSION", "0.1.0")

app = FastAPI(title="argo-cicd-app")


@app.get("/")
def read_root():
    return {"status": "ok", "version": APP_VERSION}


@app.get("/health")
def health():
    return {"healthy": True}


Instrumentator().instrument(app).expose(app, endpoint="/metrics")
