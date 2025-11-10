# DaVinci Batch Render TODO

- [x] 需求分析与架构设计：梳理UI布局、状态流、模块（Config/Core/State/UI/Timeline/Render/Logger），并记录关键API映射。
  - 模块划分：`App.Config`（常量/UI尺寸/渲染键默认值）、`App.Core`（Resolve/Fusion/UI/Dispatcher获取）、`App.State`（输入状态 + RenderSettings + 队列数据）、`App.Logger`（日志缓冲/窗口）、`App.UI`（布局/事件）、`App.Timeline`（Mark操作）、`App.Render`（渲染设置 & 作业执行）、`App.Helpers`（校验/格式化）。
  - UI布局：顶行按钮区（Add Mark、数值输入、路径控件、获取渲染队列、开始渲染），中部左侧TREE展示序号|开始|结束|名称|状态，右侧滚动面板输入全部RenderSettings键，底部多行日志窗口。
  - 状态流：UI输入 -> `State` 更新 -> 校验 -> 执行 `Timeline`/`Render` 操作 -> 更新Tree/日志 -> 根据State调用 `Project:SetRenderSettings`、`AddRenderJob`、`StartRendering`。
  - 关键API：`Resolve()` -> `ProjectManager:GetCurrentProject()` -> `GetCurrentTimeline()`；`Timeline:AddMarker/GetMarkers/DeleteMarker...`；`Project:SetRenderSettings`, `Project:AddRenderJob`, `Project:GetRenderJobs`, `Project:StartRendering`（或等价重载）；Fusion UI：`ui.Button`, `ui.LineEdit`, `ui.SpinBox`, `ui.Tree`, `ui.VGroup/HGroup`, `dispatcher:AddWindow`, `window:Show/RunLoop`等。
- [x] 初始化与骨架代码：创建主Lua文件（单文件多模块模式），完成配置、核心对象获取、入口函数与基本日志管道。
- [x] 通用状态与工具模块：封装输入验证、时间线/项目获取、渲染设置读写、树数据建模等复用逻辑。
- [x] UI搭建：按草图构建窗口（按钮行 + TREE + 渲染参数面板 + 日志窗口），绑定ID与初始事件。
- [x] 批量添加Mark逻辑：基于间隔与数量输入创建时间线标记，提供校验与日志输出。
- [x] 保存路径选择功能：实现路径字段显示当前目录、按钮触发目录选择并回写状态。
- [x] 渲染参数面板：覆盖 `SetRenderSettings` 支持的全部键，提供输入控件、默认值与状态同步。
- [x] 渲染队列生成：读取时间线Mark，按相邻区间生成列表、填充TREE、命名规则“时间线名+序号”。
- [x] 批量添加与渲染执行：根据TREE条目设置渲染范围、调用AddRenderJob批量入队，最后调用StartRendering（或传入jobIds）执行。
- [x] 日志与用户交互完善：统一日志窗口更新、错误提示、必要的UI禁用/启用与状态持久（如最近路径）。
