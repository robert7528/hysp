# 文件 5 — Tailwind / CSS 隔離策略

> 解決 ADR Open Question **Q2**:離開 Wujie ShadowDOM 後,Tailwind utility / preflight / 全域樣式如何避免衝突。
> 這是 ADR 標註的**本案最大技術風險**:Wujie 的 CSS 隔離是「免費」的,MF 沒有,必須用設計把它補回來。
>
> 依據:文件 1(AS-IS §4/D5)、文件 4(ui-kit build 改造)。
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 問題本質

現況(文件 1 §4、本次盤點):

- **ui-kit 不打包 CSS**:`hyui-kit/tsup.config.ts:11` 明寫「No CSS bundling — Tailwind classes must be scanned by consumer's bundler」。
- **每個 app 各自跑一套完整 Tailwind**:
  - `hycert-ui/tailwind.config.ts` → `presets: [hyspPreset]`,`content` 含 `./src` 與 `./node_modules/@hysp/ui-kit/src`。
  - `hyadmin-ui` 同樣模式。
  - 各自 emit 完整 stylesheet:**`@tailwind base`(含 preflight)+ components + utilities**(`hyui-kit/styles/globals.css:1-3`)。
- **設計 token 走 CSS 變數**:`globals.css` 的 `:root` / `.dark` 定義 `--background`、`--primary`…(`globals.css:5-30`),preset 的顏色全是 `hsl(var(--x))`(`tailwind.preset.ts:14-47`)。

Wujie 下這些各自關在 ShadowDOM,互不可見。**MF 共享同一份 document**,於是:

| 衝突源 | 後果 |
|--------|------|
| 多份 `@tailwind base`(preflight)| 重複的全域 reset(`*{}`、`h1`、`button`…)互相覆蓋,且**載入順序不可控** |
| 同名 utility(`.flex`、`.p-4`、`.text-sm`)由不同 app emit | 內容相同還好,但**版本/設定一旦分歧就視覺漂移**;CSS 後載者勝,順序由 MF chunk 載入決定 = 不可預測 |
| 多份 `:root` CSS 變數 | 若 host 與 remote 的 token 值不同,**後定義者覆蓋全域**,殃及彼此 |
| 重複 stylesheet | 體積膨脹 |

核心矛盾:**utility-first CSS 是全域命名空間**,天生與「多 app 同頁共存」相剋。

---

## 2. 候選方案

### 方案 A — Tailwind `prefix`(各 app 加前綴)
每個 app 設 `prefix: 'cert-'` / `'adm-'`,utility 變 `cert-flex`、`adm-p-4`。
- ✅ utility 完全隔離,不互撞。
- ❌ **ui-kit 元件的 className 寫死**(`button.tsx` 等用 `cn("inline-flex …")`),prefix 後 ui-kit 自己的 class 也得跟著變 → ui-kit 必須綁定某個 prefix,**破壞共享**。對共用 ui-kit 的架構幾乎不可行。
- 結論:**不採用**(與單例 ui-kit 衝突)。

### 方案 B — ui-kit 預編譯 CSS + 各 app 只負責自身 utility(建議主軸)
讓 **ui-kit 自己 build 出一份編譯好的 CSS**(含它用到的所有 utility + base token),由 **host 載入一次**;remote 不再重複掃描 ui-kit 原始碼。
- ui-kit:`tsup`/獨立 Tailwind build 產 `dist/ui-kit.css`(只含 ui-kit 元件實際用到的 class + `:root` token),`exports['./styles']` 指它。
- host:`import '@hysp/ui-kit/styles'` **一次**,提供 preflight + token + 所有 ui-kit 元件樣式。
- 各 app 的 Tailwind **關掉 preflight**(`corePlugins: { preflight: false }`),且 `content` **移除** ui-kit 原始碼路徑 → 各 app 只 emit「自己 JSX 額外用到、ui-kit 沒涵蓋」的 utility。
- ✅ preflight 與 token 單一來源(host),消除重複 reset 與 `:root` 打架。
- ✅ ui-kit 維持單例、不需 prefix。
- ⚠️ 殘留風險:各 app 自有 utility 仍同名共存——但內容由**同一個 hyspPreset** 決定,值一致 → 同名同義,覆蓋順序不影響結果。
- 配合 **文件 4 §3**(ui-kit 改為有版本的 build 產物)一起做,工程量共用。

