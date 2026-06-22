# 文件 4 — 共享依賴與單例策略

> 解決 ADR Open Question **Q3**:`react` 是否 eager 於 host;`@hysp/ui-kit` 的版本協商策略。
> 這是 MF 最容易 runtime 爆炸、也最容易被低估的一份。離開 Wujie 沙箱後,host 與 remote 跑在**同一個 JS runtime**,「哪些套件共用同一份、版本怎麼協商」決定了系統能不能起來。
>
> 依據:文件 1(AS-IS)、文件 2(ADR)。
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 為什麼這份最關鍵

Wujie 下每個 remote 在獨立 JS context,各自打包一份 `react`/`ui-kit` **互不干擾**(文件 1 §4)。MF 把這個前提反過來:

- 多份 `react` 同時存在 → **hooks 立刻炸**(`Invalid hook call` / `dispatcher is null`)。
- `@hysp/ui-kit` 若非單例 → host 建立的 `LocaleProvider` context 與 remote `import` 到的是**兩個不同 context 物件**,`useLocale()` 在 remote 永遠拿 default value(文件 1 §4 描述的「context 不可跨界」會重演,只是這次我們**需要**它可跨界)。

所以 MF 的 `shared` 設定不是優化,是**正確性前提**。

---

## 2. 共享清單與設定

| 套件 | singleton | eager | requiredVersion | 理由 |
|------|:---------:|:-----:|-----------------|------|
| `react` | ✅ | ✅(host)| `^19`(strict)| 多份必炸 hooks;eager 確保 host 啟動即就緒,remote 不需自帶 |
| `react-dom` | ✅ | ✅(host)| `^19` | 與 react 綁定同版 |
| `@hysp/ui-kit` | ✅ | host eager | 見 §4 版本策略 | context/`PLATFORM_STORAGE_KEYS` 須同一實例 |
| `react-router-dom` | ✅ | ✅(host)| `^7`(對齊現況)| 若採共用路由(文件 6 方案 A)必須同一份;Router context 否則斷裂 |
| `js-cookie` | ⛔(一般 shared)| ❌ | `^3` | 無狀態工具,版本相容即可,不需單例 |
| `lucide-react` | ⛔ | ❌ | `^0.4xx` | 純 icon,重複載入只是體積問題,不影響正確性 |

> 慣例:**有 React context / 模組級單例狀態的 → singleton;純函式工具 → 一般 shared。**

### MF host 設定骨架(`@module-federation/vite`)
```ts
// hyadmin-ui/vite.config.ts(host)
federation({
  name: 'hyadmin',
  remotes: {},                    // 改為 runtime 動態註冊(見文件 3),非編譯期寫死
  shared: {
    react:           { singleton: true, eager: true, requiredVersion: '^19' },
    'react-dom':     { singleton: true, eager: true, requiredVersion: '^19' },
    'react-router-dom': { singleton: true, eager: true, requiredVersion: '^7' },
    '@hysp/ui-kit':  { singleton: true, eager: true },
    'js-cookie':     { requiredVersion: '^3' },
  },
})
```

### MF remote 設定骨架
```ts
// hycert-ui/vite.config.ts(remote)
federation({
  name: 'hycert',
  filename: 'remoteEntry.js',
  exposes: { './App': './src/expose/App.tsx' },   // 見文件 8
  shared: {
    react:           { singleton: true, requiredVersion: '^19' },  // 注意:remote 端不 eager
    'react-dom':     { singleton: true, requiredVersion: '^19' },
    'react-router-dom': { singleton: true, requiredVersion: '^7' },
    '@hysp/ui-kit':  { singleton: true },
    'js-cookie':     { requiredVersion: '^3' },
  },
})
```

**eager 規則**:**只在 host eager**(host 同步載入提供者),remote **不 eager**(避免每個 remote 都把 react 塞進自己的 initial chunk,失去共享意義)。

---

## 3. ⚠️ 前置改造:@hysp/ui-kit 必須先變成「有版本的 build 產物」

這是 §2 能成立的硬前提,現況**還沒滿足**:

