# 文件 7 — 認證與多租戶傳遞

> 解決 ADR Open Question **Q4**:host 如何把認證 / 租戶 / API base / locale 注入 remote;401 與 token 刷新的統一點放哪。
> 同時修掉文件 1 的 D1(`api_url` 未接通)與 D2(host↔remote 無資料通道)。
>
> 依據:文件 1(§3.4 / D1 / D2)、文件 3(RemoteProps)、文件 4(ui-kit singleton)、文件 6(共用 router)。
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 現況回顧與問題

- host(`hyadmin-ui/src/lib/api.ts`):token 存 `hyadmin_token`(sessionStorage + cookie),tenant 存 `hyadmin_tenant`,`apiFetch` 帶 `Authorization` + `X-Tenant-ID`,401 → `clearToken()` + 轉 `/hyadmin/login`。
- remote(`hycert-ui/src/lib/cert-api.ts`):**各自重做一套**——自己讀 `PLATFORM_STORAGE_KEYS.COOKIE.TOKEN`、自己解 JWT `tc` claim 取 tenant、自己處理 401 轉址。
- 問題:
  - **D1**:`Module.api_url` 沒接通,remote 的 `_apiBase` 是 hardcode `/hycert-api`,`setCertApiBase` 無人呼叫。
  - **D2**:host 與 remote 無資料通道,只能各自靠**同源全域 storage** 猜彼此狀態 → 耦合在同源假設、且邏輯重複。
  - token key 不一致(host `hyadmin_token` vs remote `PLATFORM_STORAGE_KEYS.COOKIE.TOKEN`)是隱性風險。

MF 共享 runtime 後,host 可以**直接把這些當 context/props 注入**,不必再靠隱性全域狀態。

---

## 2. 設計:host 集中供應,remote 純消費

**兩層注入,互補:**

1. **共享 context(主)**:host 用 `@hysp/ui-kit` 的 `AuthProvider`(singleton)建立唯一一棵認證樹,remote 用 `useAuth()` 直接讀。因 ui-kit 是 singleton(文件 4),context 可跨 host/remote。
2. **顯式 props(輔,契約化)**:`RemoteOutlet` 載入 remote `./App` 時,把契約欄位當 props 傳入,讓 remote 的依賴**型別明確、可獨立測試**。

### 2.1 RemoteProps 契約(文件 3 §9 引用的定義)
```ts
// @hysp/ui-kit 匯出,host 與所有 remote 共用
export interface RemoteProps {
  auth: {
    getToken: () => string | null     // 不傳裸 token,傳 getter,避免過期快照
    tenantId: string                  // 由 host 統一解出(JWT tc claim)
    onUnauthorized: () => void        // 401 統一處理(host 實作:clearToken + 轉 login)
  }
  apiBase: string                     // ★ 來自 Module.api_url,解掉 D1
  locale: string                      // host 當前語系,remote 同步(文件 4 LocaleProvider 亦可讀)
  // 路由由共用 router 提供(文件 6),不入 props
}
```

### 2.2 host 注入
```tsx
// hyadmin-ui: RemoteOutlet
<RemoteComponent
  auth={{
    getToken,                              // 來自 lib/api.ts
    tenantId: getTenantCode(),             // host 既有
    onUnauthorized: () => { clearToken(); navigate('/login') },
  }}
  apiBase={module.api_url || '/hycert-api'} // ★ Module.api_url 終於接通
  locale={currentLocale}
/>
```

### 2.3 remote 消費
```tsx
// hycert-ui: src/expose/App.tsx
export default function CertApp(props: RemoteProps) {
  configureCertApi(props)   // 把 props 灌進 cert-api 模組(取代散落的 getToken/setCertApiBase)
  return <Routes>{/* 文件 6 */}</Routes>
}
```
```ts
// cert-api.ts 改造:不再自己讀 storage / 解 JWT,改吃注入
let _cfg: RemoteProps | null = null
export function configureCertApi(cfg: RemoteProps) { _cfg = cfg }

async function certFetch<T>(path: string, init: RequestInit = {}) {
  const token = _cfg!.auth.getToken()
  const res = await fetch(`${_cfg!.apiBase}${path}`, { /* + Authorization, X-Tenant-ID: _cfg.auth.tenantId */ })
  if (res.status === 401) { _cfg!.auth.onUnauthorized(); throw new Error('Unauthorized') }
  // ...
}
```

---

## 3. 401 與 token 刷新的統一點

**決議:統一收斂到 host。**

- **401**:remote `certFetch` 偵測到 401 → 呼叫 `props.auth.onUnauthorized()`(host 實作),**remote 不自己決定轉去哪**。消除文件 1 §3.4 remote 寫死 `/hyadmin/login` 的耦合。
- **token 刷新 / 過期**:remote 拿的是 `getToken()` **getter 不是快照**,每次請求取最新;刷新邏輯(若有)只在 host 一處。remote 永遠不需要知道 token 怎麼來、怎麼存。
- **租戶**:`tenantId` 由 host 統一解出並傳入;remote 不再自己解 JWT `tc`(刪掉 `cert-api.ts:17 getTenantId`)。單一真相來源。

---

## 4. token key 一致性(順手修的隱性風險)

現況 host 用 `hyadmin_token`,remote 用 `PLATFORM_STORAGE_KEYS.COOKIE.TOKEN`——若兩者不同字串,Wujie 時代靠各自讀各自的剛好沒爆,但語意上是兩套。

**決議**:本次注入改造後 remote **不再直接讀 storage**(改吃 `props.auth.getToken`),所以 remote 端的 key 不一致問題**自然消失**。host 端則建議把 `'hyadmin_token'` 收斂到 `PLATFORM_STORAGE_KEYS`,讓 storage key 也單一來源(可列入文件 9 清理項)。

---

## 5. 安全性備註

- 同源前提仍在(host 與 remote 通常同源部署),cookie 帶 token 的行為不變;但**跨應用授權判斷不再靠隱性同源 storage**,而是 host 顯式注入 → 邊界更清楚。
- remote 不再持有「如何取得/儲存 token」的知識 → 最小權限,降低 remote 被注入惡意 entry 時的攻擊面(配合文件 3 §5 remoteEntry 來源控管)。
- `getToken` getter 不在 props 裡塞裸 token 字串,避免長壽命快照外洩。

---

## 6. 驗證(進文件 10)
1. host 登入後進 remote 子頁,remote API 請求帶正確 `Authorization` + `X-Tenant-ID`(來自注入,非 remote 自解)。
2. `Module.api_url` 改值 → remote 實際打的 base URL 跟著變(**驗 D1 已修**)。
3. 模擬 401 → 走 host 的 `onUnauthorized`(轉 login),remote 不自行決定轉址。
4. host 切語系 → remote `useLocale()`/`props.locale` 同步(驗 ui-kit context 跨界,呼應文件 4)。
5. remote standalone 模式:用 mock 的 `RemoteProps` 即可獨立跑(驗證依賴已契約化、可測)。

---

## 7. 銜接
- `RemoteProps` 定義落在 `@hysp/ui-kit`(文件 4 的 build 改造一起加)。
- 路由不入 props,由共用 router 提供(文件 6)。
- `cert-api.ts` 改造的實作步驟在 **文件 8**。
- host token key 收斂列入 **文件 9** 清理項。
