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

### Frontend
- **Runtime**: `Bun` (取代 Node.js 進行所有安裝、構建與測試)。
- **框架**: `Vite` + `React` + `React Router v7`（純 SPA，無 SSR）。
- **表單**: `TanStack Form` (輕量/AI 載體), `Formily v2` (複雜聯動)。
- **UI 組件**: `@hysp/ui-kit`（Shadcn/ui + Tailwind CSS，見 5.8 共用層）。
- **微前端**: `wujie-react`（iframe 模式，見 5.14 微前端架構決策）。

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
- 前端使用 Vite 構建，`bun run build` 輸出靜態檔到 `dist/`。
- 容器部署使用 `nginx:alpine` 提供靜態檔 + SPA fallback。

### 容器與部署規範
- 前端容器鏡像：`oven/bun:alpine`（build）+ `nginx:alpine`（runtime）。
- Podman 構建時應標註版本號並符合 OCI 標準。
- K8S 配置應定義 `resources.limits` 與 `readinessProbe`。

## 4. 排除名單 (Red-Light List)
- 不使用裸 `iframe`（由 wujie-react 微前端框架管理）。
- 不使用 `logrus` 或 `fmt.Print`。
- 不提交 `node_modules` 或 `.env` 敏感資料。

## 5. 架構決策 (Architecture Decisions)

### 5.1 方案 D：按技術棧分離
- **API 與 UI 完全分離**：Go (Backend) 與 Vite+React (Frontend) 各自獨立 Repo。
- **理由**：Containerfile 環境隔離（`golang:alpine` vs `oven/bun:alpine`）、UI 變動頻率遠高於 API、micro-app 天然需要獨立部署。

### 5.2 模組 Repo 命名規則
每個模組最多 3 個 Repo，命名規則固定，按需建立：

| 後綴 | 角色 | 技術棧 | 範例 |
|--|--|--|--|
| `-api` | 前後台 API（路由分層，單一 image） | 純 Go | `hycert-api` |
| `-ui` | 後台 UI（wujie 子應用，掛載於 hyadmin-ui） | Vite+React/Bun | `hycert-ui` |
| `-pui` | 前台 UI（Portal/Public，面向用戶） | Vite+React/Bun | `hysso-pui` |

- 有前台+後台：建 3 個（`-api` + `-ui` + `-pui`）
- 只有後台：建 2 個（`-api` + `-ui`）
- 只有前台：建 2 個（`-api` + `-pui`）

### 5.3 平台中控台：hyadmin
HySP Console 是 HySP 平台的管理介面，由 hyadmin 實作。負責租戶管理、模組管理、系統設定，並作為 wujie 微前端 Shell 掛載各模組的 `-ui`。維持現有命名不改名。

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
| `hyui-kit` | npm 共用套件（`@hysp/ui-kit`） | Shadcn/ui 元件、Tailwind preset、hooks、create-fetch |

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

#### 前端：`hyui-kit`（獨立 Repo，npm 套件）
- **定位**：前端共用套件，對應後端 `hycore`。Repo 名稱 `hyui-kit`，npm 套件名 `@hysp/ui-kit`。
- **內容**：全部 Shadcn/ui 元件、Tailwind preset（基礎色彩，不含 sidebar）、globals.css、cn() helper、useLocale hook、i18n 型別框架、createApiFetch factory、PLATFORM_COOKIE_KEYS 常數。
- **引用**：`bun add @hysp/ui-kit`；本地開發用 `bun link @hysp/ui-kit`。
- **輸出格式**：TypeScript + JSX 原始碼，tsup 打包 ESM/CJS + d.ts，不 bundle CSS（Tailwind class 需由消費端掃描）。
- **版本管理**：Semantic Versioning，已驗收的 App 可鎖版。
- **職責邊界**：不放業務元件、業務翻譯、環境變數、路由邏輯、API endpoint 路徑。
- **詳細規範**：見 `D:\HySP-Temp\Spec\hysp-ui-kit-claude-spec-v3.md`。
- **狀態**：待建立（從 hyadmin-ui 抽取）。
- **架構定案**：獨立套件模式（對應 hycore），不採 monorepo。各模組 UI 獨立 repo、獨立部署。

### 5.9 i18n 多語架構

