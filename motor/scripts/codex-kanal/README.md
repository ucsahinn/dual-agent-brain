# Codex canli kanal

## Canli gorunum ve gecmis

`beyin codex liste` ve `beyin claude liste`, acik kayitlari ve son 24 saatte
kapanan kayitlari gosterir. `-SonSaat <saat>` bu pencereyi degistirir;
`-Hepsi` arsivlenmis kayitlar dahil tum gecmisi gosterir. Kimligi bilinen
kayit her zaman `durum <CK-id>` ile okunabilir. Merkez Ajanlar sekmesi de
24 saatlik gorunum kuralini kullanir ve ayni kanal kimligini bir kez gosterir.

`beyin codex temizle [-SonSaat 24]` arsiv adaylarini kuru modda listeler.
`-Uygula` yalniz eski terminal kayitlara `ArchivedAt` ekler; kayit veya
isci dosyasi silmez/tasima yapmaz. Ayni komut Claude kanali icin de vardir.
Calisan isci, canli host/root sureci veya canli sahip oturumu korunur.

`aktar.ps1 -Bayat 3` uc gunden eski acik aktarimlari ve hedef klasoru
artik olmayan kayitlari nedenleriyle listeler. Yeni mutlak `-Hedef` yollarinin
tam adresi korunur; eski smoke kayitlarinin Temp yaprak adlari da taninir.
Siradan proje etiketlerinden yol tahmin edilmez. Yalniz `-Uygula` kapatir;
gecmis `aktar -Hepsi` ile gorunur kalir. Dagitici bu secenekleri aktarmalidir.

`ac` sema uyarilari stdout'a ayri satir basmaz; JSON `Warnings` alanindadir.
Her `sor` talebinin claim anahtari kendi metninden veya acik yazma kapsamindan
turetilir. Otomatik genel brifing kapsam sayilmaz. Windows yol buyuk/kucuk
harfi ve ayiraclari normalize edilir. Claim kimligi konusma devam kimliginden
ayridir; kapsamsiz takip mesaji ayni isci oturumuna devam edebilir.

## V2 kaynak durumu (2026-10-27)

### Sef dumanindan sonra sandbox geri dususu

App-server `model_not_found` hatasinda her tur icin tek model fallback'i
vardir: gecersiz mevcut modelden farkli rol katalog modeli, yoksa config'in
kok `review_model` degeri. Secenek yoksa acik hata verilir. Secilen model
ayni owned thread'in `turn/start.model` alanina verilir ve sonraki turlarda
korunur; `ModelFallback {from,to,reason}` kayda girer. Kullanici config'i
yalniz okunur. Normal ajan metni veya komutun kendi model_not_found metni
bu mekanizmayi tetiklemez; API hata olaylari ve turn.error kullanilir.

Basarisiz `command_execution.aggregated_output` icindeki setup-refresh
imzasi, ajan gecerli handoff verse bile teslim kontrolunden ONCE ele alinir.
App-server camelCase ve snake_case item alanlarini tanir. Setup-refresh
icin toplam ust sinir uc denemedir: elevated, elevated, unelevated. Acik
unelevated profilinde uc deneme de ayni kiptedir. Model fallback'i ayrica
en fazla bir kezdir; iki hata turu birlesirse toplam en fazla dort deneme.

Windows isci varsayilani `elevated` kalir. Yalniz basarisiz turda, arac/hata
olayi veya bu owned backend'in stderr'inde `setup refresh had errors`
gorulurse tekrarlar arasinda 10-40 sn rastgele gecikme uygulanir. Yalniz son
denemede `windows.sandbox="unelevated"` geri dususu uygulanir. Backend ayni
sahipli thread'i resume ederek yeniden acilir.
`sandbox_mode` (workspace-write veya daha dar rol) ve onaylar korunur.
Basarili yan etkiden sonra replay yoktur. Tamamlanan, ajan cevabi ve gecerli
handoff'u olan tur, stderr uyarisi yuzunden failed olmaz.

Profil secimi: `ac -Proje <dizin> -WindowsSandbox unelevated` veya
`gonder -Proje <dizin> -WindowsSandbox unelevated`; v1 icin ayrica
`-Motor exec`. Bu ayar sadece o iscinin kaydina/argumanina gider; global
config'e yazilmaz. Geri dususten sonra o isci unelevated devam eder;
yeni isci yine elevated varsayilaniyla acilir.

