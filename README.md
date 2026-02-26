# HySP — Hybrid Service Platform

HySP 是一個以 Go 為核心驅動、具備多租戶隔離與微前端架構的混合服務平台。

## Repos

| Repo | 說明 | GitHub |
|------|------|--------|
| **hysp** | Workspace（本 repo）：平台規範、服務文件 | `robert7528/hysp` |
| **hyadmin-api** | 管理端 Go 後端 API | `robert7528/hyadmin-api` |
| **hyadmin-ui** | 管理端 Next.js 前端 Admin Shell | `robert7528/hyadmin-ui` |

## Services

### hyadmin-api

Go backend，提供租戶管理、模組 registry、業務資料 API。

- Port: `8080`
- Nginx: `https://your-domain/hyadmin-api/`
- 多租戶 DB：GORM + dbresolver，支援 database / schema 兩種隔離模式
- DB 版控：Atlas（`migrations/admin/`、`migrations/tenant/`）

### hyadmin-ui

Next.js Admin Shell，動態載入各微前端子應用。

- Port: `3000`
- Nginx: `https://your-domain/hyadmin/`
- basePath: `/hyadmin`
- Sidebar 從 hyadmin-api `GET /api/v1/modules` 取模組清單
- 子應用透過 micro-app 掛載

## Tech Stack

| 層次 | 技術 |
|------|------|
| Backend | Go · uber-go/fx · Gin · Cobra/Viper · zap |
| Database | PostgreSQL · GORM · dbresolver · Atlas |
| Frontend | Next.js 15 · React 19 · HeroUI · Shadcn/ui · Tailwind · micro-app |
| Runtime | Bun |
| Deploy | Podman Quadlet · systemctl · nginx |

## Deploy

```bash
# hyadmin-api（含 DB migration + nginx）
sudo bash /hysp/hyadmin-api/deployment/deploy.sh

# hyadmin-ui（NEXT_PUBLIC_API_URL 若有變更先 export）
export NEXT_PUBLIC_API_URL=https://your-domain/hyadmin-api
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

- 禁止 `Ant Design`、`iframe`、`logrus`、提交 `node_modules` / `.env`
- Frontend 使用 `bun install`，禁止產生 `package-lock.json`
- 容器基於 `oven/bun:alpine` 構建
