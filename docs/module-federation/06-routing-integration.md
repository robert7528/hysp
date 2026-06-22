# 文件 6 — 路由整合契約

> 解決 ADR Open Question **Q1**:remote 共用 host 的 react-router(方案 A)還是各自帶 router 僅同步 URL(方案 B)。
> 取代文件 1 的兩個現況痛點:host `key` re-mount(§2.3)+ remote 手刻 `popstate` router(§3.3 / D3)。
>
> 依據:文件 1(§2.1/§2.3/§3.3)、文件 3(§4 subPath)、文件 4(router singleton)。
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 現況回顧

- host:`app.tsx:26` `BrowserRouter basename="/hyadmin"`,`app/:route/*` → `AppPage`(react-router-dom v7)。
- remote:`cert-router.tsx` 手刻——`window.location.pathname` + `popstate`,只認瀏覽器前進/後退,**不處理應用內 `pushState`**(因為現況靠 host `key` re-mount,每次都是全新掛載)。
- 問題(D3):切子頁 = 整個 remote re-mount,**狀態不保留、無無重整導航、捲動位置丟失**。

---

## 2. 兩方案

### 方案 A — 共用 host 的 react-router(巢狀路由)★ 建議
remote **不自帶 `BrowserRouter`**,直接用 host 透過 **shared singleton** 提供的同一個 router context,以**巢狀路由 / 相對路徑**渲染自己的子頁。

```tsx
// host: app.tsx —— 改 /app/:route/* 為交給 remote 接管尾段
<Route path="app/:route/*" element={<AppPage />} />

// remote: src/expose/App.tsx —— 用 Routes(相對),basename 由 host 提供
export default function CertApp() {
  return (
    <Routes>
      <Route path="list"        element={<CertList />} />
      <Route path="csrs"        element={<CSRList />} />
      <Route path="deployments" element={<DeployList />} />
      <Route path="agents"      element={<AgentList />} />
      <Route path="tokens"      element={<TokenList />} />
      <Route path="acme/orders" element={<AcmeOrderList />} />
      <Route path="acme/accounts" element={<AcmeAccountList />} />
      <Route path="health"      element={<HealthDashboard />} />
      <Route path="toolbox"     element={<CertToolbox />} />
      <Route path="*"           element={<HealthDashboard />} />
    </Routes>
  )
}
```

- **前提**:`react-router-dom` 設 `singleton`(文件 4 §2),否則 remote 的 `<Routes>` 找不到 host 的 Router context → `useNavigate outside Router`。
- remote 內導航用 `<Link to="../csrs">` / `useNavigate()`,**無重整、狀態保留**。
- URL 結構:`/hyadmin/app/cert/csrs` 全程由單一 router 管理,瀏覽器前後鍵自然運作(取代 `popstate` 手刻)。
- ✅ 解 D3:in-app 導航、狀態保留、捲動位置;✅ host 麵包屑/側欄能讀同一 location。
- ⚠️ 耦合:remote 綁定 react-router 主版本(文件 4 已要求 major 對齊);remote standalone 開發需自備 router(§4)。

### 方案 B — remote 自帶 router,僅同步 URL
remote 內用自己的 `MemoryRouter`/`BrowserRouter`,host 把 subPath 當 prop 傳入,雙向同步 URL。
- ✅ remote 與 host router 解耦,版本無關。
- ❌ URL 同步要自己寫(host→remote 與 remote→host 雙向),容易不一致;前後鍵、深連結邊界多;本質上是把現況 `popstate` 手刻法包裝得更複雜。
- 適用:remote 用**完全不同的路由技術**或想完全獨立時。**本案不需要**。

---

## 3. 決議:採方案 A

理由:host 已是 react-router v7、文件 4 已將其列為 singleton,remote(hycert)子頁本來就是同一棵 SPA 的延伸,**共用 router 同時解掉 D3 與「麵包屑/側欄與子頁 location 不同步」**。方案 B 的解耦在本案沒有實際需求,徒增同步成本。

### 落地要點
1. `react-router-dom` → `singleton: true, eager(host), requiredVersion '^7'`(文件 4 §2)。
2. host `AppPage` 不再組 `subAppUrl`、不再用 `key` re-mount;改 render `<RemoteOutlet>`(文件 3 §4),remote 內用相對 `<Routes>`。
3. **basename 對齊**:host `basename="/hyadmin"`,remote 的相對路由掛在 `/app/:route` 下;remote 內一律用**相對路徑**(`to="../csrs"`、`path="csrs"`),不寫絕對 `/hyadmin/...`,避免綁死 host 前綴。
4. **刪除 `cert-router.tsx` 的 `popstate` 手刻邏輯**,改成上面的 `<Routes>`(文件 8 執行)。
5. host 的側欄高亮/麵包屑改讀 `useLocation()`(已是 react-router)即可涵蓋 remote 子頁。

---

## 4. standalone 開發模式

remote 單獨開發時沒有 host 的 Router → 自備薄殼(文件 8 的 `main.tsx` 分支):

```tsx
// standalone 入口:自己包 BrowserRouter
<BrowserRouter basename="/hycert-ui">
  <Routes><Route path="/*" element={<CertApp />} /></Routes>
</BrowserRouter>
```

MF 模式則由 host 提供 Router,remote 的 `./App` **不含** `BrowserRouter`。**同一個 `CertApp` 元件,兩種外殼**。

---

## 5. 驗證(進文件 10)

1. host 內點 remote 子頁連結(`list`→`csrs`)→ **URL 變、無整頁重整、無 re-mount**(在元件放 `useEffect` log 驗證未重新 mount)。
2. 瀏覽器前進/後退跨越 host 頁與 remote 子頁皆正確。
3. host 側欄/麵包屑在 remote 子頁仍正確高亮(讀同一 location)。
4. remote standalone 啟動仍能獨立切頁。
5. 深連結直接開 `/hyadmin/app/cert/acme/orders` → 正確落到對應子頁。

---

## 6. 銜接
- 依賴 **文件 4**(router singleton)。
- subPath 不再當 prop(文件 3 §4 的暫定作法被本文取代為共用 router)；文件 3 §4 的 `RemoteOutlet` 仍是載入點,只是內部改 render 含 `<Routes>` 的 `CertApp`。
- **文件 8** 執行 `cert-router.tsx` → `<Routes>` 的改寫與雙入口。
