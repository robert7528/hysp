# hyadmin-ui

## Development Environment

- **Windows local**: Source code editing only. No Node/Bun runtime available.
- **GitHub**: `robert7528/hyadmin-ui`
- **Package manager**: Bun
- **Deploy**: Linux server (`/hysp/hyadmin-ui/`) via Podman Quadlet + systemctl.

## Project Structure

```
hyadmin-ui/
├── src/
│   ├── main.tsx                  # React DOM 掛載入口
│   ├── app.tsx                   # BrowserRouter + 路由定義
│   ├── globals.css               # Tailwind + CSS variables (Shadcn/ui theme)
│   ├── vite-env.d.ts             # Vite 型別宣告
│   ├── layouts/
│   │   ├── root-layout.tsx       # Providers wrapper (Outlet)
│   │   ├── shell-layout.tsx      # Header + Sidebar + Outlet
│   │   └── login-layout.tsx      # 置中 layout (Outlet)
│   ├── pages/
│   │   ├── home.tsx              # Dashboard 首頁
│   │   ├── login.tsx             # 登入頁
│   │   ├── profile.tsx           # 個人設定
│   │   ├── forbidden.tsx         # 403 頁面
│   │   ├── not-found.tsx         # 404 頁面
│   │   ├── app-page.tsx          # wujie 微前端動態路由
│   │   └── admin/                # 系統管理 CRUD 頁面
│   │       ├── users.tsx, users-new.tsx
│   │       ├── roles.tsx, roles-new.tsx, role-permissions.tsx
│   │       ├── modules.tsx, modules-new.tsx, module-edit.tsx
│   │       ├── feature-permissions.tsx
│   │       └── audit-logs.tsx
│   ├── components/
│   │   ├── auth-guard.tsx        # 客戶端認證守衛 (檢查 token → Outlet or redirect)
│   │   ├── providers.tsx         # LocaleProvider + PermissionProvider + ModuleProvider
│   │   ├── permission-guard.tsx  # 權限控制元件
│   │   ├── layout/
│   │   │   ├── header.tsx        # Top bar（module tabs + user menu）
│   │   │   ├── sidebar.tsx       # 左側選單（模組功能 / admin 選單）
│   │   │   ├── breadcrumb.tsx    # 麵包屑導航
│   │   │   └── footer.tsx
│   │   └── micro-app/
│   │       └── app-container.tsx # wujie-react 微前端容器
│   ├── contexts/
│   │   ├── locale-context.tsx    # i18n context
│   │   ├── module-context.tsx    # 模組 + 功能選擇狀態
│   │   └── permission-context.tsx # 使用者權限快取
│   ├── hooks/
│   │   └── use-idle-timeout.ts   # 閒置自動登出
│   ├── lib/
│   │   └── api.ts                # apiFetch + 各資源 API client
│   ├── types/                    # TypeScript interfaces
│   └── i18n/                     # 多語翻譯
├── deployment/
│   ├── hyadmin-ui.container      # Podman Quadlet
│   ├── nginx-hyadmin-ui.conf     # 外部 nginx location config
│   ├── nginx-static.conf         # 容器內 nginx（SPA fallback）
│   └── deploy.sh                 # 完整部署腳本
├── index.html                    # SPA 入口（Inter font via Google Fonts link）
├── vite.config.ts                # base: '/hyadmin/', react plugin, tsconfigPaths
├── tailwind.config.ts            # hyspPreset + sidebar colors
├── components.json               # Shadcn/ui config
└── Containerfile                 # Bun build + nginx runner
```

## Tech Stack

- Vite 6 + React 19 + React Router v7 + TypeScript
- Shadcn/ui（Radix UI primitives）+ Tailwind CSS
- wujie-react 微前端子應用載入
- Bun（package manager + build）

## Key Patterns

### basePath
- `vite.config.ts` 設定 `base: '/hyadmin/'`
- React Router `BrowserRouter` 設定 `basename="/hyadmin"`
- `useLocation().pathname` 回傳**不含** basename 的路徑（如 `/admin/users`）
- 內部路由不帶 `/hyadmin/` 前綴

### API URL（相對路徑）
- **不使用**環境變數，一份 image 到處部署
- hyadmin-api：硬編碼 `/hyadmin-api`（`src/lib/api.ts`）
- 模組 API：從 DB `hyadmin_modules.api_url` 欄位 runtime 讀取（如 `/hycert-api`）
- 瀏覽器 `fetch('/hyadmin-api/...')` 自動解析為當前域名
- 跨域部署：`api_url` 填完整 URL（如 `https://other-host.com/hycert-api`），API server 需開 CORS

### 路由架構
- **RootLayout**: Providers wrapper
- **AuthGuard**: 檢查 token，無 token redirect to /login
- **ShellLayout**: Header + Sidebar + Outlet（受保護路由）
- **LoginLayout**: 置中 layout（公開路由）

### Layout 架構
- **Header**: Logo + 模組水平 tabs（responsive overflow dropdown）+ 系統管理 tab + 使用者選單
- **Sidebar**: 依選中模組顯示功能列表；admin 路由顯示管理選單
- **Breadcrumb**: 首頁 → 模組 → 功能（或管理路徑標籤）
- **Mobile**: Sidebar 以 Sheet 呈現，Header 左側漢堡按鈕觸發

### 模組動態載入流程
1. Header `loadModules()` → `GET /api/v1/modules`（帶 `X-Tenant-ID`）
2. 點選模組 tab → `selectModule()` → 載入功能列表 → Sidebar 顯示
3. 點選功能 → `/app/{route}/{path}` → `AppContainer` → wujie-react 載入

## nginx

- 容器內：nginx 提供靜態檔 + SPA fallback（`/hyadmin/index.html`）
- 外部 nginx：`/hyadmin/` → `http://127.0.0.1:3001`（反向代理到容器 port 80）

## Deploy

```bash
# 第一次
git clone https://github.com/robert7528/hyadmin-ui.git /hysp/hyadmin-ui

# 部署（無需設環境變數，image 通用）
sudo bash /hysp/hyadmin-ui/deployment/deploy.sh
# 步驟：git pull → podman pull image
#        → Quadlet 安裝 → systemctl restart → nginx reload
```
