# 文件 10 — PoC 驗收清單(M0)

> 一個 spike:host 動態載入 `hycert` remote,逐項驗證單例 / 樣式 / 認證 / 路由 / 降級皆通。**全綠才算 M0 完成、可進 M1**(文件 9)。
> 彙整文件 3–8 的「驗證」段落為一張可勾選清單。
>
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 0. PoC 範圍

- ui-kit 完成 build 改造(dist + 版本 + 預編譯 CSS + RemoteProps)。
- host(`hyadmin-ui`)具備雙路徑骨架 + runtime `registerRemotes` + RemoteOutlet + ErrorBoundary。
- `hycert-ui` 依文件 8 改造完成。
- DB 一筆 `hycert` 模組設 `integration='mf'` + 三元組。

---

## A. 共享單例(文件 4)
- [ ] A1 host 與 remote console 各印 `React.version` → **相同**;`useState` 等 hooks 在 remote 正常(無 `Invalid hook call`)。
- [ ] A2 host 與 remote 取得的 `@hysp/ui-kit` 為**同一版本/同一實例**(印版本或物件 identity 比對)。
- [ ] A3 host 包 `LocaleProvider defaultLocale="zh-TW"`,remote 元件 `useLocale()` → 拿到 **zh-TW 字典**,非 default。
- [ ] A4 remote 觸發 `toast()` → host 單一 `<Toaster>` **能顯示**(sonner 同實例)。
- [ ] A5 故意把 remote 的 react 設成不相容版本 → strictVersion **fail-fast 報錯**(驗證守門有效),修正後恢復。

## B. 樣式 / Tailwind(文件 5)
- [ ] B1 remote 元件(含 `Dialog`/`Select`/`Tooltip` 等 **Radix Portal**)外觀正確、無缺樣式。
- [ ] B2 DevTools:`@tailwind base`/preflight **只出現一次**;`:root --primary` **只有一個定義**。
- [ ] B3 host 與 remote 各自的純 utility(如 `grid-cols-3`)並存且不互相覆蓋成錯值。
- [ ] B4 切 `.dark` → host 與 remote **同步**變深色。
- [ ] B5 remote standalone 模式外觀正常(自載完整 CSS)。

## C. 路由(文件 6)
- [ ] C1 host 內點 remote 子頁連結(`list`→`csrs`)→ URL 變、**無整頁重整、無 re-mount**(元件 `useEffect` log 驗證未重新 mount)。
- [ ] C2 瀏覽器前進/後退跨 host 頁與 remote 子頁皆正確。
- [ ] C3 host 側欄/麵包屑在 remote 子頁正確高亮(讀同一 location)。
- [ ] C4 深連結直接開 `/hyadmin/app/cert/acme/orders` → 正確落子頁。
- [ ] C5 remote standalone 仍能獨立切頁。

## D. 認證 / 多租戶(文件 7)
- [ ] D1 host 登入後進 remote,API 請求帶正確 `Authorization` + `X-Tenant-ID`(來自**注入**,非 remote 自解)。
- [ ] D2 改 `Module.api_url` → remote 實際 API base **跟著變**(驗 D1 缺口已修)。
- [ ] D3 模擬 401 → 走 host `onUnauthorized`(轉 login),remote **不自行**決定轉址。
- [ ] D4 host 切語系 → remote 同步(呼應 A3)。
- [ ] D5 remote standalone 以 mock `RemoteProps` 可獨立跑。

## E. 整合契約 / 降級(文件 3)
- [ ] E1 host runtime `registerRemotes` 從 DB 清單載入(編譯期 `remotes` 為空)。
- [ ] E2 `integration='wujie'` 的其他模組**行為完全不變**(雙模式並存)。
- [ ] E3 把 `remote_entry` 指向不存在 URL → `RemoteErrorBoundary` 顯示錯誤 + 重試,**shell 其餘正常**(故障隔離)。
- [ ] E4 remote render 期間故意拋錯 → ErrorBoundary 攔截,**不白屏**。
- [ ] E5 `enabled=false` → host 不註冊、不顯示。
- [ ] E6 更新 `remote_entry` 的 `?v=` → host 載到新版(快取破壞有效)。

## F. 改造完整性(文件 8)
- [ ] F1 `hycert-ui` grep **無** `__WUJIE` / `__POWERED_BY_WUJIE__` 殘留。
- [ ] F2 `cert-router.tsx` 已刪除,路由改 `<Routes>`。
- [ ] F3 `cert-api.ts` 不再自讀 storage / 自解 JWT,改吃 `configureCertApi`。
- [ ] F4 `pnpm build` 產出 `dist/remoteEntry.js` + chunks。

---

## 結論判定
- **全綠** → M0 完成,進 M1(hycert 正式切 mf 上 production)。
- **任一紅** → 回對應文件章節修正後重驗。
- 特別關注 **B(樣式,ADR 標的最大風險)** 與 **A(單例,最易隱性 bug)** 兩組——這兩組過了,MF 架構基本成立。

---

## 附:四項核心一句話
> **單例通**(react/ui-kit/router 同一份)→ **樣式通**(host 單一 CSS 來源)→ **認證通**(host 注入、remote 純消費)→ **路由通**(共用 router、無重整)→ MF 取代 Wujie 成立。
