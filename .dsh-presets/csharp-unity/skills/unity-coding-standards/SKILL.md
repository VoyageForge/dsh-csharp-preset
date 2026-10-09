---
name: unity-coding-standards
description: >-
  Unity C# coding standards and best practices reference. Use when writing MonoBehaviour
  scripts, creating C# classes, reviewing Unity code, or when the user asks about naming
  conventions, component patterns, or code quality in a Unity project.
---

# Unity C# Coding Standards

Source: nyosegawa/unity-agent (template/.claude/skills/unity-coding-standards).

## Naming Conventions
- Classes/Structs: PascalCase (`PlayerController`)
- Public methods/properties: PascalCase (`TakeDamage()`)
- Private fields: _camelCase (`_currentHealth`)
- [SerializeField] private fields: _camelCase (`_moveSpeed`)
- Local variables/parameters: camelCase (`hitPoint`)
- Constants: UPPER_CASE (`MAX_HEALTH`)
- Interfaces: I-prefix PascalCase (`IDamageable`)
- Enums: PascalCase, singular (`DamageType`)

## MonoBehaviour Patterns
```csharp
public class ExampleComponent : MonoBehaviour
{
    [Header("Configuration")]
    [SerializeField] private float _moveSpeed = 5f;
    [SerializeField] private LayerMask _groundLayer;

    [Header("References")]
    [SerializeField] private Transform _groundCheck;

    private Rigidbody _rb;

    private void Awake()
    {
        _rb = GetComponent<Rigidbody>();
    }

    private void OnEnable() { /* Subscribe to events */ }
    private void OnDisable() { /* Unsubscribe from events */ }
}
```

## Input

Determine which input solution the project actually uses **before writing input code** — never impose
one on a project that already relies on the other:

| Setting | Meaning |
|---|---|
| `Packages/manifest.json` lists `com.unity.inputsystem` | New Input System package is installed |
| `ProjectSettings/ProjectSettings.asset` → `activeInputHandler` | `0` = legacy Input Manager only, `1` = New Input System only, `2` = both |

- New Input System active → use it, as below.
- Legacy Input Manager active (`activeInputHandler: 0`) → legacy `Input` is available and correct for
  that project. Unity documents it as *not the recommended workflow* and says it will be removed in
  future versions ([Legacy Input](https://docs.unity3d.com/6000.0/Documentation/Manual/InputLegacy.html)),
  but it is not forbidden; an existing project that uses it stays on it.
- Neither set up yet (a fresh project) → **ask the user once** whether to adopt the New Input System;
  installing the package changes `activeInputHandler` and requires an Editor restart. Do not install
  it unprompted.
- Never mix legacy `Input` and New Input System calls for the same action in one project; mixed
  `activeInputHandler: 2` is a migration state, so follow whichever the surrounding code uses.

### New Input System (`using UnityEngine.InputSystem;`)
```csharp
// Mouse
if (Mouse.current != null && Mouse.current.leftButton.wasPressedThisFrame) { }
Vector2 mousePos = Mouse.current.position.ReadValue();

// Keyboard
if (Keyboard.current != null && Keyboard.current.spaceKey.wasPressedThisFrame) { }
```

### Legacy Input Manager (`using UnityEngine;`)
```csharp
// Mouse
if (Input.GetMouseButtonDown(0)) { }
Vector3 mousePos = Input.mousePosition;

// Keyboard
if (Input.GetKeyDown(KeyCode.Space)) { }
```

## Anti-Patterns to Avoid
- `GameObject.Find()` in Update — cache the reference
- `GetComponent<T>()` in Update — cache in Awake
- `Camera.main` in Update — cache the reference
- String comparison for tags — use `CompareTag()`
- `new` allocations in Update — use object pooling
- LINQ in hot paths — generates garbage

## Assembly Definition Guidelines
- Separate runtime and editor code
- Define explicit references between assemblies
- Use `Tests/Editor/*.asmdef` and `Tests/Runtime/*.asmdef`

## Examples

### Good: Cached component access
```csharp
private Rigidbody2D _rb;
private void Awake() => _rb = GetComponent<Rigidbody2D>();
private void FixedUpdate() => _rb.AddForce(Vector2.up * _jumpForce);
```

### Bad: Uncached access in Update
```csharp
private void Update()
{
    GetComponent<Rigidbody2D>().AddForce(Vector2.up); // GC alloc every frame
}
```
