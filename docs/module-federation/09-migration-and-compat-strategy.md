# 文件 9 — 漸進式遷移與相容策略

> 如何在不中斷現有 Wujie 子應用的前提下,逐模組切到 MF;含過渡期雙模式、遷移順序、回滾、佈署、本機 dev、版本約束。
>
> 依據:文件 2(ADR 里程碑 M0–M3)、文件 3(integration 旗標)、文件 4(版本約束)。
> 最後更新:2026-06-16
> 狀態:Proposed

---

## 1. 核心策略:DB 旗標驅動的雙模式並存

關鍵賦能機制是 `Module.integration: 'wujie' | 'mf'`(文件 3 §2)。host 同時保留兩條載入路徑,**每個模組獨立切換、獨立回滾**:

```
integration='wujie' → <WujieReact/>（現況零改動）
integration='mf'    → loadRemote()（新路徑）
```

- migration 後所有模組預設 `'wujie'` → **上線即等同現況,零風險**。
- 改單一模組為 `'mf'` 並填妥三元組 → 只有該模組走新路徑。
- 出問題改回 `'wujie'` → 即時回滾,**不需重新部署 host**。

---

## 2. 里程碑與遷移順序

| 里程碑 | 內容 | 完成判準 |
|--------|------|----------|
| **M0 — PoC** | ui-kit build 改造(文件 4§3/5§3)+ host 雙路徑骨架 + hycert 改造 + 動態載入 | 文件 10 全綠 |
| **M1 — 首發** | hycert 正式切 `'mf'` 上 production,其餘維持 `'wujie'` | hycert 線上穩定運行 ≥ 1 週,無回滾 |
| **M2 — 推廣** | 其餘 remote 依序改造(文件 8 樣板),逐一切 `'mf'` | 各模組比照 M1 判準 |
| **M3 — 收尾** | 確認無模組為 `'wujie'` → 移除 host Wujie 路徑、`wujie-react` 依賴、`url` 欄位語意調整 | grep 無 Wujie 殘留 |

**遷移順序原則:**
1. **先簡單後複雜**:hycert 結構清楚、子頁皆為 list,適合當樣板首發。
2. **先低風險客戶/環境**:先內部/測試租戶驗證,再推 production。
3. **依賴最少者先行**:嵌入 host 其他區塊(expose widgets)的模組後做。

---

## 3. 版本約束(MF 上線後的硬規則)

源自文件 4(singleton strictVersion)。寫成團隊規約:

- **major 對齊**:`react` / `react-dom` / `react-router-dom` / `@hysp/ui-kit` 的 **major 版本,host 與所有 mf remote 必須一致**。任一升 major = 全體協調升,不可單獨升。
- **ui-kit 發版紀律**:每次改 ui-kit 必遞增版本;破壞性改動升 major 並通知所有 remote。
- **token 走 caret**:patch/minor 可漂移(`^19`),由 MF 取最高相容版。
- **CI 守門**:加一個檢查,比對 host 與各 remote 的 `@hysp/ui-kit` / react major 是否一致,不一致則 fail。
- **token storage key 收斂**(文件 7 §4 清理項):host `'hyadmin_token'` 收進 `PLATFORM_STORAGE_KEYS`。

---

## 4. 佈署

- **獨立佈署保留**:remote 各自 build、各自上 CDN/靜態主機,產 `remoteEntry.js`(文件 3 §5)。host 不需隨 remote 重建。
- **發版流程**:remote 上線新版 → 更新 DB `remote_entry` 的 `?v=`(或部署腳本自動 bump)→ host 下次載 module 清單即指向新版。
- **快取**:`remoteEntry.js` `Cache-Control: no-cache`;內部 hash chunk 長快取(文件 3 §5)。
- **CORS**:跨源 remote 的 entry/chunk 需 `Access-Control-Allow-Origin`(production 由 CDN/反代設定)。
- **回滾**:把 DB `remote_entry` 指回舊 `?v=`,或 `integration` 改回 `'wujie'`。

---

## 5. 本機開發

| 情境 | 做法 |
|------|------|
| 只開發 remote | `hycert-ui` standalone(文件 8 Step 3),自帶外殼 + mock RemoteProps,`pnpm dev` 5173 |
| 開發 host + 連線上 remote | host dev,DB `remote_entry` 指向已部署的 remote URL |
| 開發 host + 本機 remote | host dev,DB(或本機 override)`remote_entry` 指 `http://localhost:5173/...remoteEntry.js`;remote `server.cors: true`(現況已開)|
| 同時改 ui-kit | monorepo workspace 連結;注意 singleton 版本——本機用 workspace 協定即可,但要驗 build 產物版本一致 |

> 建議提供一份 **本機 dev override**(env 或 localStorage 旗標)讓開發者把某模組的 `remote_entry` 暫指 localhost,不污染共用 DB。

---

## 6. 風險登記與緩解

| 風險 | 緩解 |
|------|------|
| ui-kit build 改造牽動所有 app | M0 先做、CI 守門、workspace 鎖版本 |
| 樣式衝突(文件 5 最大風險)| M0 PoC 重點驗 §4/§5;Radix Portal 特別測 |
| 某 remote 升 react major 破壞全體 | major 對齊規約 + CI 檢查擋 |
| remote CDN 故障拖累 shell | RemoteErrorBoundary 降級(文件 3 §6)|
| 過渡期兩套機制維護成本 | 控制 M1→M3 時程,避免長期雙軌 |
| 開發者誤用絕對路徑綁死 host 前綴 | 文件 6 §3 規約:remote 一律相對路徑 |

---

## 7. 完成定義(M3 收尾檢查)
- [ ] 所有 enabled 模組 `integration='mf'`。
- [ ] host 移除 `wujie-react`、`AppContainer`、`__WUJIE` 相關。
- [ ] 各 remote 移除 Wujie 生命週期碼。
- [ ] `Module.url` 欄位語意更新或淘汰(mf 模式不用)。
- [ ] CI major 對齊守門已上線。
- [ ] 文件 1–10 與實作一致,過時處更新。
