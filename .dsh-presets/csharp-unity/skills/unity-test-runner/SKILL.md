---
name: unity-test-runner
description: >-
  Run and analyze Unity tests via Unity MCP. Use when running EditMode or PlayMode tests,
  creating test scripts, analyzing test failures, or when the user asks to test Unity code.
---

# Unity Test Runner (via Unity MCP)

Source: nyosegawa/unity-agent (template/.claude/skills/unity-test-runner).

## Running Tests

### Via MCP (recommended)
Drive the test run with `Unity_RunCommand`:
```csharp
internal class CommandScript : IRunCommand
{
    public void Execute(ExecutionResult result)
    {
        // Trigger test execution
        var testRunner = UnityEditor.TestTools.TestRunner;
        result.Log("Tests triggered");
    }
}
```

### Via Unity CLI (fallback)
```bash
# Windows
"C:\Program Files\Unity\Hub\Editor\*\Editor\Unity.exe" ^
  -batchmode -quit -projectPath . -runTests -testPlatform EditMode -testResults TestResults\results.xml

# macOS
/Applications/Unity/Hub/Editor/*/Unity.app/Contents/MacOS/Unity \
  -batchmode -quit -projectPath . -runTests -testPlatform EditMode \
  -testResults TestResults/results.xml
```

## Test File Structure
```csharp
using NUnit.Framework;
using UnityEngine;
using UnityEngine.TestTools;

[TestFixture]
public class PlayerTests
{
    [Test]
    public void Health_TakeDamage_ReducesHealth()
    {
        // Arrange
        var go = new GameObject();
        var player = go.AddComponent<Player>();
        // Act
        player.TakeDamage(10);
        // Assert
        Assert.AreEqual(90, player.Health);
        Object.DestroyImmediate(go);
    }
}
```

## Examples

### Example 1: Create and run an EditMode test
1. Use `Unity_CreateScript` to create the test script under `Tests/Editor/`.
2. Confirm compilation with the console log tool.
3. Run the test.

### Example 2: Analyze a test failure
1. Report the total / passed / failed / skipped counts.
2. For failing tests: report test name, error message, and stack trace.
3. Propose a cause analysis and fix.

## Troubleshooting
- **Test not found**: check the .asmdef `includePlatforms` and references.
- **PlayMode test disconnects**: Project Settings > Editor > Enter Play Mode Settings > Reload Domain: OFF.
- **Test assembly error**: check that the `Tests/` folder's .asmdef references the runtime .asmdef.
