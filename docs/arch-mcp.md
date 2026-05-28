# Форк arch-ops-server с авторизацией

## Оригинальный репозиторий

- **URL:** `github.com/nihalxkumar/arch-mcp`
- **Версия:** 3.4.0
- **Путь к исходникам:** `src/arch_ops_server/`
- **pyproject.toml:** `uv_build`, entrypoints `arch-ops-server` (STDIO) и `arch-ops-server-http` (HTTP)
- **HTTP зависимость:** `[project.optional-dependencies] http = ["starlette>=0.27.0", "uvicorn[standard]>=0.23.0"]`

## Что меняем в форке

### 1. `src/arch_ops_server/http_server.py`

#### 1a. `run_http_server()` — читать хост из env

Сейчас строка 809 (функция `run_http_server`):

```python
async def run_http_server(host: str = "0.0.0.0", port: int = 8080) -> None:
    port = int(os.getenv("PORT", port))
```

Изменить на:

```python
async def run_http_server(host: str = "0.0.0.0", port: int = 8080) -> None:
    host = os.getenv("ARCH_OPS_SERVER_BIND", host)
    port = int(os.getenv("PORT", port))
```

#### 1b. `create_app()` — добавить auth middleware

Добавить middleware после `CORS` (строка ~770, после `create_app()`).

```python
import os
_API_KEY = os.environ.get("ARCH_OPS_SERVER_API_KEY")

if _API_KEY:

    @app.middleware("http")
    async def auth_middleware(request: Request, call_next):
        if request.method == "OPTIONS":
            return await call_next(request)
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer ") or auth.removeprefix("Bearer ") != _API_KEY:
            from starlette.responses import Response
            import json
            return Response(
                content=json.dumps({
                    "jsonrpc": "2.0",
                    "error": {"code": -32001, "message": "Unauthorized"},
                    "id": None
                }),
                status_code=401,
                headers={"Content-Type": "application/json"},
            )
        return await call_next(request)
```

### 2. `pyproject.toml` — версия (опционально)

```toml
version = "3.4.0-auth"
```

## Сборка и установка из форка

```bash
# Установка через uv tool
uv tool install git+https://github.com/YOUR_ORG/arch-mcp

# Или с HTTP extras
uv tool install "arch-ops-server[http]" --from git+https://github.com/YOUR_ORG/arch-mcp
```

## Использование в билд-пайплайне

### `firstboot.sh`

```bash
uv tool install "arch-ops-server[http]" --from git+https://github.com/YOUR_ORG/arch-mcp
```

### `arch-ops-mcp.service`

```ini
[Unit]
Description=Arch Linux MCP HTTP Server
After=network.target

[Service]
Type=simple
EnvironmentFile=/etc/arch-ops-mcp/env
ExecStart=/root/.local/bin/arch-ops-server-http
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### `/etc/arch-ops-mcp/env`

```
ARCH_OPS_SERVER_BIND=0.0.0.0
ARCH_OPS_SERVER_API_KEY=<сгенерированный uuid>
```

## opencode.json

```json
{
  "arch-linux": {
    "type": "remote",
    "url": "http://192.168.1.54:8080/mcp",
    "headers": {
      "Authorization": "Bearer {env:ARCH_OPS_API_KEY}"
    },
    "timeout": 30000
  }
}
```

API-ключ хранить в `~/.config/opencode/env` (или в переменной окружения `ARCH_OPS_API_KEY`).
