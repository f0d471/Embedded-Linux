# 仓库协作规则

- 使用中文。
- 开工先读根 README（定位、四部分、进度）与 Engineering/README.md（流转规则、
  文档对照表）。
- Knowledge 的体例唯一出处是 Knowledge/README.md：教程完全自足，命令与代码
  完整给出并逐行讲，判据必须能注错见红；不采用"先自己想、不给命令"的引导式写法。
- Project 的验证唯一规则是 Project/doc/验证流程.md。提交前跑
  `bash Project/check.sh`，判据变了的 commit 必须同时更新文档里的 PASS 数。
- 每一次 commit 在同一 commit 里改完受影响的文档，对照表在 Engineering/README.md。
- Sources/ 内容不入 git；质检终端项目代码与文档受软著保护，不复制进仓、不上传。
- 文档里引用文件路径与行号，先重新核对再写，不靠记忆。
- 上板一律走串口（Tools/serial-board.ps1），不用 ADB；串口传文件必须分块校验重传。
