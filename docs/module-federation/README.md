# HySP 平台機制:Wujie → Module Federation 遷移文件

本目錄是把 HySP 微前端整合機制從 **Wujie(無界)** 改造為 **Module Federation** 的完整參考文件集,依實際 repo 現況(`hyadmin-ui` host、`hycert-ui` remote 樣板、`hyui-kit` 共享 UI kit)撰寫。

> 狀態:全部 **Proposed**(待 review)。核可後文件 2 的 ADR 建議同步進 Notion HySP ADR DB。
> 文件目前置於 `hycert-ui/docs/`,屬平台層文件,後續可搬至 `hysp/` 或 `hyadmin-ui/`。

## 閱讀順序

| # | 文件 | 主題 | 解決的 Open Question |
|---|------|------|---------------------|
| 1 | [01-as-is-wujie-architecture](./01-as-is-wujie-architecture.md) | 現況盤點(基準線)+ 5 個技術債缺口 D1–D5 | — |
| 2 | [02-to-be-architecture-and-adr](./02-to-be-architecture-and-adr.md) | 目標架構 + ADR(選型、取捨、里程碑、Q1–Q5)| — |
| 3 | [03-host-remote-integration-contract](./03-host-remote-integration-contract.md) | Module schema 擴充、runtime 動態載入、降級 | Q5 |
| 4 | [04-shared-dependencies-singleton](./04-shared-dependencies-singleton.md) | shared 單例、ui-kit build 改造、版本協商 | Q3 |
| 5 | [05-css-tailwind-isolation](./05-css-tailwind-isolation.md) | 失去 ShadowDOM 後的樣式隔離(**最大風險**)| Q2 |
| 6 | [06-routing-integration](./06-routing-integration.md) | 共用 react-router vs 自帶 router | Q1 |
| 7 | [07-auth-tenant-propagation](./07-auth-tenant-propagation.md) | RemoteProps 注入、401/租戶統一(修 D1/D2)| Q4 |
| 8 | [08-remote-refactor-guide-hycert](./08-remote-refactor-guide-hycert.md) | hycert remote 逐步改造範本 | — |
| 9 | [09-migration-and-compat-strategy](./09-migration-and-compat-strategy.md) | 雙模式並存、遷移順序、回滾、佈署 | — |
| 10 | [10-poc-acceptance-checklist](./10-poc-acceptance-checklist.md) | M0 PoC 驗收清單(全綠才進 M1)| M0 |

## 三條主線

- **正確性前提**:文件 4(單例)+ 文件 5(樣式)——離開 Wujie 沙箱後,原本免費的隔離要靠這兩份補回來,且都卡在 **`@hysp/ui-kit` 升級成有版本號 + 預編譯 CSS 的共享套件**(M0 第一個工作項)。
- **整合契約**:文件 3(載入)+ 文件 6(路由)+ 文件 7(認證)——host↔remote 的所有對接點。
- **落地**:文件 8(改造範本)+ 文件 9(遷移策略)+ 文件 10(驗收)。

## 關鍵決議速查

- 外掛:`@module-federation/vite`,runtime 動態註冊 remote(編譯期 `remotes` 留空)。
- remote 清單來自 **DB**(沿用現況),新增 `remote_entry`/`scope`/`exposed_module` + `integration` 雙模式旗標。
- shared singleton + **strictVersion**:`react`/`react-dom`/`react-router-dom`/`@hysp/ui-kit`。
- 樣式:ui-kit 預編譯 CSS,**host 載一次**;各 remote 關 preflight、移除 ui-kit content 來源。
- 路由:**共用 host 的 react-router**(方案 A),remote 用相對路徑 `<Routes>`。
- 認證:host 集中供應,remote 經 `RemoteProps` 純消費;401/租戶統一在 host。