Durumda `WindowsSandbox`, `SandboxFallback`, `Error`, `StderrTail` okunur.
Error/warning bildirimleri redakte edilerek events.jsonl ve Error'a yazilir.
Basarisiz tur stderr kuyrugu en fazla 8K karakter, Error en fazla 16K'dir.
Fallback ilk hatanin redakte metnini de korur. Paylasilan WS backend'i
yeniden acilirsa eski TUI baglantisi kopar; `tui <ayni CK-id>` ile tekrar
baglanilir. Yerel kanit gunlugu vault icindeki 50-research/codex-kanal-KANIT-2026-10-27.md dosyasindadir; yayina dahil degildir.

Exec sureci ve app-server baslangici/turlari, vault'tan bagimsiz
`Local\Beyin-codex-setup` adlandirilmis Windows mutex'ini paylasir. Ilk komut
olayi veya agent mesaji, tur sonu/hata ya da en cok 60 sn sonra kilit
birakilir; giris bekleme tavani da 60 sn'dir. Ayni Windows oturumundaki
kendi iscilerimizi siralar; harici Codex/TUI sureclerini siralayamaz.

Butce formulu `(input-cached)+output+cached*0.1`; cached degeri input ile
sinirlanir. `Budget` ham tokens, effectiveTokens, limit, formula, cacheWeight
ve fiyat varsa API-esdegeri cost alanlarini tasir. Fren etkin jetonu kullanir.
Varsayilan 2.000.000; `-JetonButce` veya `BEYIN_CODEX_JETON_BUTCE` Beyin
ayari ile degisir. Acik iscilerin eski launch.json butcesi sabit kalir;
yeni varsayilan icin yeni isci acilir.

Exec stdin UTF-8/BOM'suz yazilir ve okunur. Gecerli canli turn.completed +
agent handoff sonucu Delivery.Source=validated-live-turn olarak esas alinir.
Rollout hash eslesmesi ek kanittir (RolloutStatus); gecikmis ya da eski
BOM ile bozulmus rollout eslesmezligi basarili isi yeniden oynatmaz.

Varsayilan motor kalici stdio app-server'dir. `-Motor exec` v1 yedegidir.
`ac -Proje <dizin>`, `sor <CK-id> -Metin <metin>`, `devam`, `steer`,
`interrupt`, `onay <CK-id> -Istek <id> -Karar accept|decline|cancel`,
`durum`, `limitler`, `tetikle`, `kapat` ve salt okunur `yetim` vardir.
`claude ac/sor/kapat` ayni sahiplik/defter/politikayi stream-json ile kullanir.

Her isci job object'e baglidir. Sahip session, PID ve dogum zamani kontrol
edilir; ham PID ile kapatma yedegi yoktur. Aktif ayni is icin admission kilidi
ve ayrik claim kaydi vardir. Komutlar 1 MB, protokol bekleyen istekler 128 ile
sinirlidir. RPC 15 sn; istemci beklemesi 900 sn sonunda durur ve isciyi
yanlislikla tamamlandi saymaz. Kalici tur sert tavani 45 dk; supervizor
20 dk sessizlikte bir kez durter, 40 dk'da sahipli isi stalled kapatir.
Bos isci 30 dk'da kapanir; planli limit kuyrugu bu idle kapanistan muaftir.

`tui <proje>` yalniz kanal sunucusunun thread'ini acan remote TUI'dir.
`tui <CK-id>` ayni sunucuya baglanir. Varsayilan stdio modunda ag dinleyicisi
yoktur. Paylasimda 127.0.0.1, capability hash, Origin reddi ve token oncesi
ayni TCP soketinin surec sahipligi kontrolu kullanilir. Ham token arguman,
JSON veya olay kaydina yazilmaz. TUI token'i yalniz cocugun ortamindadir.
Gercek paylasim/CLI uyumu sef duman kapisidir; burada yalniz fake kanit vardir.

