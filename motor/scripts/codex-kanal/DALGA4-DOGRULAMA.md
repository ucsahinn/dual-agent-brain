# Dalga 4 kanal doğrulaması

Bu belge kanalın yazma kapsamındadır. Brifin istediği
`50-research/codex-kanal-KANIT-2026-10-27.md` kapsam dışında olduğu için
o dosyaya yazılmadı. Şef aşağıdaki bölümü kendi kanıt günlüğüne aktarabilir.

## Davranış sözleşmesi

- Başarılı tur: `turn/completed` sonucu completed, dolu agent yanıtı ve geçerli
  altı alanlı handoff. Ara araç hataları redakte edilmiş `Warnings` içinde kalır.
  Başarılı turun `Error` alanı boştur. Yeniden denemenin ara failed sonuçları
  aktar bildirimi göndermez; son sonuç bir kez bildirilir.
- Codex açılışı sayfalı `model/list` sorgular. Desteklenen rol, katalog,
  review_model sırası izlenir; bunların hiçbiri yoksa sunucunun varsayılanı
  kullanılır. Liste yoksa yapılandırılmış katalog/review_model kullanılır ve
  `ModelListStatus` bunu açıklar. Çalışma sırasında model_not_found yine sınırlı
  fallback kullanabilir. `ModelList`, `ModelSelection` kayda yazılır.
- `account/read` yalnız hesap türünü ayırmak içindir; hesap yanıtının tamamı
  kaydedilmez. ChatGPT aboneliğinde maliyet null, API eşdeğeri false;
  `account/rateLimits/read` primary ve secondary pencerelerinin en yüksek
  yüzdesi kullanılır. API modunda mevcut efektif token formülü korunur.
  Ölçülemeyen kip `unknown`, fiyat null olur; limit okunamadığında bu durum
  `RateLimitStatus` ve bütçe nedeninde görünür.
- Tanınmayan motor/backend null ve unknown durumuyla kaydedilir; çalıştırılmaz.
  Eski kayıtta motor eksikse sahip olunan spawn planı yedektir.
- 129–192 çıkış kodları (128 + sinyal 1–64) ve Node signal çıkışları arıza
  yerine interrupted olarak sınıflanır. stdout boşalmadan kapanış işlenmez.
- IPC denetimi: host, AppServerRpc ve ClaudeRpc `process.send`, `fork` veya
  `stdio: ipc` kullanmaz. İletişim stdin/stdout/stderr üzerinden JSON'dur.
  WebSocket transport `.send` çağrıları Node IPC değildir; mevcut token,
  loopback ve peer sahipliği kontrolleri korunur.
- Her kayıt klasöründe redakte edilmiş `plan.md`, `notes.md`, `checkpoint.json`
  tutulur. Ölü persistent host için `devam`, sahiplik ve canlı kapasite
  kontrolünden sonra aynı launch planını ve thread kimliğini kullanır.
  Açıkça kapatılmış host otomatik açılmaz. Yaşı eski olsa da açık checkpoint
  devamı kendiliğinden yeni threade dönüştürülmez.

## Codex home ve profil seçimi

Doğrudan kanal komutu `-CodexHome <mevcut-dizin>` ve
`-CodexProfil <mevcut-profil-adı>` kabul eder. Çoklu seçim için
`-ProfilDosya <yerel-json>` kullanılır. JSON örneği:

```json
[
  {"name":"birinci","home":"%USERPROFILE%/codex-one","profile":"worker"},
  {"name":"ikinci","home":"%USERPROFILE%/codex-two","profile":"worker"}
]
```

Bu dizinler ve hesaplar operatör tarafından önceden hazırlanmış olmalıdır.
Kanal hesap, kimlik bilgisi veya kullanıcı ayarı oluşturmaz. Her home'un MCP
yapılandırmasına ayrı rol diyeti uygulanır; profil seçimi sandbox ve onay
politikasını kaldırmaz. Seçim stdio app-server kanalına aittir; exec ve paylaşılan
TUI bu seçenekleri açık hata ile reddeder. Profil dosyası en çok sekiz kayıt ve
64 KiB olabilir; yalnız ad, home ve profil alanları kullanılır.

`-LimitteProfilDegistir` varsayılan kapalıdır. Açıldığında tur öncesi ölçülen
limitte sıradaki tanımlı profil denenir; tur promptu henüz gönderilmemiştir.
Aynı home'da thread korunur. Farklı home'da eski oturum dosyaları kopyalanmaz:
yeni thread başlar, önceki handoff bağlama eklenir ve `PreviousSessions` ile
`ProfileSwitch` soy bağı tutulur. Tur içinde gelen limitte mevcut checkpoint ve
limit kuyruğu korunur; yapılmış değişiklikler körlemesine yeniden oynatılmaz.

