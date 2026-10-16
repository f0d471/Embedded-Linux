# 仓库协作规则

- 使用中文。
- 开工先读根 README（定位、四部分、进度）与 Engineering/README.md（流转规则、
  文档对照表）。
- knowledge 的体例唯一出处是 knowledge/README.md：教程完全自足，命令与代码
  完整给出并逐行讲，判据必须能注错见红；不采用"先自己想、不给命令"的引导式写法。
- project 的验证唯一规则是 project/doc/验证流程.md。提交前跑
  `bash project/check.sh`，判据变了的 commit 必须同时更新文档里的 PASS 数。
- 每一次 commit 在同一 commit 里改完受影响的文档，对照表在 Engineering/README.md。
- sources/ 内容不入 git；质检终端项目代码与文档受软著保护，不复制进仓、不上传。
- 文档里引用文件路径与行号，先重新核对再写，不靠记忆。
- 上板一律走串口（tools/serial-board.ps1），不用 ADB；串口传文件必须分块校验重传。
