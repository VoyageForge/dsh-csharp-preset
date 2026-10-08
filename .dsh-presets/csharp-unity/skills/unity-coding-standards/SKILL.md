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

## Input (New Input System)
```csharp
using UnityEngine.InputSystem;

// Mouse
if (Mouse.current != null && Mouse.current.leftButton.wasPressedThisFrame) { }
Vector2 mousePos = Mouse.current.position.ReadValue();

// Keyboard
if (Keyboard.current != null && Keyboard.current.spaceKey.wasPressedThisFrame) { }
```
**旧 API (`Input.GetKey`, `Input.mousePosition`) は使用禁止。** — The legacy API (`Input.GetKey`, `Input.mousePosition`) is forbidden; use the New Input System.

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
