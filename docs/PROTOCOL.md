# SmartPlane BLE-Protokoll

Zusammenfassung aus TobyRichs offenem Quellcode (BSD-3, © 2014 TobyRich GmbH) und
Community-Analysen der PowerUp-3.0-Firmware, die auf derselben SmartLink-Basis aufbaut.

## Quellen

- `app-smartplane-android/SmartPlane/src/main/res/raw/services.plist` – Service-/Characteristic-Tabelle
- `lib-smartlink-android/.../driver/BLESmartplaneService.java` – Motor/Ruder-Wertebereiche, Init-Sequenz
- `lib-smartlink-android/.../BluetoothDevice.java` – Schreib-Queue, Ruder-Throttling (85 ms)
- `lib-smartlink-android/.../driver/BLEFirmwareUploadService.java` – TI-OAD-Ablauf
- `app-smartplane-android/.../BluetoothDelegate.java` – Akku-Korrekturformel
- `app-smartplane-android/.../SensorHandler.java` + `util/Const.java` – Neigung → Ruder, Flight Assist
- Qiita: „PowerUp3.0のBLEをHackして自作Appから操作してみた“ – PowerUp-UUIDs `86C3810E-…`

## GATT

```
Service 75B64E51-F171-4ED1-921A-476090D80BA7   "smartplane" (primary)
  ├ 75B64E51-0010-…  engine        UInt8 0…254         write without response
  ├ 75B64E51-0021-…  rudder        Int8 −126…126       write without response
  ├ 75B64E51-0030-…  temperature   read
  └ 75B64E51-0040-…  chargestatus  UInt8 (0 = nicht laden) read, alle 6 s abgefragt

Service 75B64E51-F181-4ED1-921A-476090D80BA7   "sml1test" (Prototyp)
  ├ 75B64E51-F184-…  engine
  └ 75B64E51-F185-…  rudder

Service 180F Battery         → 2A19 Battery Level (%), notify
Service 180A Device Info     → 2A25 Serial Number, 2A23 System ID
Service F000FFC0-0451-4000-B000-000000000000  TI OAD
  ├ F000FFC1-…  Image Identify (write + notify)
  └ F000FFC2-…  Image Block    (write + notify)
```

## Verhalten der Original-App

- Beim Verbinden: Motor `0` und Ruder `0` schreiben, beide als *write without response*.
- Werte werden nur gesendet, wenn sie sich ändern; Ruder-Updates mit ≥ 85 ms Abstand.
- Ruder: `roll / 45° × 127`, positiv = rechts. Mit Flight Assist wird Linksausschlag × 0,75.
- Flight Assist: Gas × (1 + min(0,3; 1 − cos(roll·π/2/45°))) in Kurven.
- Akku-Anzeige: Spannung `3,0 V + 0,75 V × %/100`, korrigiert um `I × 0,52 Ω`
  mit `I = Gas × 0,5 A (+ 13 mA Ruder + 19 mA Chip)`.
- System-ID-Anzeige: Bytes 0–2 und 5–7 von `2A23`, umgekehrt → entspricht der MAC-Adresse.

## TI OAD – Firmware-Version lesen

1. Notifications auf `FFC1` aktivieren
2. `0x00` auf `FFC1` schreiben, nach 1,5 s `0x01`
3. Das Flugzeug antwortet per Notify mit dem Header des laufenden Images:
   `uint16 version` (Bit 0 = Image B, Version = `>> 1`), `uint16 length` (in 4-Byte-Wörtern), `char id[4]`

Die App liest nur diesen Header. Flashen ist bewusst **nicht** implementiert.

## SmartPlane PRO

Für die PRO-Version („Vegas“, `com.tobyrich.app.Vegas`) ist kein Quellcode öffentlich. Die App
probiert daher in dieser Reihenfolge:

1. eigene Zuordnung aus dem Labor (pro Gerät gespeichert)
2. eingebaute Profile (SmartPlane, SML1-Prototyp, PowerUp 3.0)
3. Heuristik: jeder Service `xxxxxxxx-F171-…` mit Characteristics `-0010-` (Motor) und `-0021-`/`-0020-` (Ruder)

Wenn nichts passt: **Labor → Gerät → beschreibbare Characteristic → Live-Regler**, und dann
„Als Motor/Ruder verwenden“. Bitte den exportierten Bericht als Issue posten, damit das PRO-Profil
fest eingebaut werden kann.
