---
name: unity-csharp-version
description: >-
  Which C# and .NET features Unity actually supports. Unity 6 / 2022 LTS use C# 9.0 on
  .NET Standard 2.1 (Mono/IL2CPP), NOT .NET 10 or C# 14. Use when writing Unity C# code and
  unsure whether a modern C#/.NET feature compiles or serializes, or when the user asks what C#
  version Unity uses.
---

# Unity C# Version and .NET Limits

Unity is **not** on .NET 10. Do not copy .NET 10 / C# 14 patterns into Unity code.

## The facts

| Unity version | C# language | Runtime / API surface |
| --- | --- | --- |
| Unity 2021.2 → Unity 6 | **C# 9.0** | .NET Standard 2.1, Mono (editor/legacy) or IL2CPP (builds) |
| Unity 2020.2 – 2021.1 | C# 8.0 | .NET Standard 2.1 / .NET Framework 4.x |
| Older (2017–2018) | C# 6 – 7.3 | .NET Framework 4.x / legacy .NET 3.5 |

So the ceiling today is **C# 9**, not C# 14. Anything from C# 10 or later does not exist in Unity.

## Do NOT use (C# 10+, unavailable)

- `file`-scoped types (`file class X`)
- `required` members
- `record struct`
- `field` keyword (auto-property backing field access — C# 13/14)
- extension blocks (C# 14)
- collection expressions `[1, 2, 3]` (C# 12)
- primary constructors on classes (C# 12)
- `nameof(List<>)` unbound generics (C# 14)
- null-conditional assignment `x?.Age = v` (C# 14)

If a feature is not in the C# 9 column, do not write it in a Unity script.

## C# 9 features you MAY use, but carefully

- **`record`** — the compiler supports it, but **Unity's serializer does not**. A `record` will not show in the Inspector and its fields are not serialized. Use a plain `class`/`struct` for anything a `MonoBehaviour` or `ScriptableObject` must persist; use `record` only for non-serialized, in-memory data.
- **`init` accessors** — same caveat: not serialized by Unity.
- **Top-level statements** — technically C# 9, but Unity expects a MonoBehaviour class whose file name matches the class name; do not use top-level statements for scripts.
- **`init`/`record`/pattern matching** — fine for pure logic that never touches the Inspector.

## Testing

Unity uses the **Unity Test Framework (NUnit)**, not xUnit. Use `[Test]`, `[TestFixture]`, `NUnit.Framework` — never `[Fact]`/`[Theory]`/xUnit.

## What also does not exist in Unity

- Dapper, Entity Framework, ASP.NET Core, `System.Data` relational APIs — these are server-side .NET, not Unity.
- `System.Text.Json` is not guaranteed in all player builds; prefer `JsonUtility` for serialization of Unity types.

## Rule of thumb

When writing Unity C#: assume **C# 9 + .NET Standard 2.1**. If a construct is newer than C# 9, it does not compile; if it is a server/desktop .NET API (Dapper, EF, ASP.NET Core), it is the wrong ecosystem. The `csharp14-dotnet10-features` skill describes the desktop .NET world and does **not** apply to Unity.
