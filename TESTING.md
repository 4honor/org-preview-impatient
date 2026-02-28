# 测试方案 - org-preview-impatient

本文档包含验证 `org-preview-impatient` 功能的自动化测试方案与手动测试用例。

## 1. 自动化测试 (ERT)

使用 Emacs 自带的 `ert` 框架进行逻辑验证。

### 运行方式

在根目录下运行以下命令（确保加载当前目录的代码）：

```bash
emacs -Q --batch --eval "(progn (require 'package) (package-initialize) (push \"$PWD/\" load-path) (load-file \"tests/test-org-preview-impatient.el\") (ert-run-tests-batch-and-exit))"
```

或者运行集成测试：

```bash
emacs -Q --batch --eval "(progn (require 'package) (package-initialize) (push \"$PWD/\" load-path) (load-file \"tests/test-org-preview-impatient-integration.el\") (ert-run-tests-batch-and-exit))"
```

### 验证点
- [ ] 默认端口是否为 `8888`。
- [ ] 启用模式时是否正确创建了输出缓冲区。
- [ ] 启用模式时是否正确设置了 `httpd-port`。
- [ ] 修改缓冲区内容是否正确触发了防抖计时器。
- [ ] 本地图片是否成功转换为 Base64 嵌入（验证一致性）。

### 运行自动化测试
```bash
# 运行基础逻辑测试
emacs -Q --batch -L . -L tests --eval "(progn (require 'package) (package-initialize))" -l tests/test-org-preview-impatient.el -f ert-run-tests-batch-and-exit

# 运行图片嵌入测试
emacs -Q --batch -L . -L tests --eval "(progn (require 'package) (package-initialize))" -l tests/test-org-preview-impatient-images.el -f ert-run-tests-batch-and-exit
```

---

## 2. 手动测试用例 (Manual Test Cases)

由于涉及浏览器交互，部分功能需要手动验证。

### Case 1: 基础启动与端口验证
1. **操作**：打开一个 `.org` 文件，运行 `M-x org-preview-impatient-mode`。
2. **预期结果**：
   - 默认浏览器应自动打开，显示 URL 为 `http://localhost:8888/imp/live/*org-preview-<filename>*`。
   - Minibuffer 提示：`Org Preview Impatient started at http://localhost:8888/...`。
   - 运行 `netstat -an | grep 8888` 或 `lsof -i :8888` 确认 8888 端口已被 Emacs 监听。

### Case 2: 实时同步验证
1. **操作**：在 `.org` 文件中输入文字（如 `* Header 1*`），等待约 0.5 秒。
2. **预期结果**：
   - 浏览器页面在无手动刷新的情况下自动更新显示 HTML 渲染内容。
   - Emacs 后台导出过程不引发卡顿。

### Case 3: 复杂媒体验证 (Optional)
1. **操作**：插入一个图片或代码块：
   ```org
   [[./example.png]]
   #+BEGIN_SRC python
   print("hello")
   #+END_SRC
   ```
2. **预期结果**：图片能在浏览器中正确显示（如果开启了 Base64 嵌入），代码块有语法高亮。

### Case 4: 模式禁用验证
1. **操作**：运行 `M-x org-preview-impatient-mode` 禁用模式。
2. **预期结果**：
   - 相关的输出缓冲区（` *org-preview-...*`）被自动杀死。
   - 停止监听 `after-change-functions`。

---

## 3. 常见问题排查
- **端口冲突**：如果 8888 已被占用，可在 Emacs 中通过 `(setq org-preview-impatient-port 9999)` 改用其他端口。
- **浏览器未打开**：检查 `browse-url-browser-function` 的配置，确保 Emacs 有权限调用系统浏览器。