Codex secimi tek yerde `ikili.ps1` ile yapilir: `BEYIN_CODEX_YOLU` Beyin
ayari varsa o yol onceliklidir; yoksa PATH, npm ve .local adaylari sinirli
`--version` problariyla okunur ve en yeni semantik surum secilir. Esit surumde
tam yolun alfabetik sirasi belirleyicidir. Acik ayar dogrulanamazsa baska
ikiliye sessizce gecilmez. Npm CMD girisi kendi bitisik Node CLI dosyasina
cozulur. Exec, app-server, sema ve TUI ayni sabitlenmis baslaticiyi kullanir.
Kayitta `CodexPath`, `CodexVersion`, `CodexCandidates`; farkli surumler varsa
`CodexWarning` ve `events.jsonl` uyari olayi bulunur. Acik isciler kendi
baslaticilarini korur; yeni secim icin yeni isci acilir. Eski kurulum silinmez.

`sema` calistirilacak ikilinin kendi surumunu ve manifest/dosya hashlerini
dogrular; paket.json surumunden tahmin yapmaz. `sema -Uret` yalniz operatorun
generate-json-schema adimidir. Gercek CLI problarini sef sandbox disinda kosar.
Kurulum otomatiklestirilmedi. Surum pini veya uretim eksikse acik uyari vardir.

Rol MCP diyeti sadece bu isci icin `-c ...enabled=` bayraklari uretir.
node_repl daima kapali, plugin cua_repl dokunulmaz. Bilinmeyen MCP tablo
bicimi sessiz atlanmaz. Zorunlu rol politikasi kisaltilmaz: varsayilan 12K
gorev/istege bagli referans butcesine zorunlu katalog metni ayrica eklenir.
Bu, spec'teki toplam 12K'dan belgeli sapmadir; kurulu code-mapper 22.084
karakterdir. Acik BriefBudget verilirse toplam sert tavan olur.
Claude rol iscileri strict bos MCP config ile baslar; stdio initialize ve
onay kontrol protokolu kullanilir, kullanici/project hook'lari --bare ile
atlanmaz. Kurulu CLI'nin bu protokolle canli uyumu sefin duman kapisidir.

Brifteki Write scope altinda yalniz acik literal yollar otomatik dosya-onayi
kapsami olur; nesir veya wildcard yetki vermez. PowerShell kaynaginin
`-YazmaKapsami` parametresi de acik kapsam verir. Salt okunur rol, shell,
silme, hassas dosya veya symlink/junction yollari manuel kalir. Onay kararlari
kayda yazilir. Eszamanli yerel dizin degistirme yarisi dusuk kosullu risktir;
isletim sistemi sandbox'i ve kullanici onay sinirlari ayrica gecerlidir.

Limitte kuyruk dosyada kalir; otomatik tur ancak host ayaktaysa calisir.
`tetikle` hosttaki zamani gelen kaydi isler. Host tumden kapanmissa kayit
kendi kendini baslatmaz; servis veya Gorev Zamanlayici kurulmaz. Bilinen
preflight limitinde henuz modele gonderilmeyen brif redakte saklanir.
Retry yalniz basarisiz turun yapisal arac/hata olayi veya owned stderr'ine
bakar; 10-40 sn jitter ile toplam en fazla uc deneme. Normal cevap metni
tetiklemez ve basarili yan etkiden sonra
replay yapilmaz. Belirsiz teslim sessizce tekrar edilmez.

Sef MCP kaynagi ve yalniz operatorun kayit ornegi:
[beyin-sef-mcp](../../mcp/beyin-sef-mcp/README.md).
Merkez/bekci/aktar ve mevcut retrieval/kullanim entegrasyonlari bu brifin
yazma siniri disinda kalir. Kabul tablosu, sapmalar ve gercek duman komutlari
vault icindeki `50-research/codex-kanal-KANIT-2026-10-27.md` dosyasindadir (yayinlanmaz). Asagidaki eski v1 aciklamasi exec yedegine
aittir; v2 icin yukaridaki davranis gecerlidir.

Kaynak dagitici `kurulum/beyin.ps1`, `codex` komutunu bu kanala yonlendirir.
Kurulu `~/.beyin` kopyasi bu calismada degistirilmedi. Kurulum yapmadan kaynagi denemek:

```powershell
$env:BEYIN_VAULT = '<vault>'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\kurulum\beyin.ps1 codex liste
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\kurulum\beyin.ps1 codex gonder -Proje C:\projem -Rol agentchef:code-mapper -Metin 'Dosya yapisini salt okunur incele'
```

Komutlar (kurulu dagitici guncellendiginde `beyin codex` de ayni arayuzu kullanir):

