# 憑證部署 Agent 規格

本文件定義 hycert 部署目標與 Agent 之間的對應關係，供未來開發 Agent 時參考。

## 架構

```
hycert-api                              Target Host
┌────────────────────┐                 ┌──────────────────────┐
│ certificates       │  GET /download  │ agent                │
│ deployments        │ ◄────────────── │  1. 查詢部署目標       │
│                    │                 │  2. 下載對應格式       │
│                    │  PUT /status    │  3. 寫入指定路徑       │
│                    │ ◄────────────── │  4. 執行 reload_cmd   │
└────────────────────┘                 │  5. 回報狀態          │
                                       └──────────────────────┘
```

## 服務類型與下載格式對應

| target_service | 下載格式 | API 呼叫 | 輸出檔案 |
|---|---|---|---|
| nginx | PEM + KEY | `?format=pem` + `?format=key` | cert_path + key_path |
| apache | PEM + KEY | `?format=pem` + `?format=key` | cert_path + key_path |
| haproxy | PEM (含私鑰) | `?format=pem&include_key=true` | cert_path（單一檔案） |
| tomcat | PFX 或 JKS | `?format=pfx&password=xxx` | cert_path |
| iis | PFX | `?format=pfx&password=xxx` | cert_path |
| k8s | PEM + KEY | `?format=pem` + `?format=key` | kubectl create secret tls |
| other | 依 cert_path/key_path 判斷 | 預設 PEM + KEY | cert_path + key_path |

## deployment target_detail JSON 結構

```json
{
  "os": "linux",
  "cert_path": "/etc/nginx/ssl/server.pem",
  "key_path": "/etc/nginx/ssl/server.key",
  "reload_cmd": "nginx -s reload"
}
```

| 欄位 | 必填 | 說明 |
|------|------|------|
| `os` | 否 | `linux` / `windows`，影響路徑格式與指令 |
| `cert_path` | 是 | 憑證檔案的絕對路徑 |
| `key_path` | 否 | 私鑰檔案的路徑（haproxy/tomcat/iis 不需要，合併在 cert 裡） |
| `reload_cmd` | 否 | 部署完成後執行的指令 |

## 各服務的典型設定

### Nginx (Linux)
```json
{
  "os": "linux",
  "cert_path": "/etc/nginx/ssl/server.pem",
  "key_path": "/etc/nginx/ssl/server.key",
  "reload_cmd": "nginx -s reload"
}
```

### Nginx (Windows)
```json
{
  "os": "windows",
  "cert_path": "C:\\nginx\\conf\\ssl\\server.pem",
  "key_path": "C:\\nginx\\conf\\ssl\\server.key",
  "reload_cmd": "nginx -s reload"
}
```

### Apache (Linux)
```json
{
  "os": "linux",
  "cert_path": "/etc/httpd/ssl/server.pem",
  "key_path": "/etc/httpd/ssl/server.key",
  "reload_cmd": "systemctl reload httpd"
}
```

### HAProxy
```json
{
  "os": "linux",
  "cert_path": "/etc/haproxy/certs/server.pem",
  "reload_cmd": "systemctl reload haproxy"
}
```
> HAProxy 的 cert_path 包含 cert + chain + key，不需要 key_path。

### Tomcat (JKS)
```json
{
  "os": "linux",
  "cert_path": "/opt/tomcat/conf/keystore.jks",
  "reload_cmd": "systemctl restart tomcat"
}
```
> Agent 需額外管理 JKS 密碼（從 hyconf 或環境變數取得）。

### IIS (Windows)
```json
{
  "os": "windows",
  "cert_path": "C:\\certs\\server.pfx"
}
```
> Agent 使用 PowerShell 匯入 PFX 到 Windows 憑證存放區並綁定 IIS site。

### Kubernetes
```json
{
  "os": "linux",
  "cert_path": "namespace=prod,secret=tls-cert",
  "reload_cmd": "kubectl rollout restart deployment/web -n prod"
}
```
> Agent 解析 cert_path 為 namespace + secret name，執行 `kubectl create secret tls --dry-run=client -o yaml | kubectl apply -f -`。

## Agent 執行流程

```
1. Agent 啟動（排程或 daemon）
2. GET /api/v1/agent/cert/deployments?host={hostname}
   → 取得本機相關的部署目標列表
3. 對每個部署目標：
   a. 比對本機現有憑證指紋 vs DB 指紋
   b. 如果不同 → 下載新憑證
   c. 根據 target_service 決定下載格式
   d. 寫入 cert_path / key_path
   e. 執行 reload_cmd
   f. PUT /api/v1/agent/cert/deployments/{id}
      → 回報 status=active, deployed_at=now
4. 失敗時回報錯誤，不改 status
```

## Agent 認證

Agent 使用獨立的 API 路徑（`/api/v1/agent/cert/*`），認證方式待定：
- 方案 A：Agent Token（每台主機一組，存在 agent 設定檔）
- 方案 B：mTLS（Agent 用自己的 client cert 認證）
- 方案 C：hysso 簽發的 service token

## 未來擴展

| 功能 | 說明 |
|------|------|
| 到期自動推送 | Agent 排程檢查 → 偵測到新憑證 → 自動部署 |
| ACME 整合 | hycert 自動續約 → 觸發 Agent 部署 |
| 部署歷史 | 記錄每次部署的時間、結果、舊憑證指紋 |
| 回滾 | 部署失敗時還原到上一版憑證 |
| Webhook 通知 | 部署成功/失敗時發送通知 |
