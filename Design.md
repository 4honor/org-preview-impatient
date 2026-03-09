# org-preview-impatient 技术方案设计

本方案旨在利用 Emacs 现有的生态系统（`async`, `simple-httpd`, `impatient-mode` 等），构建一个高效、非阻塞的 Org-mode 实时预览工具。

## 1. 核心架构

采用 **生产者-消费者** 模型，通过异步后台进程处理耗时的导出任务，并通过轻量级 Web 服务器推送给浏览器。

```mermaid
graph LR
    A[Emacs Buffer] -->|Trigger Change| B(Async Export Task)
    B -->|Generate HTML| C[HTML Cache/Hidden Buffer]
    C -->|Notify| D[simple-httpd/impatient-mode]
    D -->|Push/Poll| E[Browser]
```

## 2. 关键组件选型

### 2.1 异步处理：`async.el`
*   **用途**：在后台启动一个新的 Emacs 实例执行 `org-html-export-as-html`。
*   **原因**：Org 到 HTML 的导出过程涉及 Babel 代码块执行、PlantUML 渲染等，是典型的 CPU 密集型任务，放在主进程会导致编辑卡顿。
*   **实现细节**：使用 `async-start`，并在回调函数中将结果写入一个中转内存块或缓冲区。

### 2.2 变动监听：`after-change-functions` 或 `timer`
*   **优化策略**：为了避免过于频繁且无用的导出，采用 **Debounce（防抖）** 机制。用户停止输入 N 毫秒（如 500ms）后才触发异步任务。

### 2.3 Web 服务器：`simple-httpd` & `impatient-mode`
*   **用途**：建立数据通道。
*   **整合方式**：
    *   创建一个隐藏的关联缓冲区（如 ` *org-preview-output*`）。
    *   在该缓冲区启用 `impatient-mode`。
    *   异步导出的结果写入该缓冲区。
    *   `impatient-mode` 负责处理浏览器的长轮询（Long Polling）或刷新逻辑。

### 2.4 渲染与媒体：`ox-html` 配置
*   **Base64 嵌入**：配置 `org-html-inline-images` 为 `t`，并利用 `org-html-postamble` 注入自定义脚本。
*   **PlantUML**：确保后台异步进程加载了 `ob-plantuml`。
*   **Excalidraw 转换 (集成 org-excalidraw)**：
    *   **核心依赖**：利用 [org-excalidraw](https://github.com/4honor/org-excalidraw) 提供的链接处理器。
    *   **异步环境同步**：在后台异步执行 `ox-html` 导出时，必须确保 `org-excalidraw` 已被正确加载和配置。
    *   **自动导出**：利用 `org-excalidraw` 拦截 `excalidraw://` 协议，并在 HTML 导出阶段自动生成对应的 SVG 图片嵌入到页面中。

## 3. 同步滚动 (Sync Scroll) 实现方案

这是提升用户体验的关键点。

1.  **注入锚点**：在导出的 HTML 元素中注入 `data-line` 属性。
    *   使用 `org-export-filter-headline-functions` 等过滤器，将 Org 源文件的行号注入到 HTML 标签中。
2.  **坐标发送**：Emacs 端监听 `post-command-hook`，获取当前行号，并通过 `simple-httpd` 的自定义路由（如 `/imp/scroll?line=42`）发送给前端。
3.  **前端响应**：`impatient-mode` 的 JS 客户端监听该消息，利用 `querySelector(`[data-line="42"]`)` 找到对应节点并调用 `scrollIntoView()`。

## 4. 极致流畅优化（避免闪烁）

默认的 `impatient-mode` 会导致页面刷新。为实现“不刷新页面更新内容”：
*   **自定义 JS Filter**：在导出的 HTML 中注入一小段 JS，接管 `impatient-mode` 的更新逻辑。
*   **DOM Diffing**：前端使用 `morphdom` 或简单的 `innerHTML` 替换（仅替换内容区），保留滚动位置和样式表状态。

## 5. 任务分解 (Milestones)

1.  **Phase 1: 最小可行性原型 (MVP)**
    - [x] 搭建 `simple-httpd` 服务器。
    - [x] 实现同步的 Org 导出到隐藏 Buffer 并在浏览器显示。
2.  **Phase 2: 异步化与防抖**
    - [x] 集成 `async.el`。
    - [x] 实现后台导出，不影响打字。
3.  **Phase 3: 媒体与美化**
    - [x] 支持 PlantUML 渲染。
    - [x] 引入 Base64 自动嵌入。
    - [x] 提供一套现代化的默认 CSS（支持 SETUPFILE 自定义主题）。
4.  **Phase 4: 同步滚动**
    - [ ] 实现行号注入过滤器。
    - [ ] 实现双向/单向滚动同步。
