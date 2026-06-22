# 文件 8 — Remote 改造指南(以 hycert-ui 為樣板)

> 把 `hycert-ui` 從 Wujie sub-app 改造成 MF remote 的逐步實作指南。其餘 remote 比照辦理。
> 整合前面所有契約:文件 3(exposes/三元組)、文件 4(shared/ui-kit build)、文件 5(CSS)、文件 6(共用 router)、文件 7(RemoteProps 注入)。
>
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 改造總覽(對照現況)

| 檔案 | 現況 | 改造後 |
|------|------|--------|
| `vite.config.ts` | react + tsconfigPaths,`base: '/hycert-ui/'` | + `@module-federation/vite` federation 設定 |
| `src/main.tsx` | `__WUJIE_MOUNT/UNMOUNT` + standalone | **只留 standalone 入口**(自帶 Router + Provider)|
| `src/expose/App.tsx` | (新增)| MF 入口:`default export CertApp(props: RemoteProps)`,含 `<Routes>` |
| `src/App.tsx` | `LocaleProvider > CertRouter > Toaster` | 拆成「provider 殼(standalone 用)」與「純 CertApp(共用)」 |
| `src/components/cert/cert-router.tsx` | 手刻 `pathname.includes` + `popstate` | 刪除,改成 `<Routes>`(併入 CertApp,文件 6)|
| `src/lib/cert-api.ts` | 自讀 storage / 自解 JWT / 自處理 401 | 改吃 `configureCertApi(props)` 注入(文件 7)|
| `src/contexts/locale-context.tsx` | remote 自建 LocaleProvider | standalone 才用;MF 模式吃 host 的(文件 4)|

---

## 2. 步驟

### Step 0 — 前置(擋住一切,先做)
依 **文件 4 §3 + 文件 5 §3** 改造 `@hysp/ui-kit`:
- `package.json` `main`/`types` 指 `dist/`、版本遞增。
- 加 CSS 預編譯產 `dist/ui-kit.css`,`exports['./styles']` 指它。
- 新增 `RemoteProps` 型別匯出(文件 7 §2.1)。

> 這步是共用前置,不屬 hycert 本身,但 hycert 改造依賴它完成。

### Step 1 — federation 設定
```ts
// hycert-ui/vite.config.ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'
import { federation } from '@module-federation/vite'

export default defineConfig({
  plugins: [
    react(),
    tsconfigPaths(),
    federation({
      name: 'hycert',                        // = DB.scope(文件 3 §2.1)
      filename: 'remoteEntry.js',
      exposes: { './App': './src/expose/App.tsx' },
      shared: {
        react:              { singleton: true, requiredVersion: '^19' },
        'react-dom':        { singleton: true, requiredVersion: '^19' },
        'react-router-dom': { singleton: true, requiredVersion: '^7' },
        '@hysp/ui-kit':     { singleton: true },
        'js-cookie':        { requiredVersion: '^3' },
      },
    }),
  ],
  base: '/hycert-ui/',          // standalone / 資產 base 保留
  server: { port: 5173, cors: true },
  build: { target: 'esnext' },  // top-level await(MF runtime 需要)
})
```

### Step 2 — MF 入口 `src/expose/App.tsx`(共用元件,不含 Provider/Router 外殼)
```tsx
import type { RemoteProps } from '@hysp/ui-kit'
import { Routes, Route } from 'react-router-dom'
import { configureCertApi } from '@/lib/cert-api'
import { CertList } from '@/components/cert/cert-list'
// ...其餘 list imports

export default function CertApp(props: RemoteProps) {
  configureCertApi(props)              // 文件 7:注入 auth/apiBase
  return (
    <Routes>
      <Route path="list"          element={<CertList />} />
      <Route path="csrs"          element={<CSRList />} />
      <Route path="deployments"   element={<DeployList />} />
      <Route path="agents"        element={<AgentList />} />
      <Route path="tokens"        element={<TokenList />} />
      <Route path="acme/orders"   element={<AcmeOrderList />} />
      <Route path="acme/accounts" element={<AcmeAccountList />} />
      <Route path="health"        element={<HealthDashboard />} />
      <Route path="toolbox"       element={<CertToolbox />} />
      <Route path="*"             element={<HealthDashboard />} />
    </Routes>
  )
}
```
> 注意:**不包 `LocaleProvider` / `Toaster` / `BrowserRouter`**——MF 模式由 host 提供(文件 4/6/7)。

