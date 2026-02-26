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
│   ├── app/
│   │   ├── layout.tsx              # Root shell: HeroUI Provider + Header + Sidebar + Footer
│   │   ├── page.tsx                # Dashboard 首頁
│   │   ├── globals.css
│   │   └── app/[...route]/page.tsx # micro-app 動態路由（client component）
│   ├── components/
│   │   ├── providers.tsx           # HeroUI provider（'use client'）
│   │   ├── layout/
│   │   │   ├── header.tsx          # Navbar（HeroUI）
│   │   │   ├── sidebar.tsx         # 動態選單，fetchModules() 取模組清單
│   │   │   └── footer.tsx
│   │   ├── micro-app/
│   │   │   └── app-container.tsx   # <micro-app> 自訂元素容器
│   │   └── ui/                     # Shadcn/ui 組件（bunx shadcn add ...）
│   ├── lib/
│   │   ├── utils.ts                # cn() helper（clsx + tailwind-merge）
│   │   └── micro-app.ts            # fetchModules() + initMicroApp()
│   └── types/
│       └── module.ts               # Module interface
├── deployment/
│   ├── hyadmin-ui.container        # Podman Quadlet
│   ├── nginx-hyadmin-ui.conf       # nginx location config
│   └── deploy.sh                   # 完整部署腳本
├── next.config.ts                  # basePath: '/hyadmin', output: 'standalone'
├── tailwind.config.ts              # HeroUI plugin
├── components.json                 # Shadcn/ui config
├── .env.local.example
└── Containerfile                   # Bun build + Node runner
```

## Tech Stack

- Next.js 15 (App Router) + React 19 + TypeScript
- HeroUI（整體 layout shell）+ Shadcn/ui（UI 組件）+ Tailwind CSS
- micro-app（`@micro-zoe/micro-app`）微前端子應用載入
- Bun（package manager + build）

## Key Patterns

### basePath
- `next.config.ts` 設定 `basePath: '/hyadmin'`
- 所有內部路由、`_next/static` 自動加前綴
- nginx **不剝離**前綴（`proxy_pass http://127.0.0.1:3000`，無 trailing slash）

### 環境變數（Build-time）
- `NEXT_PUBLIC_*` 在 **build time 嵌入**，不能 runtime 注入
- 需透過 `--build-arg` 傳入 Containerfile：
  ```bash
  export NEXT_PUBLIC_API_URL=https://your-domain/hyadmin-api
  sudo bash deployment/deploy.sh
  ```

### 模組動態載入流程
1. Sidebar `useEffect` → `fetchModules()` → `GET /api/v1/modules`（帶 `X-Tenant-ID`）
2. 點選模組 → `/app/{route}` → `AppContainer`
3. `AppContainer` → `microApp.start()` + `<micro-app name url baseroute>`

### 新增 Shadcn/ui 組件
```bash
bunx shadcn@latest add button
```

## Environment Variables

| 變數 | 預設值 | 說明 |
|------|--------|------|
| `NEXT_PUBLIC_API_URL` | `http://localhost:8080` | hyadmin-api base URL（build-time） |
| `NEXT_PUBLIC_TENANT_ID` | `default` | Tenant ID for API requests（build-time） |

本地開發：複製 `.env.local.example` → `.env.local`

## nginx

- 路徑：`/hyadmin/` → `http://127.0.0.1:3000`
- **無 trailing slash**：Next.js basePath 需收到完整路徑（含 `/hyadmin/`）

## Deploy

```bash
# 第一次
git clone https://github.com/robert7528/hyadmin-ui.git /hysp/hyadmin-ui

# 部署（API URL 若有變更先 export）
export NEXT_PUBLIC_API_URL=https://your-domain/hyadmin-api
sudo bash /hysp/hyadmin-ui/deployment/deploy.sh
# 步驟：git pull → podman build（含 build-arg）
#        → Quadlet 安裝 → systemctl restart → nginx reload
```