#### Key 命名規範（四層結構）
```
{module}.{page}.{block}.{type}
```
- `module`：模組名稱（`hycert` / `hyadmin` / `shared`）
- `page`：頁面名稱 / `common`（模組內跨頁共用）
- `block`：頁面內區塊
- `type`：具體 key（`title` / `label-{name}` / `button-{name}` / `error-{name}` 等）
- 保留字：`shared`（跨模組共用）、`common`（模組內跨頁共用）
- 範例：`hycert.cert-list.header.title`、`shared.common.action.confirm`

#### 多租戶資料分層
```
Layer 1：各模組靜態 JSON    ← 打包進 App，隨版本更新，零 latency
Layer 2：DB 租戶覆蓋        ← 管理員手動設定，優先級最高
```
- DB 表：`i18n_messages`（tenant_id + module + locale + key → value）
- `tenant_id = '__default__'` 為平台預設，各租戶只覆蓋有差異的 key
- 快取鏈：DB → Redis（Go API 層）→ UI 層 local cache（TTL 5 分鐘）

#### 演進步驟
| 步驟 | 時機 | 內容 |
|--|--|--|
| **A** | 建 hyui-kit 時 | 統一 key 命名規範，改現有 hyadmin-ui + hycert-ui 翻譯 |
| **B** | A 完成後 | 建 `i18n_messages` DB schema（預留，不急實作 API） |
| **C** | 有租戶需要覆蓋翻譯時 | 實作 Go API + Redis cache + UI 層 cache 整合 |

#### 詳細規範
見 `D:\HySP-Temp\Spec\hysp-ui-kit-claude-spec-v3.md` Section 3.6。

### 5.10 數據契約
- **現階段**：手寫 TypeScript type。
- **中長期**：Go Struct → OpenAPI spec → Zod schema 自動生成。

### 5.11 術語定義

| 術語 | 意思 | 英文 |
|--|--|--|
| 前台 | 使用者操作的（Portal） | Portal / User-facing |
| 後台 | 管理者操作的（Admin） | Admin / Back-office |
| 前端 | 瀏覽器端程式（UI） | Frontend |
| 後端 | 伺服器端程式（API） | Backend |

口語簡稱：前台 UI、前台 API、後台 UI、後台 API。

### 5.12 模組開發流程
新增模組時須執行以下步驟：
1. **功能盤點**：列出所有功能需求
2. **耦合度分析**：判斷哪些功能一定會一起改動，決定拆成幾個模組
3. **命名與 Slug**：依命名規則（`hy{模組}-api` / `-ui` / `-pui`）命名，指定 URL slug
4. **Repo 建立**：按需建立（有前台+後台建 3 個，只有後台建 2 個）
5. **模組註冊**：向 hyadmin 註冊 slug、顯示名稱、選單（含掛載 hyconf/hyiam/hylog）
6. **依賴宣告**：宣告依賴的基礎模組（hyconf、hyiam、hylog 等）

### 5.13 微前端架構決策

#### 方案選定：wujie iframe 模式
- **框架**：`wujie-react`（騰訊無界微前端）
- **模式**：iframe（物理隔離，每個子應用獨立 window）
- **父應用**：hyadmin-ui（Vite + React Router v7），作為 Shell 掛載子應用

#### 為什麼選 wujie
- 原使用 micro-app，但與 Vite ESM 輸出不相容（`new Function()` 包裝問題）
- wujie 原生支援 iframe 隔離，與 Vite 完全相容
- 子應用只需提供 `__WUJIE_MOUNT` / `__WUJIE_UNMOUNT` 生命週期

#### iframe 模式的已知限制與對策

| 限制 | 目前影響 | 對策 |
|--|--|--|
| 高度自適應 | **有** — 子應用內容動態變高 | 子應用 `ResizeObserver` → `postMessage` → 父應用調整容器高度 |
| 全域彈窗遮罩 | 暫無（工具箱未用 Dialog） | 未來需要時透過 `postMessage` 橋接父應用彈窗 |
| 前進/後退 | 無 — wujie iframe 模式內建路由同步 | 已內建 |
| 資源重複載入 | 暫無（一次一個子應用） | HTTP 快取優化 + 切換時銷毀 iframe |

#### 架構演進記錄
- 2026-03-18：POC 驗證 micro-app iframe + Next.js（成功但有 SSR 相容問題）
- 2026-03-18：遷移至 wujie-react + Vite（hycert-ui 先行，hyadmin-ui 隨後）

### 5.14 演進路線圖