```text
beyin codex gonder -Proje <dizin> [-Rol <rol>] [-BrifDosya <dosya> | -Metin <metin>] [-Arkaplan]
beyin codex devam <CK-id> -Metin <metin> [-Arkaplan]
beyin codex liste
beyin codex durum <CK-id>
beyin aktar dinle -Kime claude
```

`gonder` JSON sonucu kanal kimligini (`CK-...`), asil Codex `SessionId` degerini
ve nihai `Answer` alanini dondurur. `devam` icin **CK kimligi** kullanilir.
TUI oturum kimlikleri, `--last` ve kanal disi oturumlar kabul edilmez. Proje
ve rol ilk gonderimde sabitlenir. `liste` ozetleri, `durum` nihai yaniti da verir.

`-Metin`, yedi alanli bir brife donusturulur. `-BrifDosya` yedi dolu alani
bu sirayla tasimalidir: Goal, Evidence, Write scope, Boundaries, Done when,
Return format, User's words. Tam brif tekrar yazilmaz. Bos deger icin `none`
kullanilir. Model cevabinda alti dolu handoff alani zorunludur. AgentChef
bulunuyorsa `handoff-check` de kosar; sonuc kayittaki `HandoffCheck` alanindadir.
Eksik/yanlis handoff `invalid-handoff`, CLI/protokol hatasi `failed` olur.

Roller, kurulu AgentChef checkout'unun `templates/codex/agents/*.toml`
dosyalarindan cozulur. `agentchef:code-mapper`, `code-mapper` ve `code_mapper`
ayni role gider. Model katalogdan alinir; reasoning kullanici ayarindan miras
kalir. Roldeki `read-only` sandbox korunur; diger islerde varsayilan
`workspace-write` olur. Onay politikasi `on-request`, reviewer `auto_review`.
Kanal tehlikeli bypass bayraklari kullanmaz; TUI acmaz. Git deposu olmayan,
kullanicinin acikca sectigi bir dizin de kabul edilir.

Kanal her admission'da Beyin'in ayni formuluyle taze kaynak olcumu alir.
Kendi queued/running iscilerini ve takim motorunun queued/spawning/running
iscilerini sayar. Oneri 0 ise isci acmadan gerekcesiyle reddeder; zorla asma
secenegi yoktur. Kanal admission ve ayni oturumdaki devam cagrilari dosya
kilidiyle korunur. Takim motorunun ayri bir surecte ayni anda isci baslatmasi
iki motor arasinda ortak bir kilitle atomiklestirilmez; ortak admission
protokolu bu brifin yazma kapsaminda degildir.

Arka planda ebeveyn hemen queued kaydi dondurur. Gizli PowerShell cocugu isi
tamamlayinca bildirimi kanal durum dizininde hazirlayip tamamlanan JSON'u
`.state/handoff` altina atomik tasir; Claude'a adresli tek bildirim olusur.
`aktar dinle` bunun icin tek AKTAR satiri basar. Bildirim nihai cevabi tasimaz,
`codex durum` komutuna isaret eder. Turetilmis Markdown ve kuratorlu notlar
guncellenmez. `Notification=failed` ise sonuc kayittan okunabilir.

Kayitlar `motor/scripts/.state/codex-kanal/` altindadir. Ham JSONL ve stderr
diske yazilmaz. Istem ve cevaplar kayit oncesi mevcut fail-closed sir
filtresinden gecer; tamamlanan istem kaldirilir. Codex'in kendi rollout
saklamasi CLI'nin kendi sorumlulugundadir. Bu kanal kimlik bilgisi okumaz.
Tur varsayilan olarak 900 saniyeyle sinirlidir. Timeout yalniz kanal tarafindan
acilan tam cocuk PID'sini ve alt sureclerini kapatir. Olen sahip `interrupted`
olarak gosterilir; otomatik yeniden gonderim yapilmaz. `devam` mevcut oturum
baglamini korur; belirsiz sonuc tekrar denenecekse once proje kaniti okunmalidir.

Testler canli modeli cagirmadan gercek `codex.cmd` fixture'i, stdin/JSONL,
resume, gizli arka plan sureci ve gercek `aktar-dinle` ile calisir:

```powershell
$r = Invoke-Pester -Script .\motor\scripts\codex-kanal.Tests.ps1 -PassThru
if ($r.FailedCount) { exit 1 }
```

Yerel canli duman kaniti: vault icindeki `50-research/codex-kanal-KANIT-2026-10-27.md` (yayinlanmaz).
