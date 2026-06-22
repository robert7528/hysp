# 文件 2 — Module Federation 目標架構 + ADR

> 目的:定義 HySP 平台機制改用 **Module Federation(MF)** 後的目標架構(TO-BE),並以 ADR 形式記錄「為何換、選了什麼、放棄了什麼」。本文是後續所有契約文件(3–10)的決策前提。
>
> 撰寫依據:文件 1(AS-IS)所盤點的現況。
> 最後更新:2026-06-16
> 狀態:**Proposed**(待 review;核可後同步進 Notion HySP ADR DB)

---

## Part A — 目標架構(TO-BE)

### A.1 全景圖

```
┌──────────────────────────────────────────────────────────────┐
│ hyadmin-ui  (MF Host)                                          │
│  React 19 (singleton, eager)                                   │
│  @module-federation/vite  host 設定                            │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ Shell: react-router + ShellLayout + Providers          │  │
│  │  ├ AuthProvider / PermissionProvider / LocaleProvider  │  │← 共享單例 context
│  │  │   (來自 @hysp/ui-kit,host 建立唯一一棵)              │  │
│  │  └ Route "app/:route/*"                                 │  │
│  │      └ <RemoteOutlet />  動態載入 remote 元件           │  │
│  └───────────────┬────────────────────────────────────────┘  │
│   runtime 動態註冊 remote(從 DB module registry)             │
│   loadRemote(scope, exposed) ◄── Module.remoteEntry           │
└───────────────────┼────────────────────────────────────────────┘
                    │  共享同一 JS runtime(無沙箱)
       shared: react / react-dom / @hysp/ui-kit / react-router (singleton)
                    ▼
┌──────────────────────────────────────────────────────────────┐
│ hycert-ui  (MF Remote)                                         │
│  exposes  "./App" → 一個純 React 元件(無 BrowserRouter)        │
│  vite.config federation:                                       │
│    name "hycert", filename "remoteEntry.js"                    │
│    shared { react, react-dom, @hysp/ui-kit, react-router }     │
│  消費 host 提供的 Auth/Locale context(不再自建 provider)       │
│  standalone 模式:自帶薄殼(自建 provider + router)單獨開發      │
└──────────────────────────────────────────────────────────────┘
```

### A.2 核心轉變對照(vs Wujie)

| 面向 | AS-IS(Wujie) | TO-BE(Module Federation) |
|------|---------------|---------------------------|
| 整合單位 | iframe + ShadowDOM 沙箱 | 共享 runtime 的 JS 模組(`remoteEntry.js`)|
| 隔離 | 框架自動 JS+CSS 隔離 | **無自動隔離** → 靠單例 + 樣式 scope 契約 |
| 子應用入口 | URL(整個 app)| `exposes` 的 React 元件 |
| 生命週期 | `__WUJIE_MOUNT/UNMOUNT` | host `import()` remote 元件,React 自然掛卸 |
| 跨應用資料 | 同源 cookie/sessionStorage(props 未接)| host 經**共享 context / props** 注入 remote |
| ui-kit | 各 app 各打包一份 | **singleton 共享**(context 可跨界)|
| 子路由 | host `key` re-mount + remote `popstate` | 共用 react-router 巢狀路由 |
| 模組註冊欄位 | `url`(進入點)| `remoteEntry` + `scope` + `exposedModule`(+ 保留 `api_url`)|

### A.3 模組註冊 schema 擴充(預覽,細節見文件 3)

```ts
interface Module {
  // 既有
  id; name; display_name; icon; route; api_url;
  description; sort_order; enabled; created_at; updated_at;

  // 新增(MF)
  remote_entry: string   // 例 "https://cdn/hycert/remoteEntry.js"
  scope: string          // MF container 名,例 "hycert"
  exposed_module: string // 例 "./App"

  // 過渡期(雙模式)
  integration: 'wujie' | 'mf'  // 控制走舊機制或新機制
  url?: string                 // wujie 模式仍用;mf 模式可空
}
```

### A.4 共享依賴策略(預覽,細節見文件 4)

| 套件 | shared 設定 | 理由 |
|------|------------|------|
| `react` / `react-dom` | `singleton: true, requiredVersion`(建議 eager 於 host)| 多份 React 會炸 hooks;context 也需同一份 |
| `@hysp/ui-kit` | `singleton: true` | `LocaleProvider`/`PLATFORM_STORAGE_KEYS` 需跨 host/remote 同一實例 |
| `react-router(-dom)` | `singleton: true` | 若採共用路由(文件 6 方案 A)必須單例 |
| `js-cookie` | 一般 shared(可不 singleton)| 無狀態工具,版本相容即可 |

> ⚠️ **ui-kit 須先改 build 輸出**:目前 `main` 指向 `src/index.ts`(原始碼),作為 MF shared 需有穩定的 ESM build 產物與版本號(文件 4 處理)。

---

## Part B — ADR

### ADR-XXXX:HySP 平台微前端機制由 Wujie 改為 Module Federation

**狀態**:Proposed — 2026-06-16
**決策者**:K00(技術經理)
**相關**:文件 1(AS-IS)、文件 3–10