### 方案 C — Tailwind `important: '#scope'` + 各 remote 掛根容器 id
host 給每個 remote 一個 `<div id="app-cert">`,remote Tailwind 設 `important: '#app-cert'`,utility 變 `#app-cert .flex{}` 提高權重並限定範圍。
- ✅ 不需改 ui-kit className;範圍限定在容器內。
- ❌ ui-kit 的 class 若由 host 載,權重規則不一致會錯亂;`important` 對 Radix Portal(彈窗/下拉**渲染到 body 外**)無效——`popover.tsx`/`tooltip.tsx`/`dialog.tsx` 都用 Portal。
- 結論:可作 B 的**輔助**(處理 app 自有 utility 的範圍),不單獨用。

### 方案 D — 回退到 CSS Modules / scoped 方案
重寫元件樣式為 scoped。工程量過大、丟掉 Tailwind 生態。**不採用**。

---

## 3. 決議建議

**主軸採方案 B**,以 C 的根容器 id 作為「app 自有 utility」的輔助範圍控制:

1. **ui-kit 預編譯 CSS**(文件 4 §3 一起做):產 `dist/ui-kit.css`,含 ui-kit 元件樣式 + `:root`/`.dark` token + preflight。
2. **host 載入唯一一份 base**:`import '@hysp/ui-kit/styles'`,**只有 host 載**。
3. **各 remote 關 preflight、移除 ui-kit content 來源**:remote 的 Tailwind 僅 emit 自身 JSX 的 utility,且全部走 `hyspPreset`(token 值與 host 一致)。
4. **token 單一來源**:`:root` 變數只由 host 那份 CSS 定義;remote 不得各自再宣告 `:root`(避免覆蓋)。dark mode 由 host 在根節點切 `.dark` class(`darkMode: ['class']`,preset 已設)。
5. **Radix Portal 對策**:host 提供一個共用 portal container,或確認 ui-kit 樣式由 host 全域載入後,Portal 內容(渲染到 body)能吃到同一份 ui-kit CSS → 因為 §2 base 由 host 全域載,Portal 內容天然 cover,**這點 B 方案本來就解掉**(C 的 `important: '#scope'` 反而會漏 Portal,故 C 僅用於非 Portal 的 app utility)。

---

## 4. 待驗證(進 PoC 文件 10)

1. host 載 ui-kit base CSS 後,remote 元件(含 `Dialog`/`Select`/`Tooltip` 這些 Portal 元件)外觀正確、無缺樣式。
2. host 與 remote 各自的純 Tailwind utility(如 `grid-cols-3`)能並存且不互相覆蓋成錯誤值。
3. 切 `.dark` → host 與 remote 同步變深色(驗證 token 單一來源 + class 策略)。
4. DevTools 檢查:`@tailwind base`/preflight **只出現一次**;`:root --primary` **只有一個定義**。
5. remote standalone 模式仍能獨立顯示(此時 remote 自己載一份完整 CSS,見文件 8)。

---

## 5. 對其他文件的影響

- **文件 4 §3**:ui-kit 改 build 產物時,**順手加 CSS 預編譯**(B 方案的 1),兩件事同一個 PR。
- **文件 8**:remote 改造時要區分「standalone(自載完整 CSS)」與「MF 模式(不載 base,靠 host)」兩種入口。
- **文件 9**:遷移約束加一條「token 變更只能改 ui-kit 那份 `:root`,不得在各 app 重宣告」。
- **文件 10**:本文 §4 五項併入 PoC 驗收。

---

## 6. 一句話總結

> Wujie 用「ShadowDOM 把每個 app 的 CSS 關起來」解衝突;MF 改用「**把共用樣式收斂成 host 載入的單一來源(ui-kit 預編譯 CSS + 單一 token),各 app 只 emit 自己獨有的 utility**」解衝突。隔離的責任從框架 runtime 移到了 build 設計。
