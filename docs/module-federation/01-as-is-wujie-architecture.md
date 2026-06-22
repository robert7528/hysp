# 文件 1 — HySP 微前端現況盤點(AS-IS / Wujie)

> 目的:在導入 Module Federation 前,先把目前以 **Wujie(無界)** 為基礎的微前端機制每個對接點畫清楚,作為遷移的基準線。後續所有契約文件(共享單例、樣式隔離、路由、認證)都以本文描述的現況為「要被取代/保留的東西」。
>
> 適用範圍:`hyadmin-ui`(host)、`hycert-ui`(remote 樣板)、`hyui-kit`(共享 UI kit)。
> 撰寫依據:repo 實際程式碼,逐處標出檔案:行。
> 最後更新:2026-06-16

---

## 1. 全景圖

```
┌──────────────────────────────────────────────────────────────┐
│ hyadmin-ui  (Host / Shell)                                    │
│  React 19 + react-router-dom  BrowserRouter basename="/hyadmin"│
│                                                                │
│  app.tsx ── Route "app/:route/*" ─► AppPage                    │
│                 │  modules from DB (module-context)            │
│                 │  比對 route → 找到 Module                     │
│                 ▼                                              │
│  app-page.tsx ── 組 subAppUrl = module.url + subPath           │
│                 ▼                                              │
│  app-container.tsx ── <WujieReact name url width height />     │
│                          │  (wujie-react)                      │
└──────────────────────────┼─────────────────────────────────────┘
                           │  iframe + ShadowDOM 沙箱 (JS/CSS 隔離)
                           ▼
┌──────────────────────────────────────────────────────────────┐
│ hycert-ui  (Remote / Sub-app)   base "/hycert-ui/"             │
│  main.tsx ── 偵測 window.__POWERED_BY_WUJIE__                   │
│              掛 __WUJIE_MOUNT / __WUJIE_UNMOUNT                 │
│  App.tsx ── LocaleProvider > CertRouter > Toaster              │
│  cert-router.tsx ── 手刻:讀 window.location.pathname + popstate│
│  cert-api.ts ── fetch /hycert-api,JWT from cookie/session      │
└──────────────────────────────────────────────────────────────┘

共享層:@hysp/ui-kit  (file: 本地依賴,各 app 各自 bundle 一份)
```

**一句話**:Wujie 以「沙箱隔離 + 各自獨立 bundle」整合;host 與各 remote 在**不同 JS context**,靠**同源 cookie/sessionStorage** 共享登入狀態,靠**各自打包的 ui-kit** 取得一致外觀。

---

## 2. Host 端(hyadmin-ui)

### 2.1 路由與殼層
- `src/app.tsx:26` — `BrowserRouter basename="/hyadmin"`。
- `src/app.tsx:54` — `<Route path="app/:route/*" element={<AppPage />} />`,所有子應用掛在 `/hyadmin/app/:route/*` 之下。
- 其餘 `admin/*`、`profile`、`login` 等為 host 自有頁面(非微前端)。

### 2.2 模組註冊(DB 驅動)
- 模型 `src/types/module.ts:1`:
  ```ts
  interface Module {
    id, name, display_name, icon,
    route,            // host 路由比對用,例:"cert"
    url,              // ★ 子應用進入點 URL,例:"/hycert-ui/"
    api_url,          // ★ 子應用後端 API base(目前未實際接通,見 §5 缺口)
    description, sort_order, enabled, created_at, updated_at
  }
  ```
- `src/contexts/module-context.tsx:33` — `loadModules()` 從 `modulesApi.list()` 取清單,存進 context。
- 模組可由 `hyadmin` 後台 CRUD(`pages/admin/modules*.tsx`),`enabled` 旗標控制啟用。

### 2.3 子應用載入流程
- `src/pages/app-page.tsx:22` — 依 `route` 與 `enabled` 找到 `Module`。
- `app-page.tsx:32-38` — 把 `/app/:route` 之後的 subPath 接到子應用 URL 後面:
  `/hyadmin/app/cert/list` → subPath `/list` → `subAppUrl = "/hycert-ui/" + "/list"`。
- `app-page.tsx:40` — `<AppContainer key={`${mod.name}-${subPath}`} ... />`,**用 `key` 綁 subPath**,所以子路由切換會讓 Wujie 整個 **re-mount**。
- `src/components/micro-app/app-container.tsx:9` — 實際就是 `<WujieReact name url width="100%" height="100%" />`。

### 2.4 Wujie 能傳但沒用到的能力
- `src/types/wujie-react.d.ts:13` — `WujieReact` 型別支援 `props?: Record<string, unknown>`,可注入資料給子應用。
- **但 `AppContainer` 沒有傳 `props`**(`app-container.tsx:9-17` 只給 name/url/width/height)。→ 目前 host 與 remote 之間**沒有任何 props 通道**,所有跨應用資訊都走同源 cookie/sessionStorage。

---

## 3. Remote 端(hycert-ui,樣板)

### 3.1 生命週期
- `src/main.tsx:18-23`:
  ```ts
  if (window.__POWERED_BY_WUJIE__) {
    window.__WUJIE_MOUNT   = () => mount()
    window.__WUJIE_UNMOUNT = () => unmount()
  } else {
    mount()   // 獨立開發 / 直接開時
  }
  ```
  → mount/unmount 由 Wujie 主應用呼叫;**保留 standalone 模式**(無 Wujie 時自掛)。
- `vite.config.ts:7` — `base: '/hycert-ui/'`,對應 Module.url。

### 3.2 應用組裝
- `src/App.tsx` — `LocaleProvider > CertRouter > Toaster`,**無 router framework、無 query framework**。
- `Toaster` 來自 `@hysp/ui-kit`(sonner 封裝)。

