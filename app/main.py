import os

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
from prometheus_fastapi_instrumentator import Instrumentator

APP_VERSION = os.getenv("APP_VERSION", "0.1.0") 

app = FastAPI(title="argo-cicd-app")

HTML_PAGE = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>argo-cicd-app</title>
<style>
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: linear-gradient(135deg, #4f46e5 0%, #06b6d4 50%, #22c55e 100%);
    background-size: 200% 200%;
    animation: gradient-shift 12s ease infinite;
  }}
  @keyframes gradient-shift {{
    0% {{ background-position: 0% 50%; }}
    50% {{ background-position: 100% 50%; }}
    100% {{ background-position: 0% 50%; }}
  }}
  .card {{
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 20px;
    padding: 2.5rem 3rem;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.25);
    text-align: center;
    max-width: 420px;
    width: 90%;
  }}
  .logo {{ font-size: 3rem; line-height: 1; margin-bottom: 0.5rem; }}
  h1 {{ margin: 0.25rem 0; font-size: 1.75rem; color: #1e293b; }}
  .subtitle {{ color: #64748b; margin: 0 0 1.5rem; font-size: 0.95rem; }}
  .badge {{
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    background: #ecfdf5;
    color: #15803d;
    border: 1px solid #bbf7d0;
    border-radius: 999px;
    padding: 0.35rem 0.9rem;
    font-weight: 600;
    font-size: 0.9rem;
  }}
  .dot {{
    width: 0.55rem;
    height: 0.55rem;
    border-radius: 50%;
    background: #22c55e;
    animation: pulse 2s infinite;
  }}
  @keyframes pulse {{
    0% {{ box-shadow: 0 0 0 0 rgba(34, 197, 94, 0.6); }}
    70% {{ box-shadow: 0 0 0 8px rgba(34, 197, 94, 0); }}
    100% {{ box-shadow: 0 0 0 0 rgba(34, 197, 94, 0); }}
  }}
  table {{ width: 100%; margin-top: 1.75rem; border-collapse: collapse; font-size: 0.9rem; }}
  td {{ padding: 0.5rem 0; border-top: 1px solid #e2e8f0; text-align: left; color: #475569; }}
  td:last-child {{
    text-align: right;
    font-weight: 600;
    color: #1e293b;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }}
  .links {{ margin-top: 1.75rem; display: flex; gap: 0.75rem; justify-content: center; }}
  .links a {{
    flex: 1;
    text-decoration: none;
    color: #4f46e5;
    border: 1px solid #c7d2fe;
    border-radius: 10px;
    padding: 0.5rem 0;
    font-weight: 600;
    font-size: 0.85rem;
    transition: background 0.15s ease;
  }}
  .links a:hover {{ background: #eef2ff; }}
  footer {{ margin-top: 1.5rem; color: #94a3b8; font-size: 0.78rem; }}
</style>
</head>
<body>
  <div class="card">
    <div class="logo">🚀</div>
    <h1>argo-cicd-app</h1>
    <p class="subtitle">Deployed via Argo Workflows &amp; Argo Rollouts</p>
    <span class="badge"><span class="dot"></span> Status: ok</span>
    <table>
      <tr><td>Version</td><td>{APP_VERSION}</td></tr>
    </table>
    <div class="links">
      <a href="/health">/health</a>
      <a href="/metrics">/metrics</a>
      <a href="/docs">/docs</a>
    </div>
    <footer>Argo CI/CD Platform on EKS</footer>
  </div>
</body>
</html>
"""


@app.get("/")
def read_root(request: Request):
    if "text/html" in request.headers.get("accept", ""):
        return HTMLResponse(HTML_PAGE)
    return {"status": "ok", "version": APP_VERSION}


@app.get("/health")
def health():
    return {"healthy": True}


Instrumentator().instrument(app).expose(app, endpoint="/metrics")