| 階段 | 時機 | 核心任務 |
|--|--|--|
| **第一階段** | 完成 | 專注 `hyadmin-api` + `hyadmin-ui` |
| **第二階段** | 進行中 | 建立 `hycore`（✅ 已完成 v0.1.0）、建立 `hyui-kit`（進行中）、建立 `hycert` 模組（✅ hycert-api + hycert-ui） |
| **第三階段** | hyui-kit 穩定後 | 統一 i18n key 命名規範、建 i18n_messages DB schema |
| **第四階段** | API 穩定後 | 導入 affected-only build、Go → OpenAPI → Zod 自動化 |
| **第五階段** | 多模組穩定運行後 | 導入 SBOM 前端掃描、共用元件視覺測試（Storybook） |

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
| **Port** | 8080 | 80 (nginx in container) |
| **Nginx** | `/hub/`（trailing slash 剝離前綴） | `/hyadmin/`（反向代理到容器 nginx，SPA fallback） |
| **Quadlet** | `/etc/containers/systemd/hyadmin-api.container` | `/etc/containers/systemd/hyadmin-ui.container` |
| **Env file** | `/etc/hyadmin/api.env` | 無（stateless，靜態檔由 nginx 提供） |

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
- Vite 6 + React Router v7；`base: '/hyadmin/'`；`basename="/hyadmin"`
- Shadcn/ui (Sidebar + layout) + wujie-react 微前端
- Sidebar 從 `GET /api/v1/modules` 動態載入模組；`/app/:route/*` 掛載子應用
- 純 SPA，無環境變數，一份 image 通用所有環境

#### 部署
```bash
# API（含 migrate + nginx）
sudo bash /hysp/hyadmin-api/deployment/deploy.sh

# UI（無需設環境變數，image 通用）
sudo bash /hysp/hyadmin-ui/deployment/deploy.sh
```

### hycert — 憑證管理模組

| | hycert-api | hycert-ui |
|--|------------|-----------|
| **GitHub** | `robert7528/hycert-api` | `robert7528/hycert-ui` |
| **本地** | `D:\HySP\hycert-api\` | `D:\HySP\hycert-ui\` |
| **Linux** | `/hysp/hycert-api/` | `/hysp/hycert-ui/` |
| **Slug** | `cert` | `cert` |
| **Port** | 8082 | 3002 |
| **Nginx** | `/hycert-api/`（trailing slash 剝離前綴） | `/hycert-ui`（反向代理到容器 nginx，SPA fallback） |
| **Quadlet** | `/etc/containers/systemd/hycert-api.container` | `/etc/containers/systemd/hycert-ui.container` |
| **Env file** | `/etc/hycert/api.env` | 無（stateless） |

#### hycert-api 重點
- Go module: `github.com/hysp/hycert-api`
- DI: `uber-go/fx`；HTTP: Gin；CLI: Cobra
- **無 DB**：純工具型 API（憑證解析/轉換/驗證）
- **Auth**：JWT 驗證（共用 hyadmin-api 的 JWT_SECRET）
- **格式支援**：PEM、DER、PFX/PKCS#12、JKS（keystore-go/v4）、P7B/PKCS#7（smallstep/pkcs7）
- **鏈驗證**：AIA chasing + AKID/SKID + SystemCertPool

#### hycert-ui 重點
- Vite 6 + React；`base: '/hycert-ui/'`
- 以 wujie-react 掛載於 hyadmin-ui Shell
- Auth：讀取 hyadmin 的 cookie（`hyadmin_token`），共用同域
- i18n：獨立 locale（zh-TW/en），讀取 `hyadmin_locale` localStorage
- **模組註冊**：在 hyadmin 中設定 `route: 'cert'`, `url: 'https://domain/hycert-ui'`, `api_url: '/hycert-api'`

#### 部署
```bash
# API
sudo bash /hysp/hycert-api/deployment/deploy.sh

# UI
sudo bash /hysp/hycert-ui/deployment/deploy.sh
```

## 8. 開發與測試環境

### 開發環境
- **作業系統**: Windows 11
- **語言/Runtime**: Go 1.26, Bun
- **IDE**: VSCode (Multi-root Workspace)
- **CLI 工具**: GitHub CLI (`gh`)——用於查看 CI log（`gh run view --log-failed`）、管理 PR/Issue

### CI/CD 流程
```
Windows 本機開發 → Push GitHub → GitHub Actions 建構 Container Image → 部署到測試環境
```

### 測試環境
| 主機 | IP | 用途 |
|--|--|--|
| 應用伺服器 | 10.30.0.70 | Nginx + Podman 容器 |
| 資料庫伺服器 | 10.30.0.69 | PostgreSQL |