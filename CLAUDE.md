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
- **UI 組件**: `Shadcn/ui` (含 Sidebar/Breadcrumb/Navigation), `Tailwind CSS`。
- **微前端**: `micro-app` (子應用掛載)。

### DevOps & Infrastructure
- **容器化**: `Podman` (Rootless 容器管理), `Containerfile` (OCI 規範)。
- **編排**: `Kubernetes` (K8S), `Helm` (配置管理)。

## 3. 代碼與運維規範
### Golang 規範
- 構造函數須符合 `fx` 模式：`func NewService(lc fx.Lifecycle, ...) (*Service, error)`。
- 不使用 `go func`，須使用 `GoSafe` 防止 Panic。
- 日誌使用 `uber-go/zap`。

### Bun & Frontend 規範
- 使用 `bun install` 管理依賴，不使用 `package-lock.json`。
- Next.js 運行時應盡可能使用 `bun --bun next` 以提升效能。
- 靜態檢查：應通過 `bun x next lint`。

### 容器與部署規範
- 容器鏡像應基於 `oven/bun:alpine` 進行構建。
- Podman 構建時應標註版本號並符合 OCI 標準。
- K8S 配置應定義 `resources.limits` 與 `readinessProbe`。

## 4. 排除名單 (Red-Light List)
- 不使用 `iframe` (由 micro-app 替代)。
- 不使用 `logrus` 或 `fmt.Print`。
- 不提交 `node_modules` 或 `.env` 敏感資料。

## 5. 架構決策 (Architecture Decisions)

### 5.1 方案 D：按技術棧分離
- **API 與 UI 完全分離**：Go (Backend) 與 Next.js (Frontend) 各自獨立 Repo。
- **理由**：Containerfile 環境隔離（`golang:alpine` vs `oven/bun:alpine`）、UI 變動頻率遠高於 API、micro-app 天然需要獨立部署。

### 5.2 模組 Repo 命名規則
每個模組最多 3 個 Repo，命名規則固定，按需建立：

| 後綴 | 角色 | 技術棧 | 範例 |
|--|--|--|--|
| `-api` | 前後台 API（路由分層，單一 image） | 純 Go | `hycert-api` |
| `-ui` | 後台 UI（micro-app，掛載於 hyadmin-ui） | 純 Next.js/Bun | `hycert-ui` |
| `-pui` | 前台 UI（Portal/Public，面向用戶） | 純 Next.js/Bun | `hysso-pui` |

- 有前台+後台：建 3 個（`-api` + `-ui` + `-pui`）
- 只有後台：建 2 個（`-api` + `-ui`）
- 只有前台：建 2 個（`-api` + `-pui`）

### 5.3 平台中控台：hyadmin
HySP Console 是 HySP 平台的管理介面，由 hyadmin 實作。負責租戶管理、模組管理、系統設定，並作為微前端 Shell 掛載各模組的 `-ui`。維持現有命名不改名。

| Repo | 角色 | Slug |
|--|--|--|
| `hyadmin-api` | 中控台 API | `hub` |
| `hyadmin-ui` | 中控台 Shell（掛載各模組 -ui） | `hub` |

### 5.4 模組分層

#### 平台層（必裝）

| 模組 | Slug | 功能 |
|--|--|--|
| `hyadmin` | `hub` | 中控台 Shell、租戶管理、模組管理 |
| `hysso` | `sso` | 認證（JWT/SSO/OAuth/SAML）+ 身份管理（使用者檔/管理者檔/帳密綁定） |
| `hyiam` | `iam` | 授權 / 權限管理（Casbin policy、角色管理，可掛載到各模組選單 `?module=xxx`） |
| `hyconf` | `conf` | 通用參數管理（可掛載到各模組選單 `?module=xxx`） |
| `hylog` | `log` | 操作日誌（可掛載到各模組選單 `?module=xxx`） |

#### 共用層（程式碼，非服務）

| 名稱 | 性質 | 說明 |
|--|--|--|
| `hycore` | Go 共用 module | middleware、DB、logger、config、fx module |
| `hyviews` | Bun Workspace monorepo | 前端共用元件/hooks + 各模組 UI app |

#### 業務層（按需安裝）
- `hycert`（憑證管理）、`hypmis`（專案管理）等，依客戶需求選裝。

#### 跨模組掛載機制
基礎模組（hyconf、hyiam、hylog）可掛載到任何業務模組的選單下，用 query parameter 過濾：
```
/conf/settings?module=hycert    ← 只顯示 hycert 的參數
/iam/roles?module=hycert        ← 只顯示 hycert 的權限
/log/audit?module=hycert        ← 只顯示 hycert 的日誌
```

### 5.5 API 路由分層
單一 API 服務內，以路徑區分前後台與共用：

```
/{slug}/api/v1/adm/...         ← 後台 API（adminAuth + casbin middleware）
/{slug}/api/v1/pub/...         ← 前台 API（userAuth middleware）
/{slug}/api/v1/...             ← 共用 API（基本 auth middleware）
```

- 各層掛不同 middleware group 控制權限。
- `{slug}` 為模組可讀短名稱，由 Gateway/Nginx strip 後轉發。
- 應用程式碼內部統一使用 `/api/v1/...`，不含 slug（部署環境無關）。

### 5.6 多租戶 URL 識別
三種方式並存，由 middleware 按優先順序解析：
1. **獨立域名**（大客戶）：Gateway 查域名對照表
2. **子域名**（中型客戶）：`tenant.hysp.com`，DNS wildcard
3. **Header**（小客戶/SaaS）：`X-Tenant-ID`

路徑結構不含 tenant，保持乾淨。