- `hyui-kit/package.json:6-7` — `main`/`types` 指向 **`./src/index.ts`(原始碼)**。
- `hyui-kit/tsup.config.ts` — 其實**已經會 build** esm+cjs+dts、`external: ['react','react-dom']`、但**不打包 CSS**。
- 各 app 透過 `file:` 依賴 + `vite-tsconfig-paths` **直接吃原始碼**,從未用到 dist。

MF 的 `shared` 以 **套件名 + 版本號** 做協商。吃原始碼 / `file:` 連結會讓「版本」概念失效,singleton 無從判斷。**改造項:**

1. `package.json` 的 `main`/`module`/`types` 改指向 **`dist/`**(tsup 產物),保留 `exports` map。
2. 每次改動**遞增 `version`**(MF 用它做 requiredVersion 協商與相容判斷)。
3. host 與所有 remote 依賴 **同一個版本範圍**(monorepo 內可用 workspace 協定鎖定,但發佈/佈署時要是同一個實際版本)。
4. `external: ['react','react-dom']` 維持(已正確)——ui-kit 不可自帶 react。
5. CSS 處理見 **文件 5**(ui-kit 不打包 CSS 的決策會在那邊重新評估)。

> 換句話說:**ui-kit 從「monorepo 內共享原始碼」升級成「有版本號的共享套件」,是文件 4 的最大工程量,且擋住 PoC**。

---

## 4. 版本協商策略(Q3 決議)

兩種模式:

- **strict(嚴格)**:`requiredVersion` 不符就報錯不啟動。安全但脆——任一 remote 落後即全掛。
- **loose / 降級(預設行為)**:取最高相容版本,不相容時 MF 印警告並各自載自己的版本(等於放棄單例)。對 `react`/`ui-kit` 來說**降級=context 斷裂的隱性 bug**,比直接報錯更難查。

**決議建議:**
- `react` / `react-dom` / `react-router-dom` / `@hysp/ui-kit` → **`singleton: true` 且 `strictVersion: true`**(寧可 fail-fast,不要默默載兩份造成 hooks/context 詭異錯誤)。
- 用 **caret 範圍**(`^19`、`^7`)允許 patch/minor 漂移,**major 對齊**作為硬規則寫進文件 9 的遷移約束。
- 工具側工具(`js-cookie`/`lucide`)→ loose 即可。

---

## 5. 風險與驗證

| 風險 | 症狀 | 對策 |
|------|------|------|
| 多份 react | `Invalid hook call`、`useContext` 回 default | host eager singleton + strictVersion;PoC 用 `react.version` 在 host/remote 各印一次比對(文件 10)|
| ui-kit 非單例 | remote `useLocale()` 永遠英文 default、Toaster 不顯示 | ui-kit singleton;PoC 驗 host `LocaleProvider` 能否被 remote 元件讀到 |
| ui-kit major 不一致 | runtime 警告 + 行為分歧 | major 對齊規則 + strictVersion |
| react-router 兩份(若採方案 A 卻沒設 singleton)| `useNavigate` 報 "outside Router" | router 設 singleton;或改文件 6 方案 B 各自帶 router |
| ui-kit 仍吃原始碼 | MF 無法以版本協商,singleton 失效 | §3 前置改造(dist + 版本號)|

**最小驗證(進 PoC 驗收清單,文件 10):**
1. host 與 remote console 各印 `React.version` 與 ui-kit 版本 → 必須相同來源(同一物件/同一版)。
2. host 包 `<LocaleProvider defaultLocale="zh-TW">`,remote 元件呼 `useLocale()` → 應拿到 zh-TW 字典而非 default。
3. remote 觸發 `toast()` → host 的單一 `<Toaster>` 能顯示(驗證 sonner 也是同一實例)。

---

## 6. 與其他文件的銜接

- §3 ui-kit build 改造 → 影響 **文件 5(CSS)**(是否同時讓 ui-kit 預編譯 CSS)與 **文件 9(遷移約束:major 對齊)**。
- router singleton 取決於 **文件 6** 路由方案(A 需 singleton;B 可放寬)。
- host 供應的 `LocaleProvider`/`AuthProvider` 為單例,是 **文件 7(認證注入)** 的載體。
