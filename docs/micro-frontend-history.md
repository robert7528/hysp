# HySP 微前端架構變更歷史

## 架構概述

hyadmin-ui 作為平台 Shell（父應用），透過微前端技術掛載各模組的 `-ui` 子應用（如 hycert-ui）。本文件記錄架構選型的演進過程、遇到的問題與最終決策。

---

## 時間線

| 日期 | 事件 |
|------|------|
| 2026-03 初 | 採用 micro-app 預設模式 + Next.js |
| 2026-03-18 | POC 驗證 micro-app 各模式，選定 iframe 模式 |
| 2026-03-18 | hycert-ui 從 Next.js 遷移至 Vite，改用 wujie-react |
| 2026-03-18 | hyadmin-ui 從 Next.js 遷移至 Vite + React Router v7 |
| 2026-03-18 | 評估 wujie 長期風險，確認原生 iframe 為最終備案 |

---

## 第一階段：micro-app 預設模式 + Next.js

### 技術選型
- **父應用**：hyadmin-ui（Next.js 15 App Router）
- **子應用**：hycert-ui（Next.js 15 App Router）
- **微前端框架**：`@micro-zoe/micro-app` 預設模式（JS 沙箱）

### 遇到的問題

#### 問題 1：ESM 不相容（致命）
```
Cannot use import statement outside a module
```
- **原因**：micro-app 預設模式使用 `new Function()` 包裝 JS，無法處理 ESM 的 `import` 語句
- **影響**：Vite 和 Next.js 都輸出 ESM，預設模式完全無法載入
- **結論**：預設模式不可用

#### 問題 2：inline 模式 + Next.js RSC 衝突
- **嘗試**：切換到 micro-app inline 模式
- **原因**：Next.js RSC streaming 的 `ReadableStream` 與 inline 的 `eval` 衝突
- **結論**：inline 模式不可用於 Next.js

#### 問題 3：inline + disableSandbox 無隔離
- **嘗試**：inline + `disableSandbox` 模式
- **結果**：ESM 可以載入，功能正常
- **問題**：多子應用同頁時無 JS 隔離（共享 window），未來多模組場景會衝突
- **結論**：可行但不安全，不採用

### POC 結論

| 模式 | 結果 | 原因 |
|------|------|------|
| 預設模式（JS 沙箱） | **失敗** | `new Function()` 不支援 ESM |
| inline 模式 | **失敗** | Next.js RSC streaming 衝突 |
| inline + disableSandbox | **成功但不採用** | 無 JS 隔離，多子應用不安全 |
| **iframe 模式** | **成功** | 完全隔離，所有框架相容 |

---

## 第二階段：micro-app iframe 模式 + Next.js

### 技術選型
- **父應用**：hyadmin-ui（Next.js 15 App Router）
- **子應用**：hycert-ui（Next.js 15 App Router）
- **微前端框架**：`@micro-zoe/micro-app` iframe 模式

### 遇到的問題

#### 問題 4：Next.js SSR + 微前端 500 錯誤
```
500 Internal Server Error
```
- **原因**：`<micro-app>` 自訂元素在 Server Side Rendering 時不存在，導致 hydration 失敗
- **對策**：使用 `next/dynamic` 包裝 + `ssr: false`
- **結果**：可行但需要額外包裝層

#### 問題 5：頁面重新整理時 500
- **原因**：SSR 時嘗試渲染微前端元件，但 micro-app 只能在瀏覽器端執行
- **對策**：加入 `degrade` 模式（降級為 iframe），再移除
- **結果**：反覆除錯，最終穩定但過程痛苦

#### 問題 6：所有頁面都是 `'use client'`
- **觀察**：hyadmin-ui 的 19 個頁面全部標記 `'use client'`
- **原因**：後台管理系統完全是互動式 UI，沒有 SSR 使用場景
- **結論**：Next.js 的 SSR 能力對本專案零價值，反而製造問題

---

## 第三階段：wujie-react + Vite（當前）

### 遷移動機
1. Next.js SSR 對純 SPA 後台零價值，反而造成微前端相容問題
2. hycert-ui 已成功遷移至 Vite，需統一技術棧
3. micro-app 與 ESM 的根本性不相容問題

### 技術選型
- **父應用**：hyadmin-ui（Vite 6 + React Router v7）
- **子應用**：hycert-ui（Vite 6 + React）
- **微前端框架**：`wujie-react`（騰訊無界）

