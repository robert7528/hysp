# HySP — Hybrid Service Platform

HySP 是一個以 Go 為核心驅動、具備多租戶隔離與微前端架構的混合服務平台。

## Repos

| Repo | 說明 | GitHub |
|------|------|--------|
| **hysp** | Workspace（本 repo）：平台規範、服務文件 | `robert7528/hysp` |
| **hyadmin-api** | 管理端 Go 後端 API | `robert7528/hyadmin-api` |
| **hyadmin-ui** | 管理端前端 Admin Shell（Vite + React） | `robert7528/hyadmin-ui` |
| **hycert-api** | 憑證管理模組 Go 後端 API | `robert7528/hycert-api` |
| **hycert-ui** | 憑證管理模組前端（Vite + React） | `robert7528/hycert-ui` |

## Services

### hyadmin-api

Go backend，提供租戶管理、模組 registry、業務資料 API。

- Port: `8080`
- Nginx: `https://your-domain/hyadmin-api/`
- 多租戶 DB：GORM + dbresolver，支援 database / schema 兩種隔離模式
- DB 版控：Atlas（`migrations/admin/`、`migrations/tenant/`）

### hyadmin-ui

Vite + React Router v7 Admin Shell，動態載入各 wujie 微前端子應用。

- Port: `80`（容器內 nginx）
- Nginx: `https://your-domain/hyadmin/`
- basename: `/hyadmin`
- Sidebar 從 hyadmin-api `GET /api/v1/modules` 取模組清單
- 子應用透過 wujie-react 掛載

## Tech Stack

| 層次 | 技術 |
|------|------|
| Backend | Go · uber-go/fx · Gin · Cobra/Viper · zap |
| Database | PostgreSQL · GORM · dbresolver · Atlas |
| Frontend | Vite 6 · React 19 · React Router v7 · Shadcn/ui · Tailwind · wujie-react |
| Runtime | Bun |
| Deploy | Podman Quadlet · systemctl · nginx |

## Deploy

```bash
# hyadmin-api（含 DB migration + nginx）
sudo bash /hysp/hyadmin-api/deployment/deploy.sh

# hyadmin-ui（無需設環境變數，image 通用）
sudo bash /hysp/hyadmin-ui/deployment/deploy.sh
```

## Docs

服務的詳細開發規範見 `docs/`：

- [`docs/hyadmin-api/CLAUDE.md`](docs/hyadmin-api/CLAUDE.md)
- [`docs/hyadmin-ui/CLAUDE.md`](docs/hyadmin-ui/CLAUDE.md)

更新子 repo 的 CLAUDE.md 後執行同步：

```bash
bash scripts/sync-docs.sh
```

## Conventions

詳見 [`CLAUDE.md`](CLAUDE.md)。重點摘要：

- 禁止 `Ant Design`、裸 `iframe`、`logrus`、提交 `node_modules` / `.env`
- Frontend 使用 `bun install`，禁止產生 `package-lock.json`
- 前端容器：`oven/bun:alpine`（build）+ `nginx:alpine`（runtime）