### 5.7 部署策略
- **一份 image，全部路由都載入**，由 Gateway/Nginx 控制暴露面。
- Go 編譯為靜態二進位，未用到的路由不佔資源，無需拆 image 或做啟動模式切換。
- 支援 Podman（單主機，小客戶）與 K8S（多主機，大客戶），應用程式碼不感知部署環境。

| 部署情境 | 做法 |
|--|--|
| 同網段 | API 一份 + Gateway 過濾路由 |
| 網段隔離 | 同 image 各放一份，Nginx 各自設定開放路由，DB DSN 各自設定 |

Gateway 路由規則（Podman Nginx / K8S Ingress 皆適用）：
```
/{slug}/* → strip /{slug} → 轉發至對應的 API 服務
```

### 5.8 共用層詳細

#### 後端：`hycore`（獨立 Repo）
- **定位**：Go 共用 module，統一管控第三方套件版本。
- **內容**：middleware（tenant, auth, casbin）、DBManager、logger (zap)、response 格式、config (viper)、fx module。
- **引用**：`go get github.com/robert7528/hycore`；本地開發用 `go.mod replace => ../hycore`，CI 擋 replace 進 main。
- **資安驅動**：SBOM 與第三方套件 CVE 掃描集中管控，避免各模組版本落差。
- **狀態**：已從 hyadmin-api 抽取完成，tagged v0.1.0。

#### 前端：`hyviews`（Bun Workspace Monorepo）
- **定位**：所有 UI 的 monorepo，開發單體化、運行微服務化。
- **結構**：`packages/ui-shared`（共用元件/hooks）+ `apps/*`（各模組 UI，各自建 container image）。
- **引用**：Workspace 內直接 import，無需發版。
- **CI**：affected-only build（只改 ui-shared 才觸發全部重建）。
- **建立時機**：第二個 UI 模組開始開發時，從 hyadmin-ui 抽取。

### 5.9 數據契約
- **現階段**：手寫 TypeScript type。
- **中長期**：Go Struct → OpenAPI spec → Zod schema 自動生成。

### 5.10 術語定義

| 術語 | 意思 | 英文 |
|--|--|--|
| 前台 | 使用者操作的（Portal） | Portal / User-facing |
| 後台 | 管理者操作的（Admin） | Admin / Back-office |
| 前端 | 瀏覽器端程式（UI） | Frontend |
| 後端 | 伺服器端程式（API） | Backend |

口語簡稱：前台 UI、前台 API、後台 UI、後台 API。

### 5.11 模組開發流程
新增模組時須執行以下步驟：
1. **功能盤點**：列出所有功能需求
2. **耦合度分析**：判斷哪些功能一定會一起改動，決定拆成幾個模組
3. **命名與 Slug**：依命名規則（`hy{模組}-api` / `-ui` / `-pui`）命名，指定 URL slug
4. **Repo 建立**：按需建立（有前台+後台建 3 個，只有後台建 2 個）
5. **模組註冊**：向 hyadmin 註冊 slug、顯示名稱、選單（含掛載 hyconf/hyiam/hylog）
6. **依賴宣告**：宣告依賴的基礎模組（hyconf、hyiam、hylog 等）

### 5.12 演進路線圖

| 階段 | 時機 | 核心任務 |
|--|--|--|
| **第一階段** | 現在 | 專注 `hyadmin-api` + `hyadmin-ui` |
| **第二階段** | 第二個模組開工 | 建立 `hycore`（從 hyadmin-api 抽取）、建立 `hyviews`（從 hyadmin-ui 遷入） |
| **第三階段** | API 穩定後 | 導入 affected-only build、Go → OpenAPI → Zod 自動化 |

## 6. 開發工作流
1. **規劃**: `/plan` 生成設計，包含 Zod Schema 與 Go Struct。
2. **開發**: 使用 Bun 執行測試，使用 Podman 驗證容器兼容性。
3. **安全**: 執行 `/secure-audit` 檢查 Tink 加密與 K8S 安全配置。

---

## 7. 已建立服務

### hyadmin — HySP Console（中控台）

| | hyadmin-api | hyadmin-ui |
|--|-------------|------------|
| **GitHub** | `robert7528/hyadmin-api` | `robert7528/hyadmin-ui` |
| **本地** | `D:\HySP\hyadmin-api\` | `D:\HySP\hyadmin-ui\` |
| **Linux** | `/hysp/hyadmin-api/` | `/hysp/hyadmin-ui/` |
| **Slug** | `hub` | `hub` |
| **Port** | 8080 | 3000 |
| **Nginx** | `/hub/`（trailing slash 剝離前綴） | `/hyadmin/`（不剝離，Next.js basePath） |
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
- Shadcn/ui (Sidebar + layout) + micro-app 微前端
- Sidebar 從 `GET /api/v1/modules` 動態載入模組；`/app/[...route]` 掛載子應用
- `NEXT_PUBLIC_*` 為 **build-time** 變數，需 `--build-arg` 傳入

#### 部署
```bash
# API（含 migrate + nginx）
sudo bash /hysp/hyadmin-api/deployment/deploy.sh

# UI（API URL 若有變更先 export）
export NEXT_PUBLIC_API_URL=https://your-domain/hub
sudo bash /hysp/hyadmin-ui/deployment/deploy.sh
```

## 8. 開發與測試環境

### 開發環境
- **作業系統**: Windows 11
- **語言/Runtime**: Go, Bun
- **IDE**: VSCode (Multi-root Workspace)

### CI/CD 流程
```
Windows 本機開發 → Push GitHub → GitHub Actions 建構 Container Image → 部署到測試環境
```

### 測試環境
| 主機 | IP | 用途 |
|--|--|--|
| 應用伺服器 | 10.30.0.70 | Nginx + Podman 容器 |
| 資料庫伺服器 | 10.30.0.69 | PostgreSQL |