### 為什麼選 wujie-react
- 原生支援 iframe 模式，與 Vite ESM 輸出完全相容
- 子應用只需提供 `__WUJIE_MOUNT` / `__WUJIE_UNMOUNT` 生命週期
- 不需要 `next/dynamic` + `ssr: false` 等 hack

### hyadmin-ui 遷移內容
| 項目 | Next.js | Vite + React Router v7 |
|------|---------|----------------------|
| 路由 | App Router（檔案系統路由） | BrowserRouter + `<Route>` 宣告式 |
| basePath | `next.config.ts` `basePath` | `vite.config.ts` `base` + `basename` |
| 認證 | `middleware.ts`（server side） | `AuthGuard` 元件（client side） |
| SSR 守衛 | `typeof window === 'undefined'` | 不需要（純 SPA） |
| 微前端載入 | `next/dynamic` + `ssr: false` | 直接 `import WujieReact` |
| 打包輸出 | `.next/standalone`（Node.js server） | `dist/`（靜態檔 + nginx） |
| 容器 | `node:20-alpine`（runtime） | `nginx:alpine`（靜態服務） |

### 當前狀態（2026-03-18 驗證）
- hyadmin-ui Shell：所有頁面正常（登入、選單、admin CRUD）
- hycert-ui 子應用：wujie 載入正常，Radix UI Select 下拉正常
- Sidebar、Breadcrumb、Header active state 皆正確

---

## 已知風險與備案

### wujie-react 的潛在問題

#### 架構設計
wujie 嘗試將三種隔離技術縫合：
- **iframe**：JS 執行環境隔離（獨立 window）
- **Shadow DOM**：CSS 樣式隔離
- **ESM**：現代模組載入

核心矛盾：iframe 裡的 JS 執行環境 ↔ Shadow DOM 在父應用的 DOM
```
iframe 裡的 document    ←→    Shadow DOM 在父應用的 document
         ↑                           ↑
   JS 在這裡執行              DOM 在這裡渲染

連接兩者需要大量 proxy 工作 → 「縫合怪」
```

#### 具體風險

| 風險 | 嚴重度 | 目前影響 |
|------|--------|---------|
| Radix UI Popover/Dialog 跨 document 定位失準 | 高 | 暫無（Select 正常） |
| wujie 已停止維護 | 中 | 暫無（功能穩定） |
| 安全漏洞無人修補 | 中 | 暫無 |

#### 觸發遷移條件（出現任何一個就換原生 iframe）
1. Radix UI 元件在子應用內定位失準
2. wujie 爆出安全漏洞無人修
3. 需要 3+ 個子應用且有互動需求

### 備案：原生 iframe

```
目前架構                          備案架構
┌─────────────┐                ┌─────────────┐
│ hyadmin-ui  │                │ hyadmin-ui  │
│  wujie-react├──載入──┐       │  <iframe>   ├──載入──┐
└─────────────┘       │       └─────────────┘       │
                ┌─────▼─────┐                 ┌─────▼─────┐
                │ hycert-ui │                 │ hycert-ui │
                └───────────┘                 └───────────┘

改動量：只需修改 app-container.tsx（唯一耦合點）
```

原生 iframe 方案：
- `<iframe src={module.url} />` 直接載入
- `ResizeObserver` + `postMessage` 處理高度自適應
- 零外部依賴
- 瀏覽器原生支援，永不過時

---

## 技術選型決策矩陣

| 方案 | JS 隔離 | CSS 隔離 | ESM 相容 | 維護狀態 | 複雜度 | 適用規模 |
|------|---------|---------|---------|---------|--------|---------|
| micro-app 預設 | JS 沙箱 | 有 | **不相容** | 活躍 | 中 | — |
| micro-app iframe | iframe | iframe | 相容 | 活躍 | 中 | 中大型 |
| wujie-react | iframe | Shadow DOM | 相容 | **停止維護** | 高 | 中大型 |
| 原生 iframe | iframe | iframe | 相容 | **瀏覽器原生** | 低 | 小中型 |
| Module Federation | 無 | 無 | 原生 | Webpack/Vite 官方 | 中 | 大型 |

**HySP 目前選擇**：wujie-react（短期），原生 iframe（長期備案）

**選擇依據**：後台管理系統 + 子應用少（1-2 個）+ 無跨應用互動 → 不需要理論最優架構，穩定可用即可。
