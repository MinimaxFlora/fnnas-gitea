# 上架官方应用中心材料（草稿）

> 用途：如果要在飞牛应用中心里让 Gitea 卡片显示「开发工具」分类并按分类浏览，只能通过官方应用中心上架。
> 本地 `.fpk` 没有分类字段（依据见文末），这份文件是提交给飞牛官方时用的材料清单与文案。

## 一、基本信息

| 项 | 填写内容 |
| --- | --- |
| 应用名称 | Gitea |
| 应用标识（appname） | `gitea` |
| 分类 | **开发工具** |
| 版本 | 28.4.0（与上游 tag `v28.4.0` 一致，后续跟随上游 release） |
| 支持架构 | x86（amd64）、ARM（arm64） |
| 支持系统 | fnOS ≥ 1.1.3100 |
| 官网 | https://gitea.com |
| 上游仓库 | https://github.com/go-gitea/gitea |
| 打包项目 | https://github.com/MinimaxFlora/fnnas-gitea |
| 维护者 | MinimaxFlora |
| 运行形态 | 原生二进制（非 Docker），内置 SQLite，内置 SSH 服务 |
| 端口 | Web 3033 / SSH 2222 |
| 授权目录 | 不需要（`disable_authorization_path=true`） |

## 二、简介（一段话，120 字内）

轻量级、开箱即用的自托管 Git 服务。仓库、Issue、Pull Request、Wiki、包管理与 Gitea Actions 一应俱全，由上游源码直接编译，装完向导设好管理员即可使用，数据保存在 NAS 存储空间里。

## 三、功能亮点（列表）

- 完整的 Git 托管：HTTP / SSH 两种克隆方式，内置 SSH 服务默认 2222 端口（被占用自动顺延）
- **默认粉色调主题**：内置 GitHub Pink（light / dark / soft-dark / auto 四款，默认 dark），可在站内切换
- **内置 Gitea Runner**：安装即可跑 Actions，标签 `ubuntu-latest` / `ubuntu-26.04` / `ubuntu-24.04` / `ubuntu-22.04`，无需 Docker
- **安装向导即可配 SMTP**：邮件验证、找回密码、Issue/PR 通知，装好后也能在应用设置里改
- 协作能力：Issue、Pull Request、代码评审、Wiki、里程碑、标签、看板
- 包管理：支持 npm / Maven / Docker / PyPI 等十余种制品仓库
- 安装即用：安装向导里创建管理员账号，自动生成配置与数据库，不需要再打开网页安装器
- 数据安全：数据在 `/volX/@appdata/gitea`，卸载时可选择保留；升级不覆盖配置与仓库
- 双架构原生包：无 Docker 依赖，x86 与 ARM 各一份 fpk

## 四、使用说明（应用中心详情页文案）

1. 应用中心安装后，向导里填写管理员用户名、密码、邮箱，可选是否允许访客注册
2. 安装完成后访问 `http://<NAS-IP>:3033`，用刚设置的账号登录
3. 通过域名/反向代理访问时，在「应用设置 → 访问地址」里改成对外地址，仓库地址与邮件链接才会正确
4. 若开启防火墙，请放行 3033/tcp 与 2222/tcp
5. 系统需要 git ≥ 2.0；飞牛自带 git 若缺 `git-remote-https`，执行 `sudo apt install -y git libcurl4-gnutls-dev`

## 五、更新说明（changelog）

首次发布：从源码编译上游 Gitea v28.4.0，支持 x86 / ARM 双架构；安装向导创建管理员，内置 SQLite 与 SSH 服务。

## 六、需要准备的测试材料

- [ ] x86 设备安装 + 首次登录 + 新建仓库 + 克隆/推送 通过的截图
- [ ] ARM 设备安装 + 启动通过的截图
- [ ] 升级（旧版本 fpk 覆盖安装）数据保留的截图
- [ ] 卸载「保留数据」与「删除数据」两种路径的截图
- [ ] 应用中心卡片、桌面入口、应用设置页的截图

## 七、提交方式（官方文档口径）

1. 加入任意飞牛粉丝群（从飞牛官网进入，右上角关注飞牛后扫码加入）
2. 群里联系社区主理人，加入「应用中心开发者先锋交流群」
3. 按工作人员指引提交：应用信息、应用包（两个架构的 fpk）与测试材料
4. 开发者后台上线后，以后续平台流程为准（分类在后台选择「开发工具」）

## 八、为什么本地 fpk 没有分类（依据）

- 官方文档 `manifest` 页列出的全部字段为 appname / version / display_name / desc / source / platform / maintainer(_url) / distributor(_url) / os_min|max_version / ctl_stop / install_type / install_dep_apps / desktop_uidir / desktop_applaunchname / service_port / checkport / disable_authorization_path / changelog —— **没有分类字段**
- 官方打包工具 `fnpack 1.2.3 create` 生成的模板里也没有分类字段
- 官方商店应用包 `fnnas/appstore.grafana.loki`（3.7.10-1）解包后的 manifest 同样没有分类字段，包内也没有任何分类/元数据文件
- 第三方打包工具 `snltty/fnpackup` 源码中不存在 category 相关字段
- 第三方实现的 app center（`FNOSP/FPKM`）的分类取自**远程应用源**的 tags，而非本地包

结论：应用卡片上的分类小字来自应用目录（商店侧），本地手动安装的 fpk 无法自带；`manifest` 里的 `category` / `category_id` 只对读取它的第三方应用源有意义。