### 3.3 手刻路由
- `src/components/cert/cert-router.tsx:14-64`:
  - `useState(pathname)` + `useEffect` 監聽 `popstate`;
  - 用 `pathname.includes('/list' | '/csrs' | '/deployments' | ...)` 一串 if 決定渲染哪個 list 元件;
  - 只在 mount 時讀一次 pathname,**只監聽 `popstate`**(不處理應用內 `pushState`)。
- 之所以夠用,是因為子路由切換靠 host 端 `key` re-mount(§2.3),每次都是全新掛載。

### 3.4 API 與認證
- `src/lib/cert-api.ts`:
  - `:5` 預設 `_apiBase = '/hycert-api'`;
  - `:8 setCertApiBase(base)` 可覆寫 base — **但全 repo 無任何呼叫處**(見 §5);
  - `:12-15 getToken()` — `sessionStorage.getItem(TOKEN_KEY) ?? Cookies.get(TOKEN_KEY)`,key 為 `PLATFORM_STORAGE_KEYS.COOKIE.TOKEN`(來自 ui-kit);
  - `:17-27 getTenantId()` — 解 JWT payload 取 `tc` claim 當租戶碼;
  - `:36` — `Authorization: Bearer <token>`;
  - `:40-45` — 401 → `window.location.href = '/hyadmin/login'`;
  - `:56` `crudFetch` — CRUD endpoint 另加 `X-Tenant-ID` header。

---

## 4. 共享層(@hysp/ui-kit)

- `package.json`(hyui-kit):
  - `:6-7` — `main`/`types` 指向 **`./src/index.ts`**(source 形式,非 dist);實務上各 app 透過 `vite-tsconfig-paths` + `file:` 依賴直接吃原始碼。
  - `:24-27` — `peerDependencies: react/react-dom >=18`。
  - `:8-12` — `exports` 另有 `./styles`(globals.css)與 `./tailwind-preset`。
- 內容:Radix 封裝元件、`LocaleProvider`/`useLocale`、`PLATFORM_STORAGE_KEYS`、`ApiResponse` 型別、`Toaster`、`cn()` 等。
- **現況關鍵**:Wujie 下 host 與每個 remote **各自打包一份 ui-kit**。因為彼此 JS context 隔離,React context(如 `LocaleProvider`)**本來就無法跨 host/remote 共享** → 每個 app 自建一棵 provider 樹(`hycert-ui` 的 `src/contexts/locale-context.tsx` 就是再包一層自己的字典)。這在 Wujie 下沒問題,但**正是 MF 要逆轉的前提**(MF 共享 runtime,context 可跨界,但前提是 ui-kit/react 設成 singleton)。

---

## 5. 已知缺口 / 技術債(遷移時要一併處理)

| # | 現象 | 位置 | 影響 |
|---|------|------|------|
| D1 | `Module.api_url` 有定義但**未接通**:host 不傳 props、子應用 `setCertApiBase` 無人呼叫 | `module.ts:8` / `app-container.tsx:9` / `cert-api.ts:8` | 子應用 API base 實際是 hardcode `/hycert-api`;多環境/多後端佈署彈性是假的 |
| D2 | Host↔Remote **無資料通道**(props 沒接) | `app-container.tsx` | 所有跨應用狀態被迫走全域 cookie/sessionStorage,耦合在「同源」假設上 |
| D3 | 子應用路由靠 host `key` re-mount,本身只認 `popstate` | `app-page.tsx:40` / `cert-router.tsx:21` | 切子頁是整頁 re-mount,無法做應用內無重整導航;狀態不保留 |
| D4 | ui-kit 以 source 形式被多 app 重複打包 | `hyui-kit/package.json:6` | bundle 重複;MF 下若不設 singleton 會 context 斷裂 |
| D5 | 樣式隔離**完全依賴 Wujie ShadowDOM** | — | 一旦離開 Wujie,Tailwind utility/preflight 立即衝突(見文件 5) |

---

## 6. 遷移時「要保留」與「會消失」清單

**要保留(換 MF 後仍需等效機制)**
- DB 驅動的模組註冊與 `enabled` 開關(§2.2)。
- 子應用 standalone 獨立開發模式(§3.1)。
- 同源 JWT/租戶認證語意:`tc` claim、401→login(§3.4)。
- ui-kit 作為單一設計來源(§4)。

**會消失(Wujie 專屬,MF 沒有,需用契約補上)**
- ShadowDOM/iframe 的 JS + CSS 沙箱隔離 → 改用**共享單例 + 樣式 scope 策略**(文件 4、5)。
- `__WUJIE_MOUNT/UNMOUNT` 生命週期 → 改用 **MF `exposes` 的元件/mount 函式**(文件 8)。
- `key` re-mount 式子路由 → 改用**共用 react-router 或 remote 自帶 router 的整合契約**(文件 6)。

---

## 7. 對應文件

| 現況面向 | 後續契約文件 |
|----------|-------------|
| §2 host 載入、§2.2 Module schema | 文件 3 — Host↔Remote 整合契約 |
| §4 ui-kit 共享、D4 | 文件 4 — 共享依賴與單例策略 |
| D5 樣式隔離 | 文件 5 — Tailwind/CSS 隔離策略 |
| §2.3 / §3.3 / D3 路由 | 文件 6 — 路由整合契約 |
| §3.4 / D1 / D2 認證與 api_url | 文件 7 — 認證與多租戶傳遞 |
| §3.1 生命週期、§3.3 | 文件 8 — Remote 改造指南(hycert 樣板) |
