---
name: unity-uitoolkit
description: >-
  Unity UI Toolkit 编程规范与自定义控件封装。覆盖 UXML/USS 布局与样式规范、命名约定、USS 子集限制、以及自定义 VisualElement 组件封装。适用于编写、修改或生成 Unity UI Toolkit 代码（UXML、USS、自定义控件、UIDocument、PanelSettings、运行时数据绑定）。重要：先确认项目的 Unity 版本——2022.3 用旧式 UxmlFactory/UxmlTraits 封装，Unity 6 (2023.2+) 用 [UxmlElement]/[UxmlAttribute]，两者 API 完全不同、不可混用；开始前必须读 ProjectSettings/ProjectVersion.txt 或问用户确定版本。
---

# Unity UI Toolkit 编程与组件封装

适用于 Unity 2022.3 与 Unity 6 两代 API。**开始任何 UIToolkit 工作前，先确定目标 Unity 版本**，因为它决定自定义控件的写法，两代 API 互不兼容。

## 第一步：确定 Unity 版本（必须）

1. 读项目根目录 `ProjectSettings/ProjectVersion.txt` 的 `m_EditorVersion` 字段；读不到就**问用户**。
2. 据此选择封装写法：

| Unity 版本 | 自定义控件写法 | 见下文 |
| --- | --- | --- |
| 2021 / **2022.3** | 旧式 `UxmlFactory<T>` + `UxmlTraits` | 「组件封装 · 旧式」 |
| 2023.2+ / **Unity 6** | 新式 `[UxmlElement]` + `[UxmlAttribute]` | 「组件封装 · 新式」 |

> **绝不混用**：旧式在 Unity 6 会报 Obsolete 警告，新式在 2022.3 会编译失败（特性不存在）。

## UXML/USS 通用规范（跨版本稳定）

### 命名

| 项 | 约定 | 正确 | 错误 |
| --- | --- | --- | --- |
| `name` 属性 | camelCase | `submitButton` | `submit-button` |
| `class` 属性 / USS | kebab-case | `.submit-button` | `.submitButton` |
| 文件路径 | 按功能分目录 | `Assets/UI/Inventory/` | `Assets/Scripts/UI/` |

### UXML 必须项

每个 `.uxml` 文件必须：
1. 声明命名空间：`<ui:UXML xmlns:ui="UnityEngine.UIElements">`
2. 链接样式表：`<ui:Style src="Screen.uss" />`
3. 恰好一个顶层容器
4. **禁止 `style="..."` 内联属性**——所有样式进 USS

```xml
<ui:UXML xmlns:ui="UnityEngine.UIElements">
  <ui:Style src="Panel.uss" />
  <ui:VisualElement name="root" class="panel">
    <!-- content -->
  </ui:VisualElement>
</ui:UXML>
```

### USS 子集限制（这些属性在 USS 中不存在，禁止使用）

| 禁用 | 改用 |
| --- | --- |
| `border` 简写 | `border-width`、`border-color` 分开写 |
| `gap` | 子元素 `margin` |
| `z-index` | DOM 顺序或父级嵌套 |
| `pointer-events` | `picking-mode` UXML 属性 |
| `filter`、`outline`、`box-shadow` | 嵌套元素或背景图 / `border-*` |
| `:first-child`、`:last-child`、`:nth-child` | 显式 class |
| `[attribute]` 选择器 | 显式 class |
| `linear-gradient()`、`radial-gradient()` | 自定义 `VisualElement` + Painter2D |

**内联样式永远禁止**：`style="..."` 在 UXML 里，或 C# 里 `element.style.*` 都禁用——内联样式优先级高于 USS 选择器，无法被样式表覆盖。

### 布局优先弹性而非硬编码

- 用 `flex-grow`、`flex-shrink`、百分比，而非固定 `width`/`height`
- 只在根容器或确需固定尺寸时用像素值
- 子元素应适应父容器，不要各自定义尺寸

### 样式精简

- 不写默认值（`flex-direction: column` 是默认）
- 不写冗余约束（`width: 100px` 不需要再加 `min-width`/`max-width`）
- 不重复选择器
- 用能生效的最简选择器

### 验证（UXML/USS 无法在编辑器外验证）

1. 写完整文件到目标路径，绝不写半成品——半个 UXML 文件一被 Unity 导入就是解析错误。
2. 让用户切到 Unity 编辑器触发 reimport。
3. 请用户报告 Console：UXML 解析错误会标文件名和行号；USS 问题是"未知属性/选择器"警告。
4. 修复后重复。

因为验证要耗用户一次往返，**第一次就写对**：写完所有文件再让用户检查；写前重读 USS 限制清单；留意那些"能解析但渲染错"的问题（不在 Console 出现，需肉眼检查）。

### C# 侧（仅当请求时）

- 用 USS class（`AddToClassList()`），**禁止** `element.style.*`
- 字体用 TextCore（`FontAsset`、`TextStyleSheet`、`TextSettings`），不是 TextMeshPro 的 `TMP_FontAsset`
- 脚本放在 UXML/USS 同目录

