# 模組與功能選單架構

本文件說明 HySP 平台中，模組（Module）和功能（Feature）從資料庫註冊到 UI 呈現的完整流程。

## 資料結構

### hyadmin_modules（模組表）

| 欄位 | 類型 | 說明 | 範例 |
|------|------|------|------|
| `name` | VARCHAR, UNIQUE | 唯一識別碼 | `cert` |
| `display_name` | VARCHAR | 預設顯示名稱 | `Certificates` |
| `i18n` | JSONB | 多語翻譯（預留） | `{}` |
| `icon` | VARCHAR | 圖標名稱 | `shield` |
| `route` | VARCHAR | URL 路徑段 | `cert` |
| `url` | VARCHAR | 子應用 iframe URL | `https://domain/hycert-ui` |
| `api_url` | VARCHAR | 後端 API base URL | `/hycert-api` |
| `sort_order` | INT | 排序（Header Tab 順序） | `10` |
| `enabled` | BOOL | 是否啟用 | `true` |

### hyadmin_features（功能表）

| 欄位 | 類型 | 說明 | 範例 |
|------|------|------|------|
| `module_id` | BIGINT, FK | 所屬模組 | `6` |
| `name` | VARCHAR | 功能識別碼 | `cert-list` |
| `display_name` | VARCHAR | 預設顯示名稱 | `Certificate List` |
| `i18n` | JSONB | 多語翻譯（預留） | `{}` |
| `icon` | VARCHAR | 圖標名稱 | — |
| `path` | VARCHAR | 子路徑（接在模組 route 後） | `/list` |
| `sort_order` | INT | 排序（Sidebar 順序） | `2` |
| `enabled` | BOOL | 是否啟用 | `true` |

## 註冊方式

### Seed 初始化

位置：`hyadmin-api/cmd/seed/main.go`

```
模組: cert (route="cert", url="/hycert-ui", api_url="/hycert-api", sort_order=10)
  ├─ 功能: cert-toolbox (path="/toolbox", sort_order=1)
  └─ 功能: cert-list    (path="/list",    sort_order=2)
```

執行方式：
```bash
./hyadmin seed           # 容器內
go run ./cmd/seed        # 本機開發
```

### 管理 API（動態管理）

| Method | Path | 說明 |
|--------|------|------|
| GET | `/api/v1/admin/modules` | 列出所有模組 |
| POST | `/api/v1/admin/modules` | 新增模組 |
| PUT | `/api/v1/admin/modules/:id` | 更新模組 |
| DELETE | `/api/v1/admin/modules/:id` | 刪除模組 |
| GET | `/api/v1/admin/modules/:id/features` | 列出模組下功能 |
| POST | `/api/v1/admin/modules/:id/features` | 新增功能 |
| PUT | `/api/v1/admin/features/:id` | 更新功能 |
| DELETE | `/api/v1/admin/features/:id` | 刪除功能 |

### 使用者 API（權限過濾）

| Method | Path | 說明 |
|--------|------|------|
| GET | `/api/v1/modules` | 使用者可見模組（依權限過濾） |
| GET | `/api/v1/features?module_id=X` | 模組下功能清單 |

## UI 呈現流程

```
┌────────────────────────────────────────────────────────────────┐
│ Header                                                         │
│  [租戶管理] [使用者管理] [憑證管理] [系統管理]  ← Module Tabs  │
├──────────┬─────────────────────────────────────────────────────┤
│ Sidebar  │ Content Area                                        │
│          │                                                     │
│ 憑證管理 │  ┌─────────────────────────────────┐               │
│ ───────  │  │ WujieReact iframe               │               │
│ 工具箱   │  │                                 │               │
│ 憑證列表 │  │ hycert-ui (子應用)              │               │
│          │  │                                 │               │
│          │  └─────────────────────────────────┘               │
└──────────┴─────────────────────────────────────────────────────┘
```

### 詳細步驟

1. **Header 載入模組**
   - 呼叫 `GET /api/v1/modules`
   - 依 `sort_order` 排列，渲染為 Tab 按鈕
   - 顯示名稱：`i18n moduleNames[mod.name]` → fallback `mod.display_name`

2. **點擊模組 Tab**
   - `selectModule(mod)` → 呼叫 `GET /api/v1/features?module_id=X`
   - `navigate("/app/{mod.route}")` → 例如 `/app/cert`

3. **Sidebar 渲染功能選單**
   - 將 features 轉為選單項目
   - `href = /app/${module.route}${feature.path}`
   - 例如：`/app/cert/toolbox`、`/app/cert/list`
   - 顯示名稱：`i18n featureNames[f.name]` → fallback `f.display_name`

4. **點擊功能項目**
   - React Router 導航至 `/app/cert/list`
   - `AppPage` 提取 `route="cert"`, `subPath="/list"`
   - 拼接子應用 URL：`mod.url + subPath` → `https://domain/hycert-ui/list`

5. **WujieReact 載入子應用**
   - `<WujieReact name={mod.name} url={subAppUrl} />`
   - `key` 包含 subPath，確保路由變更時重新載入
   - 子應用讀取 `window.location.pathname` 決定頁面

## i18n 翻譯覆蓋

模組和功能的顯示名稱支援 i18n 覆蓋：

```typescript
// hyadmin-ui i18n
moduleNames: {
  cert: '憑證管理',
  tenants: '租戶管理',
}
featureNames: {
  'cert-toolbox': '憑證工具箱',
  'cert-list': '憑證列表',
}
```

優先級：i18n 翻譯 > DB display_name

## 新增模組 Checklist

1. **DB 註冊**：在 `seed/main.go` 加入模組 + 功能
2. **子應用路由**：子應用內根據 pathname 路由到正確頁面
3. **i18n**：在 hyadmin-ui 的 i18n 加入 `moduleNames` 和 `featureNames`
4. **部署**：跑 seed 寫入 DB，部署子應用

## 關鍵檔案索引

| 層級 | 檔案 | 說明 |
|------|------|------|
| DB Schema | `hyadmin-api/migrations/admin/20260302000001_init_admin_schema.sql` | modules + features 表 |
| Seed | `hyadmin-api/cmd/seed/main.go` | 初始資料 |
| API | `hyadmin-api/internal/pbmodule/handler.go` | 模組 CRUD |
| API | `hyadmin-api/internal/feature/handler.go` | 功能 CRUD |
| API | `hyadmin-api/internal/pbmodule/service.go` | ListForUser 權限過濾 |
| UI Context | `hyadmin-ui/src/contexts/module-context.tsx` | 模組狀態管理 |
| UI Header | `hyadmin-ui/src/components/layout/header.tsx` | Module Tab 渲染 |
| UI Sidebar | `hyadmin-ui/src/components/layout/sidebar.tsx` | Feature 選單渲染 |
| UI Router | `hyadmin-ui/src/pages/app-page.tsx` | 路由 → subPath → wujie URL |
| UI Container | `hyadmin-ui/src/components/micro-app/app-container.tsx` | WujieReact 掛載 |
