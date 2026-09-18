---
brain_schema: "codex-chef.brain-note.v1"
id: "brn_2d328d57-7aa5-431d-9fb5-5fbb1e95a5c4"
type: "knowledge"
title: "Proje Adlari"
project_id: "brain"
status: "active"
privacy: "local"
confidence: "confirmed"
retention: "permanent"
created: "2026-01-01T00:00:00.000Z"
updated: "2026-01-01T00:00:00.000Z"
source_refs: ["engine:kurulum/kur.ps1", "template:iskelet"]
---

# Proje Adlari

Motor, bir oturumun hangi projeye ait oldugunu **calisma klasorunun adindan**
tahmin eder. Bu cogu zaman dogru calisir ama uc durumda yaniltir:

1. Klasor adi projeyi anlatmiyor (`api`, `v2`, `yeni`, `deneme`)
2. Ayni proje birden fazla klasorde (`ornek-api-source`, `ornek-api-web`, `ornek-api`)
3. Klasor adi bir istegin ozeti (`musteri-a-panelini-incele-ve-ozetle`)

Bu dosya o tahmini duzeltir. **Kuratorludur: motor buraya yazmaz, yalniz okur.**

## Nasil yazilir

Her satir `klasor-adi = Kanonik Proje Adi` bicimindedir. Klasor adi
buyuk/kucuk harf duyarsizdir; kanonik ad aynen yazildigi gibi kullanilir.

```
ornek-api-source = ornek-api
ornek-api-web    = ornek-api
api              = odeme-servisi
v2               = musteri-paneli
```

Ayni kanonik ada birden fazla klasor baglanabilir; o zaman gunluk logda ve
`86-compiled/son-durum.md` icinde tek bir proje satiri gorunur ve gecmis
dogru yerde toplanir.

## Otomatik davranis (takma ad gerekmeyen durumlar)

Motor bunlari zaten kendi halleder, buraya yazmana gerek yok:

| Durum | Sonuc |
| --- | --- |
| `Desktop`, `Documents`, `src`, `repos`, `temp` gibi klasorler | `genel` |
| Surucu koku (`C:\`) | `genel` |
| 28 karakterden uzun klasor adlari | ilk uc parcaya kisaltilir |
| Git worktree (`<proje>/.claude/worktrees/...`) | gercek proje adina cozulur |

`genel` bir proje degil, "bu oturum belirli bir projede degildi" demektir.
O bloklar hafizada durur ama `son-durum.md` icinde sahte bir proje satiri
acmaz.

## Aktif takma adlar

> Buraya kendi eslemelerini yaz. Bos birakabilirsin - o zaman yalnizca
> yukaridaki otomatik davranis calisir.
