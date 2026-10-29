# Geciken tur sonucunu koruma

2026-10-29, yerel inceleme. Gercek Codex turu baslatilmadi; kurulu
`~/.beyin` kopyasi ve W5'in adli kanit kaydi degistirilmedi.

## W5 olay zinciri

Kaynak: `motor/scripts/.state/codex-kanal/CK-396c46cdefe940d5bfbd7109093b9cf3/`
altindaki `events.jsonl`, ayni adli kanal JSON'u ve oturum
`01a18496-534e-7651-98cd-4cd2f33d2714` rollout'u. Saatler UTC:

| Olay | Zaman |
| --- | --- |
| Tek `ready` | 2026-10-28 22:16:48.025 |
| Tek `thread/started` | 22:16:48.648 |
| `turn/started`, `01a18496-780d-7a80-8fa9-80806db6e4ce` | 22:16:56.686 |
| Araclarda sandbox setup hatalari | 22:17'den itibaren |
| `disconnected` | 22:36:13.484 |
| Ayni turun `turn/completed` olayi | 22:36:59.609 |
| Host `closed` | 22:46:45.684 |

Bu aralikta ikinci `ready`, thread baslangici veya tur baslangici yok.
Yeniden baglanma/ikinci host gorulmuyor. Dosyanin diskte degistirilmesi,
calisan Node modulunu kendiliginden yeniden yuklemez.

Eski `AppServerRpc.receive`, 1 MiB uzerindeki satirda `ended()` cagiriyordu.
`stdin`/process hatasi da cikis kodu olmadan ayni sinyali uretebiliyordu.
`ended()` sonrasinda stdout dinleyicisi yasamaya devam ediyordu. Host ise
aktif tur nesnesini silip sozu reddediyor, kalici `ActiveTurn` alanini
temizlemiyordu. Bu nedenle daha sonra gunluge yazilan tamamlanma,
`this.active` korumasinda eleniyor; cevap kaydedilmiyordu.

`WorkerExit.kind=fault` tek basina OS process cikisini kanitlamiyor:
eski kod bos exit bilgisini de fault sayiyor. Ham RPC satiri ve gercek
process cikis ayrintisi saklanmadigindan W5'te 1 MiB yolu mu, stdin hatasi
mi tetiklendi kesinlestirilemiyor. Rollout'un 22:36-22:37 arasindaki en buyuk
agent-facing response_item satiri 4.689 bayt; bu, host'un aldigi ham RPC
satirinin boyutu degildir. Kesin kanitlanan hata, yerel kapanis sinyalinden
sonra ayni tur akisinin 46.125 saniye daha surmesi ve tamamlanmanin atlanmasi.

## Davranis

- Buyuk protokol olayi process cikisi sayilmaz. 16 MiB uzerindeki satir,
  icerigi gunluge dokulmeden uyariyla atlanir; akis dinlenmeye devam edilir.
- Baslamis Codex turunun belirsiz hata sonucu `PendingTurn` ile tutulur.
  Terminal kayitlarda `ActiveTurn` bosalir. Kimligi bilinen belirsiz tur,
  otomatik replay edilmez; canli baglantida yeni tur gonderimi engellenir.
- Ayni tur ve denemenin geciken cevabi/tamamlanmasi kalici kayda islenir.
  Yanlis `failed` bildirimi gitmisse tek `completed` bildirimiyle duzeltilir.
  Buyuk olay kendi basina hata olmadigindan bu yolda `failed` gonderilmez.
- Handoff JSON'u bozuksa ozgun cevap silinmez; dogrulama basarisiz kalir.
- Kapanis kaydi artik kaynak, process kodu, sinyal ve PID ayrintilarini tasir.
- Timeout, stall veya kullanici kapanisi sirasinda child ciktilari bosaltilirken
  gelen tamamlanma, kapanisin son durum atamasiyla ezilmez. Tamamlanmanin
  hemen ardindan gercek process cikisi da sonucu `disconnected` yapmaz;
  `backend-closed` olayi process yasam dongusunu ayrica kaydeder.
- `durum`/kayit listeleme, cevapsiz terminal kayitlarda salt okunur kurtarma
  gorunumu uretir. Rollout oturum/proje/tur kimligi dogrulanir. Kayit dosyasi
  ve gercek aktarim kutusu bu okuma sirasinda degismez. `Recovery` alani eski
  durum, kaynak dosya ve kurtarma sonucunu gosterir.
- Tur kimligi yoksa ayni prompt'un eski cevabi basari kaniti sayilmaz.
  `Recovery.Hint` acik inceleme yolunu verir. Tarama dosya boyutu ve okuma
  suresiyle sinirlidir; belirsizlikte tamamlandi sonucu uretilmez.

W5 bu yolla `completed`, `HandoffValid=true`, bos `ActiveTurn` ve dolu cevap
olarak gorundu. Ozgun JSON'un SHA-256 degeri okuma oncesi/sonrasi ayniydi.

## Regresyon komutlari

```powershell
node --test motor/scripts/codex-kanal/late-completion.test.mjs motor/scripts/codex-kanal/notification.test.mjs
& ./motor/scripts/test-motor.ps1 -Suite Pester -PesterPath ./motor/scripts/codex-kanal/answer-recovery.Tests.ps1
& ./motor/scripts/test-motor.ps1 -Suite All
```

Ilk uc Node senaryosunun eski davranisinda 3/3 kirmizi kaniti alindi:
buyuk olay, RPC hatasindan sonra gecikmis cevap ve aktif turda kapanis.
Kurtarma testleri eski okuma yolunda 4/4 kirmiziydi. Bagimsiz incelemenin
buldugu ayni-prompt/belirsiz-tur riski de once kirmizi, sonra yesil dogrulandi.
Fixture'lar gecici dizin ve sahte app-server kullanir; notification testi
gercek vault aktarim kutusunun degismedigini ayrica dogrular.

## Son dogrulama

2026-10-29 yerel son kosu: `test-motor.ps1 -Suite All`, exit 0.

- Pester 3.4.0 / Windows PowerShell 5.1: 32 dosya, 383/383 gecti;
  hata, atlanan veya bekleyen test yok (468,85 saniye).
- Node: 19 dosya, 81/81 gecti; hata/atlama yok (54,38 saniye).
- Bagimsiz kod incelemesi: son degisikliklerde acik bulgu yok.
  Bagimsiz odakli Node kosusu: 14/14; kurtarma Pester: 5/5.
- `git diff --check`: whitespace hatasi yok. Yeni kodun salt okunur
  secret/injection taramasinda bulgu yok.
- Sonuclar: `%TEMP%/beyin-late-final/pester.json` ve
  `%TEMP%/beyin-late-final/node.tap`.

W5 icin kullaniciya acik yerel CLI de dogrulandi:

```powershell
& ./motor/scripts/codex-kanal.ps1 -Komut durum -Id CK-396c46cdefe940d5bfbd7109093b9cf3 -Vault (Get-Location).Path
```

Sonuc: `Status=completed`, `HandoffValid=true`, `ActiveTurn` bos,
`Recovery.Status=recovered`, `Answer` 3.256 karakter. Gercek kanal JSON'u
hash'i ve gercek aktarim kutusu envanteri degismedi. Bu gorunum kurulu
kopyayi guncellemeden, depodaki komutla kullanilir.

Sandbox'taki aralikli `setup refresh had errors` nedeniyle test komutlari
dar kapsamli onayla sandbox disinda calistirildi; hicbir gercek Codex turu
baslatilmadi. Commit/push, CHANGELOG, surum isareti ve kurulu kopya kapsam
disinda tutuldu.
