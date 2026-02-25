# HySP (Hybrid Service Platform) 開發規範

## 1. 專案定位與願景
HySP 是一個全 Go 驅動、具備國防級資安與 AI 自動化能力的混合服務平台。
- **目標**: 透過 AI Schema 驅動 Generative UI。
- **運行環境**: 支持 Podman (開發) 與 Kubernetes (生產)。
- **原則**: 租戶隔離、零信任架構、Framework Agnostic。

## 2. 完整技術棧 (Full Tech Stack)
### Backend (Golang)
- **架構**: `uber-go/fx` (DI), `Gin` (Web), `KrakenD` (Gateway), `Cobra/Viper` (CLI/Config)。
- **穩定性**: `go-zero/core` (mr, GoSafe, breaker), `x/sync/errgroup`。
- **資安**: `casbin` (RBAC/ABAC), `google/tink` (加密), `HashiCorp Vault` (KMS)。
- **資料庫**: `PostgreSQL` (JSONB), `Redis`, `GORM` (dbresolver), `ElasticSearch`。

### Frontend (Bun & Next.js)
- **Runtime**: `Bun` (取代 Node.js 進行所有安裝、構建與測試)。
- **框架**: `Next.js` (App Router), `React`。
- **表單**: `TanStack Form` (輕量/AI 載體), `Formily v2` (複雜聯動)。
- **UI 組件**: `Shadcn/ui`, `HeroUI` (佈局), `Tailwind CSS`。
- **微前端**: `micro-app` (子應用掛載)。

### DevOps & Infrastructure
- **容器化**: `Podman` (Rootless 容器管理), `Containerfile` (OCI 規範)。
- **編排**: `Kubernetes` (K8S), `Helm` (配置管理)。

## 3. 代碼與運維規範
### Golang 規範
- 構造函數須符合 `fx` 模式：`func NewService(lc fx.Lifecycle, ...) (*Service, error)`。
- 禁止直接使用 `go func`，須使用 `GoSafe` 防止 Panic。
- 日誌強制使用 `uber-go/zap`。

### Bun & Frontend 規範
- 使用 `bun install` 管理依賴，嚴禁產生 `package-lock.json`。
- Next.js 運行時應盡可能使用 `bun --bun next` 以提升效能。
- 靜態檢查：必須通過 `bun x next lint`。

### 容器與部署規範
- 容器鏡像必須基於 `oven/bun:alpine` 進行構建。
- Podman 構建時必須標註版本號並符合 OCI 標準。
- K8S 配置必須定義 `resources.limits` 與 `readinessProbe`。

## 4. 排除名單 (Red-Light List)
- 禁止使用 `Ant Design` (資安與政治風險)。
- 禁止使用 `iframe` (由 micro-app 替代)。
- 禁止在生產環境中使用 `logrus` 或 `fmt.Print`。
- 禁止提交 `node_modules` 或 `.env` 敏感資料。

## 5. 開發工作流
1. **規劃**: `/plan` 生成設計，包含 Zod Schema 與 Go Struct。
2. **開發**: 使用 Bun 執行測試，使用 Podman 驗證容器兼容性。
3. **安全**: 執行 `/secure-audit` 檢查 Tink 加密與 K8S 安全配置。

---

## 6. 已建立服務

### hyadmin — 管理端框架（Admin Shell）

| | hyadmin-api | hyadmin-ui |
|--|-------------|------------|
| **GitHub** | `robert7528/hyadmin-api` | `robert7528/hyadmin-ui` |
| **本地** | `D:\hysp\hyadmin-api\` | `D:\hysp\hyadmin-ui\` |
| **Linux** | `/hysp/hyadmin-api/` | `/hysp/hyadmin-ui/` |
| **Port** | 8080 | 3000 |
| **Nginx** | `/hyadmin-api/`（trailing slash 剝離前綴） | `/hyadmin/`（不剝離，Next.js basePath） |
| **Quadlet** | `/etc/containers/systemd/hyadmin-api.container` | `/etc/containers/systemd/hyadmin-ui.container` |
| **Env file** | `/etc/hyadmin/api.env` | build-arg（`NEXT_PUBLIC_*`） |

#### hyadmin-api 重點
- Go module: `github.com/hysp/hyadmin-api`
- DI: `uber-go/fx`；HTTP: Gin；CLI: Cobra；Config: Viper
- **多租戶 DB**：`TenantDBConfig` 存 admin DB；`DBManager` 懶載入 + 快取
  - `mode=database`：不同 DSN；`mode=schema`：同 PostgreSQL 不同 schema（auto `search_path`）
  - dbresolver 讀寫分離（`ReplicaDSNs` JSON array）
  - Handler 取 tenant DB：`middleware.GetTenantDB(c)`
- **DB 版控**：Atlas（`ariga.io/atlas` + `atlas-provider-gorm`）
  - `migrations/admin/`：admin DB（Tenant, TenantDBConfig）
  - `migrations/tenant/`：租戶業務 schema
  - `go run ./cmd/migrate admin|tenant --code X|all-tenants`

#### hyadmin-ui 重點
- Next.js 15 App Router；`basePath: '/hyadmin'`；`output: 'standalone'`
- HeroUI layout shell + Shadcn/ui + micro-app 微前端
- Sidebar 從 `GET /api/v1/modules` 動態載入模組；`/app/[...route]` 掛載子應用
- `NEXT_PUBLIC_*` 為 **build-time** 變數，需 `--build-arg` 傳入

#### 部署
```bash
# API（含 migrate + nginx）
sudo bash /hysp/hyadmin-api/deployment/deploy.sh

# UI（API URL 若有變更先 export）
export NEXT_PUBLIC_API_URL=https://your-domain/hyadmin-api
sudo bash /hysp/hyadmin-ui/deployment/deploy.sh
```