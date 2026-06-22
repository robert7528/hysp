# 文件 3 — Host ↔ Remote 整合契約

> 定義 host(`hyadmin-ui`)如何在 **runtime 從 DB 動態載入** remote(`hycert-ui` 等)、`Module` 註冊 schema 如何擴充、`exposes` 命名規範、以及 remote 載入失敗的降級。解決 ADR Open Question **Q5**(remoteEntry 佈署與快取破壞)。
>
> 這是文件 6(路由)、7(認證)、8(改造)的共同上游——它們都掛在這份契約定義的載入點上。
> 依據:文件 1(AS-IS §2)、文件 2(ADR A.3)、文件 4(shared)。
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 契約全景

```
DB module registry (擴充 schema)
   │  GET /api/v1/modules  → host ModuleProvider 載入清單
   ▼
host 啟動時:依清單 registerRemotes([{ name, entry }])  ← runtime,非編譯期
   │
使用者進 /hyadmin/app/cert/list
   ▼
RemoteOutlet
   ├ integration === 'wujie' → 舊路徑 <WujieReact/>(過渡期保留)
   └ integration === 'mf'    → loadRemote('hycert/App')
                                 │  動態 import remoteEntry.js
                                 ▼
                            <RemoteErrorBoundary>
                               <Suspense fallback={Loader}>
                                  <CertApp ...injected props/>   ← 見文件 7
                               </Suspense>
                            </RemoteErrorBoundary>
```

**三條鐵則:**
1. **remote 清單來自 DB,不寫死在 `vite.config`**(沿用現況 DB 驅動,文件 1 §2.2)。MF remotes 必須**在 runtime 註冊**。
2. host 對 remote 的唯一耦合是 **三元組 `(scope, exposedModule, remoteEntry URL)`**,其餘走契約。
3. remote 掛掉 **不得拖垮整個 shell**(共享 runtime 下這是新風險,文件 1 D 沒有的)。

---

## 2. Module schema 擴充

### 2.1 新欄位
現況 `src/types/module.ts:1` 的 `Module` 擴充(對應 DB migration 與 `/hyadmin-api`):

```ts
interface Module {
  // ── 既有(保留)──
  id; name; display_name; icon; route; api_url;
  description; sort_order; enabled; created_at; updated_at;

  // ── 新增:MF 整合三元組 ──
  remote_entry: string    // remoteEntry.js 絕對 URL,例 "https://cdn.hysp/hycert/remoteEntry.js"
  scope: string           // MF container 名(= remote vite federation 的 name),例 "hycert"
  exposed_module: string  // 例 "./App"

  // ── 新增:過渡控制 ──
  integration: 'wujie' | 'mf'   // 載入路徑切換(預設 'wujie',逐模組改 'mf')

  // ── 既有 url:語意收斂 ──
  url: string             // wujie 模式進入點(沿用);mf 模式可空,僅 standalone 開發參考
}
```

> **`name` 與 `scope` 的關係**:建議令 `scope === remote 的 federation name`(如 `hycert`),`name` 維持現有的人類可讀模組名。若兩者目前混用,遷移時釐清:**`scope` 是技術識別碼,對應 `vite.config federation.name`**。

### 2.2 後端與後台
- **DB migration**:`modules` 表加 `remote_entry`、`scope`、`exposed_module`、`integration`(預設 `'wujie'`)。
- **API**:`GET /api/v1/modules`(`api.ts:82`)回傳值帶上新欄位即可,**形狀不變**(host 端只多讀幾個欄位)。`adminModulesApi`(`api.ts:100`)CRUD 透傳。
- **後台表單**:`pages/admin/modules-new.tsx` 與 `module-edit.tsx` 加四個欄位輸入(`remote_entry`/`scope`/`exposed_module` + `integration` 下拉)。`integration='wujie'` 時隱藏 MF 三欄、顯示 `url`;`='mf'` 時相反。