## 组件封装 · 旧式（Unity 2021 / 2022.3）

用 `UxmlFactory<T>` + `UxmlTraits` 暴露自定义控件。这是 2022.3 唯一写法。

### 基础模式

```csharp
// StatusBar.cs
using System.Collections.Generic;
using UnityEngine.UIElements;

class StatusBar : VisualElement
{
    // 暴露到 UXML 的工厂（泛型第二参数指定 traits）
    public new class UxmlFactory : UxmlFactory<StatusBar, UxmlTraits> { }

    // 属性 trait：把 UXML 属性映射到 C# 属性
    public new class UxmlTraits : VisualElement.UxmlTraits
    {
        UxmlStringAttributeDescription m_Status = new UxmlStringAttributeDescription { name = "status" };

        public override IEnumerable<UxmlChildElementDescription> uxmlChildElementsDescription
        {
            get { yield break; }  // 无子元素
        }

        public override void Init(VisualElement ve, IUxmlAttributes bag, CreationContext cc)
        {
            base.Init(ve, bag, cc);  // 先初始化基类属性
            ((StatusBar)ve).status = m_Status.GetValueFromBag(bag, cc);
        }
    }

    string m_Status;
    public string status { get; set; }

    public StatusBar() { m_Status = string.Empty; }  // 必须有默认构造
}
```

UXML 里用（需先定义命名空间前缀，见下）：

```xml
<StatusBar status="Ready" />
```

### 属性类型对照（UxmlXxxAttributeDescription）

| 属性类 | C# 类型 |
| --- | --- |
| `UxmlStringAttributeDescription` | `string` |
| `UxmlFloatAttributeDescription` | `float` |
| `UxmlDoubleAttributeDescription` | `double` |
| `UxmlIntAttributeDescription` | `int` |
| `UxmlLongAttributeDescription` | `long` |
| `UxmlBoolAttributeDescription` | `bool` |
| `UxmlColorAttributeDescription` | USS 格式颜色字符串 |
| `UxmlEnumAttributeDescription<T>` | 枚举 `T` |
| `UxmlTypeAttributeDescription<T>` | 类型的程序集限定名 |

### 接受子元素

默认（`yield break`）不接受子元素。要接受任意子元素：

```csharp
public override IEnumerable<UxmlChildElementDescription> uxmlChildElementsDescription
{
    get { yield return new UxmlChildElementDescription(typeof(VisualElement)); }
}
```

### 命名空间前缀

在程序集里用 `[assembly: UxmlNamespacePrefix(...)]` 声明（放任意 .cs 文件、任何 namespace 之外）：

```csharp
[assembly: UxmlNamespacePrefix("My.First.Namespace", "first")]
```

UXML 根元素声明前缀后即可用 `<first:StatusBar>`。改完选 **Assets > Update UXML Schema** 让编辑器/文本编辑器识别新元素。

### 继承基类 traits

`UxmlTraits` 继承自基类的 `UxmlTraits`（如 `VisualElement.UxmlTraits`、`Label.UxmlTraits`），并在 `Init()` 里 `base.Init()`——这样自动继承基类的全部属性。

## 组件封装 · 新式（Unity 6 / 2023.2+）

用属性式 `[UxmlElement]` + `[UxmlAttribute]`。旧的 `IUxmlFactory`/`UxmlTraits` 已废弃。

### 基础模式

```csharp
[UxmlElement]
public partial class MyElement : VisualElement
{
    [UxmlAttribute]
    public string myValue { get; set; }
}
```

```xml
<ui:UXML xmlns:ui="UnityEngine.UIElements"
         xmlns:custom="Game.UI.Custom">
    <custom:MyElement my-value="Hello" />
</ui:UXML>
```

### 要求

1. `[UxmlElement]` 特性在类上
2. 类必须 `partial`
3. 继承 `VisualElement` 或其子类
4. `[UxmlAttribute]` 在要暴露的属性上

### 属性命名

C# camelCase 自动转 UXML kebab-case：`myStringValue` → `my-string-value`。

### 校验与自定义属性名

```csharp
[UxmlAttribute]
[Range(0, 100)]
[Tooltip("Current health value")]
public float health { get; set; } = 100f;

[UxmlAttribute("hp")]   // UXML 里用 "hp" 而非 "health"
public float health2 { get; set; }
```

### 命名空间（新式，关键易错点）

```xml
❌ xmlns:custom="Game.UI.Custom, Assembly-CSharp"  (带程序集名 → 错)
❌ xmlns:custom="game.ui.custom"                    (大小写错)
✅ xmlns:custom="Game.UI.Custom"                    (只要命名空间，大小写精确匹配)
```

## 最佳实践（两代通用）

1. 提供默认值：`public float radius { get; set; } = 30f;`
2. 属性变化时更新视觉：用 setter 调 `UpdateVisuals()` 或 `MarkDirtyRepaint()`
3. 需校验/变更检测时用 backing field
4. 样式用 USS class，不用内联样式
5. 静态图 → USS `background-image`；动态图（每实例不同）→ 属性 + C#
6. 给公开元素写 XML 文档注释