#### 背景(Context)
- 現況以 Wujie 整合 host(`hyadmin-ui`)與 remote(`hycert-ui` 等),沙箱隔離換來的代價是:
  - host↔remote **無有效資料通道**(`Module.api_url`/Wujie `props` 皆未接通,見文件 1 §5 D1/D2);
  - ui-kit **重複打包**、context 無法跨界共享(D4);
  - 子路由只能靠整頁 re-mount,**無應用內無重整導航**(D3);
  - iframe/ShadowDOM 在巢狀元件(Radix Portal、彈窗、定位)與 SSO/跳轉上偶有相容性摩擦。
- 期望平台朝「共享設計系統、單例 context、host 統一供應認證/i18n、子應用可無重整導航」演進。

#### 決策(Decision)
1. 採 **Module Federation** 取代 Wujie 作為微前端整合機制。
2. 建置工具沿用 **Vite**,MF 外掛採 **`@module-federation/vite`**(官方 MF 2.0 系,提供 runtime 動態載入與 shared 協商)。
   - 備案:`@originjs/vite-plugin-federation`(較輕量但 runtime 動態能力與維護活躍度較弱)。
3. **Host 集中供應**共享 context(Auth / Locale / Permission),remote 消費而非自建。
4. remote 對外 **`exposes` 一個純 React 元件**(不含自己的 `BrowserRouter`),standalone 開發時用薄殼自帶 provider + router。
5. 模組註冊由 DB 驅動(沿用),欄位擴充 `remote_entry`/`scope`/`exposed_module`,並新增 `integration` 旗標支援**雙模式過渡**。
6. 採**漸進式遷移**:host 同時支援 wujie 與 mf 兩條載入路徑,逐模組切換,先以 `hycert-ui` 作 PoC 樣板。

#### 取捨(Consequences)

**正面**
- ui-kit/react 單例 → bundle 變小、context 可跨 host/remote 共享,host 能統一供應認證與 i18n。
- 子應用可參與同一 react-router → 無重整導航、狀態保留、URL 一致。
- 解掉 D1/D2:認證與 API base 改由 host 經 context/props 明確注入,不再依賴隱性同源全域狀態。

**負面 / 風險**
- **失去 CSS/JS 隔離**:Tailwind utility、preflight、全域樣式會衝突 → 需文件 5 的 scope/prefix 策略(本案最大技術風險)。
- **版本耦合上升**:react / ui-kit 須跨 app 對齊主版本;singleton 版本不符會 runtime 報錯或降級。
- ui-kit 須改為有版本號的 ESM build 產物(目前是 source 形式)。
- remote 故障的隔離性變差(共享 runtime)→ 需 error boundary + remote 載入失敗降級(文件 3)。
- 團隊需建立 MF 心智模型(shared scope、eager、requiredVersion)。

**已評估但未採用的方案**
- *維持 Wujie + 補 props 通道*:能解 D1/D2,但 ui-kit 重複打包、context 不可共享、無重整導航三項仍無解 → 不符演進目標。
- *single-spa*:生態成熟但樣板較重,且 shared runtime 仍需自行處理,相對 MF 無額外優勢。
- *iframe 純隔離*:隔離最強但體驗/整合最差,與目標相反。

#### 待決問題(Open Questions,交由後續文件定案)
- Q1 路由:remote 共用 host 的 react-router(方案 A,巢狀路由)還是各自帶 router 僅同步 URL(方案 B)?→ **文件 6**。
- Q2 樣式:Tailwind 全域 prefix vs `@layer` 隔離 vs ui-kit 預先編譯 CSS?→ **文件 5**。
- Q3 react 是否 eager 於 host;ui-kit 版本協商策略(strict 或 loose)?→ **文件 4**。
- Q4 認證注入:純共享 context 還是 context + `loadRemote` 時帶 props?401/refresh 統一點放哪?→ **文件 7**。
- Q5 remoteEntry 佈署與快取破壞策略(版本化檔名 vs DB 帶版本)?→ **文件 3 / 9**。

#### 落地里程碑(概要,細節見文件 9)
1. **M0 PoC**:host 動態載入 `hycert` remote,驗證單例/樣式/認證/路由四項皆通(文件 10 驗收清單)。
2. **M1 雙模式**:host 支援 `integration` 旗標,`hycert` 切 mf,其餘維持 wujie。
3. **M2 逐模組遷移**:其他子應用依序改造。
4. **M3 移除 Wujie**:確認全數遷移後下架舊路徑。

---

## 附:文件地圖

| 文件 | 主題 | 解決的 Open Question |
|------|------|---------------------|
| 1 | AS-IS 現況盤點 | — |
| **2** | **TO-BE + ADR(本文)** | — |
| 3 | Host↔Remote 整合契約 | Q5 |
| 4 | 共享依賴與單例策略 | Q3 |
| 5 | Tailwind/CSS 隔離策略 | Q2 |
| 6 | 路由整合契約 | Q1 |
| 7 | 認證與多租戶傳遞 | Q4 |
| 8 | Remote 改造指南(hycert 樣板)| — |
| 9 | 漸進式遷移與相容策略 | — |
| 10 | PoC 驗收清單 | M0 |