### 2.3 相容性
- 既有資料 migration 後 `integration` 預設 `'wujie'` → **行為完全不變**,舊機制續跑。
- 改某模組為 `'mf'` 且填妥三元組 → host 該模組走新路徑。**逐模組、可回滾**(把 `integration` 改回 `'wujie'` 即還原)。

---

## 3. Runtime 動態註冊與載入

`@module-federation/vite` 提供 runtime API(`@module-federation/runtime`):

```ts
// hyadmin-ui/src/lib/remotes.ts
import { registerRemotes, loadRemote } from '@module-federation/runtime'

/** host 取得 DB modules 後呼叫一次 */
export function registerMfModules(modules: Module[]) {
  const mf = modules.filter((m) => m.integration === 'mf' && m.enabled)
  registerRemotes(
    mf.map((m) => ({
      name: m.scope,                       // 'hycert'
      entry: withCacheBust(m.remote_entry) // 見 §5
    })),
    { force: true }                        // 允許後續更新覆蓋(熱更新模組清單)
  )
}

/** 載入某模組的 exposed 元件 */
export async function loadModuleComponent(m: Module) {
  return loadRemote<{ default: React.ComponentType<RemoteProps> }>(
    `${m.scope}/${stripDotSlash(m.exposed_module)}`  // 'hycert/App'
  )
}
```

時機:`ModuleProvider.loadModules()`(`module-context.tsx:33`)成功後,立刻 `registerMfModules(data.modules)`。**註冊是冪等的、可重入**(模組清單變更時 re-register)。

> **編譯期 `remotes` 留空**:`vite.config federation.remotes = {}`(文件 4 §2 已示),所有 remote 走 runtime 註冊——這是「DB 驅動」與「MF」並存的關鍵接法。

---

## 4. 取代 AppContainer / AppPage

現況 `app-container.tsx`(`<WujieReact/>`)與 `app-page.tsx` 改為依 `integration` 分流:

```tsx
// hyadmin-ui/src/pages/app-page.tsx(改造後骨架)
const mod = modules.find((m) => m.route === route && m.enabled)
if (!mod) return <ModuleNotFound />

if (mod.integration === 'wujie') {
  return <AppContainer key={`${mod.name}-${subPath}`} module={mod} url={subAppUrl} />  // 舊路徑原樣
}

// mf 路徑
return (
  <RemoteErrorBoundary moduleName={mod.display_name} key={mod.scope}>
    <Suspense fallback={<Loader2 className="animate-spin" />}>
      <RemoteOutlet module={mod} subPath={subPath} />
    </Suspense>
  </RemoteErrorBoundary>
)
```

`RemoteOutlet`:`React.lazy(() => loadModuleComponent(module))`,把 host 注入的 props(認證/locale/api base/subPath,**詳見文件 7**)傳給 remote 的 `./App`。

> **subPath 處理改變**:Wujie 靠 `key` re-mount(文件 1 §2.3 / D3);MF 下 subPath 改**以 prop / 共用 router 傳入**,remote 內部無重整切換(**文件 6 定案**)。本文先把 subPath 當 prop 往下帶,具體路由整合由文件 6 決定。

---

## 5. remoteEntry 佈署與快取破壞(Q5 決議)

`remoteEntry.js` 是 MF 的入口 manifest,**一旦被瀏覽器快取住舊版,會載到舊 chunk** → 必須有破壞策略。

**決議:採「DB 帶版本 + query 破壞」為主,檔名 hash 為輔。**

1. **remote 佈署**產出 `remoteEntry.js`(穩定檔名)+ 內部 chunk 帶 content hash(Vite 預設)。`remoteEntry.js` 自身設 **`Cache-Control: no-cache`**(每次 revalidate),內部 hash chunk 可長快取。
2. **DB `remote_entry` 可帶版本 query**:`...//hycert/remoteEntry.js?v=1.4.2`。發版時更新 DB 的版本 → host 下次載清單就指到新 entry,強制破壞快取。
   ```ts
   function withCacheBust(entry: string) {
     return entry  // 版本已含在 DB URL 的 ?v=,無需再加;若 DB 未帶則附建置時間戳
   }
   ```