### Step 3 — standalone 入口 `src/main.tsx`(自帶外殼)
```tsx
import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import { LocaleProvider } from '@/contexts/locale-context'
import { Toaster } from '@hysp/ui-kit'
import CertApp from '@/expose/App'
import '@hysp/ui-kit/styles'   // standalone 自載完整 CSS(文件 5 §4-5)
import './globals.css'

// standalone 用 mock / 本機 token 組 RemoteProps
const devProps = {
  auth: {
    getToken: () => sessionStorage.getItem('hyadmin_token'),
    tenantId: '...', onUnauthorized: () => { location.href = '/hyadmin/login' },
  },
  apiBase: '/hycert-api',
  locale: 'zh-TW',
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <LocaleProvider>
      <BrowserRouter basename="/hycert-ui">
        <Routes><Route path="/*" element={<CertApp {...devProps} />} /></Routes>
      </BrowserRouter>
      <Toaster />
    </LocaleProvider>
  </React.StrictMode>
)
```
> **移除 `__POWERED_BY_WUJIE__` / `__WUJIE_MOUNT/UNMOUNT` 整段**(文件 1 §3.1)。MF 模式不經 `main.tsx`,host 直接 `loadRemote('hycert/App')`。

### Step 4 — 刪 `cert-router.tsx`
其邏輯已搬進 Step 2 的 `<Routes>`。刪除 `pathname.includes` + `popstate` 整檔(文件 6 §3.4)。

### Step 5 — 改造 `cert-api.ts`(文件 7 §2.3)
- 移除 `getToken`(自讀 storage)、`getTenantId`(自解 JWT)、`setCertApiBase`、寫死的 401 轉址。
- 新增 `configureCertApi(props: RemoteProps)`,`certFetch`/`crudFetch` 改吃 `_cfg.auth.getToken()` / `_cfg.apiBase` / `_cfg.auth.tenantId` / `_cfg.auth.onUnauthorized()`。

### Step 6 — Tailwind 設定(文件 5 §3)
- `tailwind.config.ts`:`corePlugins: { preflight: false }`,`content` **移除** `./node_modules/@hysp/ui-kit/src/**`(改由 host 載 ui-kit 預編譯 CSS)。
- 保留 `presets: [hyspPreset]`(token 值一致)。
- standalone 模式仍 `import '@hysp/ui-kit/styles'`(Step 3)。

---

## 3. 雙模式對照(同一個 CertApp,兩種外殼)

```
MF 模式(host 載入):
  host: <RemoteErrorBoundary><Suspense>
          <CertApp {...injectedProps} />     ← host 提供 Router/Provider/CSS
        </Suspense></RemoteErrorBoundary>

standalone 模式(獨立開發):
  main.tsx: <LocaleProvider><BrowserRouter>
              <CertApp {...devProps} />        ← 自備 Router/Provider/CSS
            </BrowserRouter></LocaleProvider>
```

`CertApp` 本體零分支,差異全在外殼。

---

## 4. 驗收(本 remote 自測,進文件 10 整合驗收)
- [ ] `pnpm dev` standalone 可獨立切所有子頁、API 通。
- [ ] `pnpm build` 產出 `dist/remoteEntry.js` + chunks。
- [ ] host 以 `integration='mf'` 載入本 remote,四項(單例/CSS/router/auth)皆通。
- [ ] `Module.api_url` 改值,remote API base 跟著變。
- [ ] 移除 Wujie 相關碼後 grep 無殘留 `__WUJIE` / `__POWERED_BY_WUJIE__`。

---

## 5. 銜接
- Step 0 依 **文件 4 / 5**。
- Step 2/3 路由依 **文件 6**;Step 5 注入依 **文件 7**。
- host 端對應改造(RemoteOutlet/分流/ErrorBoundary)見 **文件 3 §4**。
- 遷移順序與回滾見 **文件 9**。
