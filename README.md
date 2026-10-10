# C# 开发

面向 C# 与 .NET 的编码 Agent：内置 C# 14 / .NET 10 特性、编码规范、SOLID 审查与测试规范四份 Skill，其余能力与 standard 一致（文件编辑、Shell、检索、计划、目标、子代理、工作流）。

这是 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（DSH）的一个 **agent 预设（persona preset）** bundle，供 `dsh-agent-preset` 装载：配置一个人格身份、一套工具组合，以及一组按需加载的 Skill。

## 内容

| 文件 | 说明 |
|---|---|
| `cordis.patch.yml` | 预设定义：persona 文案 + 工具装配 + 技能目录 |
| `package.json` | bundle 清单（`dsh.bundle.patch` 指向上面的 patch） |
| `skills/` | 该人格自带的 Skill，每个子目录一份 `SKILL.md` |

## 内置的 Skill

- `csharp-file-organization`
- `csharp14-dotnet10-features`
- `dotnet10-conventions`
- `dotnet10-testing`
- `solid-review`

## 安装

从 GitHub 直接安装（{profile} 换成目标 profile 名，通常是 `web`）：

```sh
dsh plugin --profile web add github:VoyageForge/dsh-csharp-preset
```

想锁定版本就钉住 commit（比标签可靠——标签可以移动，commit 不能）：

```sh
dsh plugin --profile web add github:VoyageForge/dsh-csharp-preset#<40 位或 7 位 sha>
```

本包是纯配置 bundle（没有 TypeScript 源码、没有 `prepare` 脚本），因此 **git 安装不需要 `allowBuilds` 构建授权**。安装后用 `dsh --profile web --dump-config` 核对配置层已挂载，再启动。

## 它做什么，不做什么

- **做**：装配一个完整的人格——persona 文案、工具组合、按需加载的 Skill 目录。
- **不做**：不注册自己的模型工具，不携带运行时逻辑。它组合的是 DSH 内置插件（`@deepseek-ai/dsh-persona`、`dsh-tool-*`、`dsh-skill-filesystem` 等），这些插件本身已随 DSH 发行。

因此它的价值在于「一次装好一整套开发约定」，而不是新增能力。

## 目录结构

```
.
├── cordis.patch.yml
├── package.json
└── skills/
```

## 本地开发时挂载（link 方式）

如果你要改这个预设本身，把 clone 下来的目录以 `link:` 方式挂进 profile，改完立即生效（git 安装的副本则要重新 `add` 才会更新）：

```json
{
  "dependencies": {
    "@voyageforge/dsh-csharp-preset": "link:path/to/dsh-csharp-preset"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@voyageforge/dsh-csharp-preset"
      ]
    }
  }
}
```

`link:` 指向仓库根目录；依赖键与 `bundles` 里都写根 `package.json` 中的 `name`（带 `@voyageforge/` 作用域）。开发用 link、分发用 git，**两者不要同时存在**——同一 profile 里装两份同名 bundle 会因预设 id 重复而加载失败。

## 它是怎么生成的

本仓库的 `cordis.patch.yml` 由一份生成脚本从原始预设转换而来：把 `preset.yml` 的 name/description、`agent.cordis.yml` 的 plugins 组装成 bundle 形态，并把 `customSkillDirs` 改成基于包名解析的写法（`createRequire(baseUrl).resolve('<包名>/package.json')`）。

生成脚本 `migrate.ps1` 与四个预设的源文件、发布脚本一起放在**主仓库** `F:\Projects\Web\csharp`，不在本仓库内——本仓库只是它的发布产物。

## License

内部工程，未声明开源许可证。