## Şef koşacak

Bu komutlar bu işçi oturumunda **çalıştırılmadı**. Yerel smoke projesi ve mevcut
hesaplarla şef tarafından ayrı bir normal oturumda uygulanmalıdır.

```powershell
# Gerçek model listesinin ve hesap türünün kayda geldiğini denetle.
$r = & ./motor/scripts/codex-kanal.ps1 gonder -Proje '<smoke-projesi>' -Metin 'Salt okunur incele; altı alanlı handoff ver.' | ConvertFrom-Json
& ./motor/scripts/codex-kanal.ps1 durum $r.Id
# ModelList, ModelSelection, BillingMode, RateLimits, Budget, Warnings, Error.

# Aynı sahip oturumunda, kasıtlı kapatılmamış ama host'u ölmüş bir smoke kaydı:
& ./motor/scripts/codex-kanal.ps1 devam '<CK-id>' -Metin 'Kaydedilmiş checkpointten devam et; kapsamı koru.'
# SessionId aynı kalmalı; plan.md, notes.md, checkpoint.json bulunmalı.

# Mevcut home ve profil; hesap/ayar yaratmaz. Gerçek limit olmadan rollover ispatı sayılmaz.
& ./motor/scripts/codex-kanal.ps1 gonder -Proje '<smoke-projesi>' -ProfilDosya '<mevcut-profiller.json>' -LimitteProfilDegistir -Metin 'Salt okunur smoke; altı alanlı handoff ver.'

# Claude canlı stream uyumluluğu:
& ./motor/scripts/claude-kanal.ps1 gonder -Proje '<smoke-projesi>' -Metin 'Salt okunur smoke; altı alanlı handoff ver.'
```

Aktar/aktar-dinle gerçek bildirim görünümü ve gerçek abonelik limitleri ayrıca
şef tarafından doğrulanmalıdır. Bu çalışmanın testleri yalnız sahte CLI ve
app-server süreçleri kullanır. Commit, kurulum, yayın veya MCP kaydı yapılmaz.

## Yerel kanıt — 2026-10-28

| Denetim | Sonuç |
| --- | --- |
| Node, 15 kanal/Claude/Şef MCP test dosyası | 64 geçti, 0 hata, 0 atlanan |
| Windows PowerShell 5.1 / Pester 3.4, 9 dosya | 58 geçti, 0 hata, 0 atlanan |
| Son host değişikliği ardından köprü + Dalga 4 Pester tekrarı | 8 geçti, 0 hata |
| PowerShell parser, 19 dosya | 0 sözdizimi hatası |
| Gitleaks, kanal + Claude + Şef MCP + iki kanal giriş dosyası | Sızıntı yok |
| Kapsamlı diff whitespace kontrolü | Hata yok |

Pester dağılımı: `codex-kanal.Tests.ps1` 32, `dalga4.Tests.ps1` 5,
`teslim.Tests.ps1` 3, `surec.Tests.ps1` 4, `sema.Tests.ps1` 1,
`recovery.Tests.ps1` 1, `profil.Tests.ps1` 5, `kopru.Tests.ps1` 3,
`ikili.Tests.ps1` 4. Her dosya ayrıca taze PowerShell alt sürecinde çalıştırıldı.

Node komutu:

```powershell
$tests = @(rg --files motor/scripts/codex-kanal motor/scripts/claude-kanal motor/mcp/beyin-sef-mcp -g '*.test.mjs')
node --test --test-concurrency=1 @tests
```

Yeni regresyonlar önce başarısız olarak gözlendi: toparlanan araç hatasının
failed sayılması, ara retry bildirimi, bilinmeyen backend'in varsayılana
dönüşmesi, eski checkpoint'in fresh olması ve eski sinyal kaydının yeni RPC
arızasını maskelemesi. Düzeltmelerden sonra son tam Node koşusu 64/64 geçti.

Bağımsız inceleme bu işçi tarafından yapılmadı: gerçek Codex çağrısı yasak;
yerel requesting-code-review becerisi de iç alt ajanı bağımsız inceleme olarak
kabul etmiyor. Şefin ayrı inceleme geçişi ve canlı smoke bu rapordan ayrıdır.

Kapsam sapması: canlı kapasite okuması `beyin kapasite`, motorun kendi davranışı
gereği `motor/scripts/.state/kapasite.json` çalışma zamanı önbelleğini yeniledi.
Bu dosya elle düzenlenmedi veya geri alınmadı; kaynak değişikliklerinin tamamı
brifteki kanal yazma kapsamındadır. Paralel işçinin kaynaklarına dokunulmadı.
