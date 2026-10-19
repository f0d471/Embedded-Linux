# 仓库协作规则

- 使用中文。
- 开工先读根 README（组成、路线、进度）与 Engineering/README.md（流转规则、
  文档对照表）。
- Knowledge 的体例唯一出处是 Knowledge/README.md：问题链推进、一次一块积木、
  就地讲透；命令与代码完整给出并逐行讲，判据必须能注错见红。
- 仓库内容自洽：讲事物本身，依据是实测、内核源码、man 手册、芯片手册与标准；
  不写"某某资料里说"一类的出处。
- Project 的验证唯一规则是 Project/doc/验证流程.md。提交前跑
  `bash Project/check.sh`，判据变了的 commit 必须同时更新文档里的 PASS 数。
- 每一次 commit 在同一 commit 里改完受影响的文档，对照表在 Engineering/README.md。
- 文档里引用文件路径与行号，先重新核对再写，不靠记忆。
- 上板一律走串口（Tools/serial-board.ps1），不用 ADB；串口传文件必须分块校验重传。