3. **獨立佈署不變**:remote 可獨立發版,只要更新它的 `remote_entry`(或其 `?v=`),host **無需重新建置**——保留 Wujie 時代「子應用獨立上線」的優點。
4. **CORS**:remote 與 host 不同源時,remoteEntry 與 chunk 的回應需 `Access-Control-Allow-Origin`(現況 `hycert-ui/vite.config.ts:10` 已開 dev `cors: true`,production 由 CDN/反代設定)。

---

## 6. 降級與隔離(共享 runtime 的新風險)

Wujie 的 iframe 讓 remote crash 不波及 host;MF 共享 runtime,**remote 載入失敗或 render 拋錯會冒泡到 host**。對策:

| 失敗類型 | 對策 |
|----------|------|
| `remoteEntry` 載入失敗(網路/404/CDN 掛)| `loadRemote` reject → `RemoteErrorBoundary` 顯示「模組暫時無法載入 + 重試鈕」,**shell 其餘部分照常** |
| remote render 期間拋錯 | `RemoteErrorBoundary`(React error boundary)攔截,不讓整頁白屏 |
| shared 版本不符(strictVersion fail)| 屬部署期問題,進 §7 驗證攔截,不應上線 |
| 模組被停用 | DB `enabled=false` → host 不註冊、不顯示(沿用現況語意)|

`RemoteErrorBoundary` 是**每個 remote 一個邊界**(`key={mod.scope}`),確保故障隔離在單一模組。

---

## 7. 契約檢核表(remote 端要遵守 / host 端要保證)

**Remote 必須提供:**
- [ ] `vite.config federation`:`name === DB.scope`、`filename: 'remoteEntry.js'`、`exposes` 含 DB.exposed_module(預設 `'./App'`)。
- [ ] exposed 模組 **default export 一個 React 元件**,接受契約 props(文件 7 定義的 `RemoteProps`)。
- [ ] shared 設定與文件 4 §2 一致(react/react-dom/router/ui-kit singleton)。
- [ ] remoteEntry 與 chunk 的 CORS / Cache-Control 符合 §5。

**Host 必須保證:**
- [ ] runtime `registerRemotes`,編譯期 `remotes` 留空(§3)。
- [ ] 依 `integration` 分流,`'wujie'` 路徑零改動(§4)。
- [ ] 每個 mf 模組包 `RemoteErrorBoundary` + `Suspense`(§6)。
- [ ] 注入契約 props(文件 7)。

---

## 8. exposes 命名規範

| 用途 | exposes key | 說明 |
|------|-------------|------|
| 模組主入口(必須)| `./App` | default export React 元件,host 載這個 |
| 獨立工具/區塊(選用)| `./widgets/HealthCard` | 若 host 首頁要嵌 remote 的小區塊,可額外 expose |
| 型別(選用)| 由 `@module-federation/vite` 的 dts 外掛產 | host 取得 remote props 型別,非必要 |

規範:**一律 `./PascalCase` 或 `./namespace/PascalCase`**,`./App` 為保留名(每個 remote 都要有)。

---

## 9. 對其他文件的銜接

- **文件 6**:§4 的 subPath 與 `RemoteOutlet` 的路由整合(prop vs 共用 router)在那邊定案。
- **文件 7**:`RemoteProps` 的完整定義(認證 token、tenant、api base、locale、subPath)。
- **文件 8**:remote 端 `src/expose/App.tsx` 與 `vite.config federation` 的實作範本。
- **文件 9**:`integration` 旗標的逐模組遷移順序與回滾流程。
- **文件 10**:§7 檢核表 + §6 降級行為併入 PoC 驗收。
