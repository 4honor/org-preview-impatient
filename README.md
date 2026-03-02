# org-preview-impatient

`org-preview-impatient` 是一个 Emacs 软件包，通过异步导出和轻量级 Web 服务器，为 Org-mode 提供**极致流畅、接近零延迟**的浏览器实时预览体验。

## ✨ 特性

- **实时预览**：输入即所得，采用防抖（Debounce）机制优化性能。
- **非阻塞导出**：利用 `async.el` 在后台进程执行渲染，绝不卡顿 Emacs。
- **一致性保证**：自动将本地图片转换为 **Base64 编码**嵌入 HTML，确保浏览器预览效果与源文件完美一致。
- **自动交互**：开启模式后自动打开默认浏览器并跳转至预览页面。
- **Excalidraw 支持**：深度集成 `org-excalidraw`。
- **自定义主题与 SETUPFILE**：完全支持 Org 的 `#+SETUPFILE:` 指令加载自定义主题及宏。

## 📦 安装

推荐使用 `use-package` 配合 `quelpa` 从 GitHub 直接安装：

```elisp
(use-package org-preview-impatient
  :quelpa (org-preview-impatient :fetcher github :repo "4honor/org-preview-impatient")
  :config
  ;; 默认端口为 8888，如果需要修改：
  ;; (setq org-preview-impatient-port 8888)
  
  ;; 如果你的 #+SETUPFILE 中包含需要在 <head> 中加载的 HTML 样式（如 istyle.theme），请将其设置为 nil
  ;; (setq org-preview-impatient-body-only nil)
  )
```

### 依赖项

本软件包依赖以下插件（通过上述方式安装会自动处理）：
- `async`
- `simple-httpd`
- `impatient-mode`

## 🚀 使用方法

1. 打开一个 `.org` 文件。
2. 运行 `M-x org-preview-impatient-mode`。
3. 你的默认浏览器将自动打开预览页面。
4. 开始编辑，查看实时变化！

## ⚙️ 自定义配置

| 变量名 | 默认值 | 描述 |
| :--- | :--- | :--- |
| `org-preview-impatient-port` | `8888` | Web 服务器监听端口 |
| `org-preview-impatient-debounce-interval` | `0.5` | 触发预览更新的防抖时间（秒） |
| `org-preview-impatient-extra-packages` | `'(org-excalidraw)` | 异步导出进程需要额外加载的包 |
| `org-preview-impatient-body-only` | `t` | 导出时是否只输出 `<body>` 内容。若设为 `nil`，将包含完整的 `<head>` 信息，以便应用 `#+SETUPFILE` 引入的主题样式 |

## 🛠 开发与测试

详见 [TESTING.md](./TESTING.md)。

## 📄 许可证

[GPLv3](./LICENSE)
