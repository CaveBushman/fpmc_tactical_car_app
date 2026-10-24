# CarPlay – plán a požadavky

Android Auto je v aplikaci hotové (Car App Library, kategorie POI + zprávy
přes MessagingStyle notifikace). CarPlay zatím ne: nejde jen o kód.

## Co je potřeba od Applu

CarPlay aplikace musí mít entitlement, o který se žádá na
<https://developer.apple.com/contact/carplay/>. Pro tuto aplikaci připadají
v úvahu:

| Funkce | Entitlement / rámec | Poznámka |
| --- | --- | --- |
| PTT hlas v autě | `com.apple.developer.carplay-communication` + CallKit | Apple ji uděluje VoIP/komunikačním aplikacím; PTT by se v CarPlay chovalo jako hovor (CallKit), ne jako tlačítko. |
| Zprávy týmu nahlas + diktovaná odpověď | SiriKit Messaging (`INSendMessageIntent`, `INSearchForMessagesIntent`) | CarPlay čte zprávy jen aplikacím se SiriKit messaging. |
| Cíle na mapě (tým, waypointy) | `com.apple.developer.carplay-maps` nebo point-of-interest kategorie | Navigační kategorie vyžaduje vlastní mapové dlaždice a turn-by-turn; POI kategorie (`CPPointOfInterestTemplate`) je omezená na konkrétní typy (parkování, nabíjení, …) a taktické body do ní nespadají. |

Realistická první žádost: **communication** (PTT přes CallKit) + **SiriKit
messaging**. Mapové cíle v CarPlay nejspíš schváleny nebudou; na iPhonu je
nahrazuje režim auta v aplikaci.

## Implementační kroky po schválení

1. Xcode: přidat entitlementy do `Runner.entitlements`, capability „CarPlay“
   a „Siri“, `UIBackgroundModes` doplnit o `voip`.
2. `CarPlaySceneDelegate.swift` + `CPTemplateApplicationScene` v
   `Info.plist` (`UIApplicationSceneManifest`), šablona `CPListTemplate`
   se skupinami a stavem kanálu.
3. CallKit: `CXProvider` – vstup do PTT kanálu jako probíhající „hovor“,
   mute/unmute = PTT; napojit na `PttController` přes MethodChannel
   (stejný princip jako `tactical/ptt_native` na Androidu).
4. SiriKit Intents extension pro čtení a odesílání zpráv; data ze sdílené
   App Group (zprávy ukládat i do sdíleného kontejneru).
5. Ověřit v CarPlay simulátoru (Xcode → I/O → External Displays → CarPlay)
   a v autě.

Nic z toho nejde sestavit ani ověřit bez macOS/Xcode a schváleného
entitlementu, proto to v repozitáři zatím není jako kód.
