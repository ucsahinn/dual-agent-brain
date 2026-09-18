# Beyin - Kullanim Kilavuzu

Bu belge, sistemi hic bilmeyen bir Windows kullanicisi icin yazildi. PowerShell
penceresi acabiliyorsan yeterli.

Kanonik bilgi kaynagi kodun kendisidir. Bu kilavuzdaki her komut
`kurulum\beyin.ps1` icindeki dagiticidan, her parametre ilgili betigin `param`
blogundan alindi. Bir seyi burada goremiyorsan `beyin yardim` cikti listesi her
zaman gunceldir.

---

## Icindekiler

1. [Bu nedir, ne degildir](#1-bu-nedir-ne-degildir)
2. [Gereksinimler](#2-gereksinimler)
3. [Kurulum](#3-kurulum)
4. [Gunluk kullanim](#4-gunluk-kullanim)
5. [Komut referansi](#5-komut-referansi)
6. [Vault klasorleri ne ise yarar](#6-vault-klasorleri-ne-ise-yarar)
7. [Ayarlar](#7-ayarlar)
8. [Gece gorevleri](#8-gece-gorevleri)
9. [Sorun giderme](#9-sorun-giderme)
10. [Gizlilik ve guvenlik](#10-gizlilik-ve-guvenlik)
11. [Kaldirma](#11-kaldirma)
12. [Guncelleme](#12-guncelleme)

---

## 1. Bu nedir, ne degildir

### Ne yapar

Beyin, **Claude Code ve Codex** icin ortak bir hafiza motorudur. Iki ajan da ayni
Markdown kasasina (vault) yazar; motor iki ajanda da ayni kancalarla kuruludur.

Uc sey kendiliginden olur:

- **Oturum acilisinda** - kurallarin, guncel odagin, acik hatlarin ve *o anda
  calistigin projeye ait* son oturum bloklari ajanin baglamina enjekte edilir.
- **Her promptta** - yazdigin metinle gercekten eslesen kavram notlari
  ozetleriyle yuzeye cikar. Alaka esiginin altinda hicbir sey enjekte edilmez;
  gurultu sessizlikten kotudur.
- **Oturum kapanisinda** - transkript ozetlenir ve o gunun gunluk loguna eklenir.
  Blogun basligina hangi ajan ve hangi proje klasoru oldugu islenir.

Bunlarin ustune gece gorevleri gunluk loglardan **kavram notlari** derler, notlari
birbirine baglar ve notlarin arasindaki yakin-ikiz/celiski ciftlerini tarar.

Sonuc: bir oturumu kapatip yenisini actiginda ajan nerede kaldigini bilir.

### Ne DEGILDIR

- **7/24 calisan bir servis degil.** Motor yalnizca (a) bir ajan oturumu acilip
  kapandiginda ve (b) kaydettiysen gece gorevleri saatinde calisir. Arka planda
  surekli duran bir surec yoktur.
- **Bulut yok.** Notlarin senin diskinde durur. Hicbir sunucuya yuklenmez.
- **Notlarinin uzak yedegi yok.** `beyin yedek` **yerel** bir kopya alir. Baska
  bir diske/bulut klasorune tasimak senin isin. Bu bilincli bir karar (bkz.
  [Gizlilik](#10-gizlilik-ve-guvenlik)).
- **Ucretli bir SaaS degil.** Aboneligi olan tek sey zaten kurulu olan ajan
  CLI'in; ozetleme onun uzerinden yapilir.
- **Bir gorev yoneticisi / veritabani / sir kasasi degil.** Vault kalici bilgi
  icindir; token, parola, baglanti dizesi oraya yazilmaz.

---

## 2. Gereksinimler

| Gereken | Zorunlu mu | Olmazsa ne olur |
| --- | --- | --- |
| **Windows + PowerShell 5.1** | Zorunlu | Hicbir sey calismaz. Motor Windows yol ve kanca varsayimlari uzerine kurulu. PowerShell 5.1 Windows ile hazir gelir, ayrica kurmana gerek yok. |
| **Claude Code CLI ve/veya Codex CLI** | En az biri zorunlu | Kancalar ateslenir, isler kuyruga girer ve **hicbir gunluk log yazilmaz** - kuyruk surekli buyur. Doktor'un `ozetleyici (claude/codex)` satiri bunu soyler. Ikisi birden varsa ikincisi ozetleyicinin yedegidir. |
| **Git** | Istege bagli | Depoyu `git clone` ile almak icin gerekir; ZIP indirip acmak da olur. `copcu` komutu git'in yok saydigi klasorleri olctugu icin git olmadan is bulamaz. |
| **Ollama + `bge-m3` modeli** | Istege bagli | Anlamsal (vektor) geri getirme kapali kalir; motor **anahtar kelime yoluna** duser ve calismaya devam eder. `beyin bagla` (capraz baglantilar) diskteki vektorleri kullandigi icin vektor olmadan is yapamaz. Doktor'un `embedding` satiri hangi yolda oldugunu yazar. |
| **Node.js** | Istege bagli | Yalnizca doktor'un `-Derin` modundaki `brain-cli` sema kontrolu icin. `beyin yedek` Node'suz da calisir (motorun kendi yedegi); brain-cli varsa dagitici onu tercih eder. |
| **Obsidian** | Istege bagli | Notlari duz Markdown olarak zaten okuyabilirsin. Obsidian yalnizca grafik gorunumu, `.base` tablolari ve `.canvas` haritalari icin gerekir. |

> `beyin yedek` bagimliliksizdir: motorun kendi PowerShell yedegini alir.
> `brain-cli.mjs` adli harici arac varsa (bilinen klasorlerde aranir ya da
> `beyin ayar BEYIN_BRAIN_CLI <yol>` ile gosterilir) dagitici **onu** tercih
> eder - zengin bir manifest uretiyor. O arac bu depoda **gelmez**; yoklugu
> yedek almana engel degildir.

---

## 3. Kurulum

### 3.1 Depoyu al

```powershell
cd $env:USERPROFILE\Documents
git clone https://github.com/ucsahinn/dual-agent-brain.git Beyin
cd Beyin
```

Klasor adini ne verirsen vault'un adi o olur. Varsayilan cozum yolu
`%USERPROFILE%\Documents\Beyin` oldugu icin orada `Beyin` adiyla durmasi en az
ayar gerektiren secenektir.

### 3.2 Once kuru calistir (istege bagli ama tavsiye edilir)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kur.ps1 -KuruCalisma
```

Hicbir sey yazmaz, yalnizca ne yapacagini satir satir basar.

### 3.3 Kur

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kur.ps1
```

Kurulum **fikirlidir (idempotent)**: istedigin kadar tekrar calistirabilirsin,
var olan kurulumu bozmaz ve senin icerigini asla ezmez.

Kullanabilecegin parametreler (hepsi `kur.ps1`'in `param` blogunda tanimli):

| Parametre | Ne yapar |
| --- | --- |
| `-KuruCalisma` | Yazmadan once ne yapacagini gosterir. |
| `-Vault "D:\Beyin"` | Vault'u baska bir yere kurar. Goreli yol yazsan bile mutlaklastirilarak kaydedilir. |
| `-YalnizVault` | Yalnizca klasor yapisi + baslangic dosyalari + surum damgasi kurulur. Ev dizinine (launcher, dagitici, kanca ayarlari, skill baglantilari) **hic dokunulmaz**. Ikinci bir vault hazirlamak icin. |
| `-Zamanla` | Gece gorevlerini de kaydeder (bkz. [8. bolum](#8-gece-gorevleri)). Opt-in. |
| `-PathAtla` | `beyin` komutunu PATH'e **eklemez**. Varsayilan aciktir; bkz. [3.7](#37-beyin-komutu-ve-path). |
| `-IzinleriSikilastir` | Vault dosya izinlerini sikilastirir: miras kirilir, tam yetki yalniz sahibi + SYSTEM + Administrators. Opt-in; geri almasi zahmetlidir (`icacls "<vault>" /reset`). |
| `-CodexZorla` | Codex kanca girdilerini beklenen komut+timeout ile yeniden yazar. Codex TUI'de `/hooks` ile yeniden onay **sarttir**. |

### 3.4 Kurulum sonrasi

Kurulumun kendisi bu adimlari `SONRAKI ADIMLAR` basligi altinda ekrana basar:

1. **Codex kullaniyorsan:** Codex TUI'de `/hooks` calistir ve `beyin` girdilerini
   onayla (Trusted olmali). Codex her kanca tanimini hash'ler; **onaylanmamis bir
   kanca sessizce atlanir** - hata vermez, sadece hic calismaz.
2. **Codex oturumlarini `/exit` ile kapat.** Pencereyi kapatmak SessionEnd
   kancasini atesmez. (Claude Code da cokme ve Ctrl+C durumunda atesmez.) Kayip
   olmaz: yetim tarayici 72 saat icinde toplar.
3. **YENI bir terminal ac.** Kurulum `beyin` komutunu PATH'e ekler, ama bir PATH
   degisikligi ancak **yeni acilan** pencerelerde gecerli olur.

### 3.5 Dogrula

Yeni actigin terminalde:

```powershell
beyin durum
```

Komut bulunamazsa (bkz. [9.7](#97-beyin-komutu-bulunamiyor)) tam yol her zaman
calisir:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
```

### 3.6 Kurulumdan sonra ne nerede olusur

**Ev dizininde:**

```
%USERPROFILE%\.beyin\
  vault.txt              vault yolunun TEK kaydi
  beyin.ps1              tasinabilir tek giris noktasi (dagitici)
  beyin.cmd              'beyin ...' komut sarmalayicisi (kur.ps1 uretir, elle duzenleme)
  beyin-launcher.ps1     gercek launcher (kancalari kosan dosya)
  ayar.json              ayarlarin kaydi (beyin ayar yazar; ilk kurulumda olusmaz)

%USERPROFILE%\.claude\
  hooks\beyin-launcher.ps1   Codex icin sim; ~\.beyin\ icindeki gercek launcher'a yonlendirir
                             (bu yol DONDURULMUS: Codex kanca tanimlarini hash'ler)
  settings.json              kanca girdileri BIRLESTIRILIR (var olan ayarlarin korunur)
  skills\                    vault'un motor\skills klasorune junction

%USERPROFILE%\.codex\
  hooks.json                 kanca girdileri - yalnizca GEREKTIGINDE dokunulur
  skills\                    vault'un motor\skills klasorune junction

%USERPROFILE%\.agents\
  skills\                    ayni junction (ortak skill deposu)
```

**Kullanici PATH'inde:** `%USERPROFILE%\.beyin` girdisi eklenir - `beyin` komutunu
her yerden calistirabilmen icin. Girdi kayit defterine **`%USERPROFILE%\.beyin`
bicimiyle** ve deger turu korunarak yazilir; boylece profil yolu degisirse girdi
kendiliginden dogru yeri gosterir ve PATH'indeki `%JAVA_HOME%\bin` gibi diger
degisken girdileri donmaz.

**Vault icinde** (yoksa olusturulur, varsa dokunulmaz):

```
<vault>\
  00-inbox\  10-command-center\  20-goals\  30-projects\  40-knowledge\
  50-research\  60-decisions\  70-personal\  80-memory\
  85-daylogs\  86-compiled\  86-compiled\concepts\  86-compiled\sources\
  90-archive\  templates\
  motor\hooks\  motor\scripts\  motor\skills\
  motor\scripts\.state\        (queue, watermarks, sessions, claims, makbuz)
  .beyin-version               motor surum damgasi
  brain.config.json  AGENTS.md  CLAUDE.md
```

`motor\scripts\.state\` motorun calisma durumudur: is kuyrugu, isaretler
(watermark), oturum durumlari, kilitler ve makbuzlar. Elle duzenleme.

### 3.7 `beyin` komutu ve PATH

Kurulum iki sey yapar, boylece bu kilavuzdaki kisa ornekler (`beyin durum`)
gercekten calisir:

1. `%USERPROFILE%\.beyin\beyin.cmd` sarmalayicisini yazar. Bu dosya `cmd`,
   PowerShell ve Git Bash icinden calisir; yaninda duran `beyin.ps1`'i cagirir.
2. `%USERPROFILE%\.beyin` girdisini **kullanici PATH'ine** ekler.

Dolayisiyla:

```powershell
beyin durum
beyin doktor
beyin al "D:\indirilenler\rapor.md" -KuruCalisma
```

**Tek sart: yeni bir terminal.** PATH degisikligi yalnizca yeni acilan
pencerelerde gecerlidir. Kurulumu calistirdigin pencerede komut henuz
bulunmayabilir (kurulum kendi surecinin PATH'ini gunceller, ama acik duran diger
pencereleri degil).

Kurulum PATH'i yazdiktan sonra isletim sistemine bir **ortam degisikligi yayini**
(`WM_SETTINGCHANGE`) gonderir. Bu yayin olmadan Explorer ortam blogunu tazelemez
ve Explorer'dan acilan her yeni terminal yine eski PATH'i miras alir - yani "yeni
terminal ac" tarifi calismazdi. **Yayin basarisiz olursa kurulum bunu soyler** ve
kesin cozumu yazar: oturumu kapatip yeniden ac (ya da tam yolu kullan).

**PATH'e dokunulmasini istemiyorsan:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kur.ps1 -PathAtla
```

Bu durumda `beyin.cmd` yine de yerine kurulur (dogrudan tam yoluyla
cagirabilirsin), ama PATH'e girdi eklenmez ve komutlari tam yolla yazarsin:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
```

Bu kilavuzda `beyin <komut>` yazan her yerde, PATH girdisi yoksa yukaridaki uzun
bicimi kullanabilirsin - ikisi ayni seyi calistirir.

PATH yazilamazsa (kisitli kullanici, politika vb.) **kurulum bozulmaz**: adim
`atlandi` olarak raporlanir ve tam yolla her sey calismaya devam eder.

---

## 4. Gunluk kullanim

**Aslinda hicbir sey yapman gerekmiyor.** Ajanla normal sekilde konusursun; motor
oturum acilisinda baglami enjekte eder, kapanista ozeti yazar. Gece gorevlerini
kaydettiysen derleme, gomme ve baglama da kendiliginden olur.

Buna ragmen isine yarayacak dort komut:

```powershell
# Beynim ne durumda? (8-12 satir, model cagirmaz, aga cikmaz)
beyin durum

# Su an ne oluyor: aktif oturumlar, kuyruk, calisan is, butce, niyet
beyin canli

# Ileriye donuk hedefini kaydet (7 gun boyunca iki ajana da enjekte edilir)
beyin niyet "bu hafta kurulumu bitir"

# Motor son 7 gunde ne yazdi, kac bayt, kac butce harcadi
beyin makbuz 7
```

Ipucu: ajanin kendisine de "beynim ne durumda?" diye sorabilirsin - `beyin-doktor`
skill'i iki ajanda da kurulu oldugu icin dogru komutu kendisi calistirir.

---

## 5. Komut referansi

Asagidaki liste `kurulum\beyin.ps1` icindeki `Yaz-Yardim` fonksiyonunun tamamidir.
"Yazar mi?" sutunu **varsayilan** davranisi gosterir.

### 5.1 Tani

| Komut | Ne yapar / ne zaman | Yazar mi? |
| --- | --- | --- |
| `durum` (`ozet`, `status`) | Kisa saglik ozeti. En sik kullanilan komut. Model cagirmaz. Tum kontroller kosar, cikti tabloya degil ozete dokulur. | Hayir |
| `doktor` (`doctor`, `tam`) | Tam kontrol tablosu. Bir sey ters gittiginde ilk basvuru. Kontrol sayisi surumle degisir; `TANI` satiri o kosudaki gercek sayiyi basar. | Hayir |
| `derin` (`deep`) | Tam kontrol + canli model duman testi (`claude -p`, claude yoksa `codex exec`) + varsa `brain-cli` sema/denetim kontrolu. Bir model arka ucu varsa **gunluk butceden 1 harcar**; hicbiri yoksa duman testi atlanir. | Hayir |
| `makbuz [gun] [betik]` | Motor kosu makbuzlari: ne yazildi, kac bayt, kac butce. Varsayilan 1 gun. `makbuz 7 flush` gibi ikinci parca betik adidir. | Hayir |
| `canli [dk]` | Su an ne oluyor: aktif oturumlar, kuyruk, calisan is, butce, niyet. Varsayilan pencere 30 dakika. | Hayir |

```powershell
beyin durum
beyin doktor
beyin makbuz 7
beyin canli 60
```

Temsili `durum` ciktisi (gercek degerler senin makinende farkli olur):

```
BEYIN DURUMU  (2026-01-15 09:12)  ·  motor v1.0.0
  Saglik      : temiz (NN kontrol)
  Butce       : 3 / 200 flush tavani (derleyici rezervi 210)
  Is kuyrugu  : 0 bekleyen flush isi · derleme: 1 gun bekliyor
  Makine      : 41 gunluk log · 26 kavram notu
  ...
  Embedding   : 26 vektor / diskte 26 kavram (bge-m3, 1024-d, 0 gun once)
  Motor surumu: guncel: 1.0.0 (uzak kontrol 5 saat once)
  Ayarlar     : yok - tum ayarlar varsayilan (normal)
```

### 5.2 Bakim

| Komut | Ne yapar / ne zaman | Yazar mi? |
| --- | --- | --- |
| `niyet [metin]` | Ileriye donuk hedefi kaydeder; 7 gun boyunca oturum acilisinda iki ajana enjekte edilir. Argumansiz cagrilirsa kayitli niyeti gosterir. `-Proje x` ile projeye baglar, `-Temizle` siler. | **Evet** (durum dosyasi) |
| `topla [gun]` | Pencereden dusmus (yetim) oturumlari toplar. **Varsayilan kuru calisma, 3 gun.** | Hayir (kuru) |
| `topla-uygula` | Ayni, ama gercekten isler. Model cagirir. | **Evet** |
| `derle` (`compile`) | Gunluk loglardan kavram notu uretir. Model cagirir. | **Evet** |
| `derle-zorla` | Bekleyen gunleri zorla derler (`-Force`). | **Evet** |
| `al <yol>` (`kaynak`, `ingest`) | Dis kaynagi (makale/rapor/dokuman) okur ve kavram notuna cevirir. Desteklenen: `.md .markdown .txt .log .html .htm .json .csv`. Kaynak sayfasi `86-compiled\sources\` altina duser. `-KuruCalisma`, `-Proje x`, `-Json`, `-MaxKavram 3`. | **Evet** (`-KuruCalisma` yoksa) |
| `denetle` (`lint`) | Kavram notlari arasinda yakin-ikiz / celiski taramasi (semantik lint). Hizli yol diskteki vektorleri kullanir, model cagirmaz ve butce harcamaz. `-MinCos` (varsayilan 0.80), `-EnFazla` (25), `-Json`. `-Derin` tek model cagrisiyla hakemlik yaptirir ve **1 butce harcar**. | Hayir (rapor) |
| `arsivle` (`archive`) | Eski gunluk loglari `90-archive`'a tasir (varsayilan 90 gunden eski). **Varsayilan kuru**; yazmasi icin `-Uygula`. | Hayir (kuru) |
| `bahcivan [gun]` (`gardener`) | Kavram/skill/betik kullanim raporu: canli, uyuyor, olu-aday. Varsayilan pencere 90 gun. **Kuru rapor.** | Hayir (kuru) |
| `bahcivan-uygula` | Olu aday kavramlari `90-archive`'a tasir. Makbuz kapsami dolmadan (90 gun) hicbir seyi olu saymaz. | **Evet** (tasir, silmez) |
| `copcu` (`janitor`) | Disk copcusu: repolardaki git'in yok saydigi cikti klasorlerini olcer. Varsayilan koklar `Desktop` ve `Documents`; `-Kok <dizin>` ile degistirilir, `-MinMB` (50) esigi. **Kuru rapor.** | Hayir (kuru) |
| `copcu-uygula` | **DIKKAT: KALICI SILER.** Kapilardan gecen klasorleri diskten kaldirir. `-CopKutusu` verirsen geri donusum kutusuna atar. | **Evet - KALICI** |
| `gom` (`embed`) | Kavram notlarini `bge-m3` ile gomer (vektor geri getirme). Ollama gerekir. `-Zorla` ile tumunu yeniden gomer. | **Evet** (vektor indeksi) |
| `bagla` (`link`) | Her kavram notuna en yakin kardeslerini gosteren `## Ilgili notlar` bolumunu hesaplar. Once `gom` calismis olmali. **Kuru.** | Hayir (kuru) |
| `bagla-uygula` | Ayni, ama bolumleri gercekten yazar. `-MinCos` (0.55), `-EnFazla` (4), `-Json`. | **Evet** |
| `zamanla` (`schedule`) | Gece gorevlerini Windows Gorev Zamanlayici'ya kaydeder. `-Liste`, `-Kaldir`, `-KuruCalisma`. | **Evet** (zamanlanmis gorev) |
| `zamanli <komut>` | Zamanlayici sarmalayicisi: kimlik on kontrolu + `[zamanlayici]` logu + makbuz. Elle cagirman gerekmez; gorevler bunu kullanir. | Komuta gore |
| `yedek` (`backup`) | Tam vault yedegi alir -> `.brain/backups/beyin-<damga>/`. **Gercekten yazar**; plani gormek icin `-KuruCalisma`, kac yedek tutulacagi icin `-Tut <n>` (5). Kopyaya girmeyenler: `.git`, `.obsidian`, `*/.state`, yedek klasorunun kendisi. Tamamlanma isareti `TAMAM.txt` tasimayan klasor **yarim** sayilir. | **Evet** |

> **`copcu-uygula` hakkinda.** Silmeden once yedi kapinin **hepsi** birden
> saglanmak zorundadir: klasor git'te yok sayilan/izlenmeyen olacak, adi izin
> listesinde olacak (`frames`, `output`, `.cache`, `.next-*` gibi; `.next` ve
> `node_modules` **asla**), 24 saatten eski olacak, yasak koklerin (vault,
> `~\.claude`, `~\.codex`, `~\.beyin`, `~\.agents`) disinda olacak, junction/symlink
> olmayacak, bir git reposunun altinda ve o repoda izlenen dosya icermeyecek,
> boyutu `-MinMB` esigini gececek. Izlenen (commit'lenmis) hicbir dosyaya
> dokunmaz. Yine de once `copcu` ile raporu oku, sonra uygula.

```powershell
beyin niyet "bu hafta kurulum belgesini bitir"
beyin topla 7                 # kuru: ne yapacagini gosterir
beyin topla-uygula 7          # gercekten isler
beyin al "D:\indirilenler\rapor.md" -KuruCalisma
beyin denetle
beyin copcu -MinMB 10         # once rapor
beyin bagla                   # once kuru bak
beyin bagla-uygula            # sonra yaz
```

### 5.3 Ayarlar

| Komut | Ne yapar / ne zaman | Yazar mi? |
| --- | --- | --- |
| `ayar` (`ayarlar`, `config`, `settings`) | Argumansiz: tum ayarlari etkin degeri ve **kaynagiyla** listeler. `ayar <ad>` tek ayarin detayini gosterir. `-Liste`, `-Json`. | Hayir |
| `ayar <ad> <deger>` | Ayari kalici yazar (`%USERPROFILE%\.beyin\ayar.json`). `BEYIN_` oneki ve buyuk/kucuk harf serbest. Yazimdan sonra **geri okuyup dogrular**: dosya kilitliyse basari mesaji basmaz, `AYAR_YAZILAMADI` makbuzu birakir ve sifir-disi cikar. | **Evet** |
| `ayar <ad> -Sil` | Ayari dosyadan kaldirir, varsayilana dondurur. Silme de geri okunarak dogrulanir. | **Evet** |
| `ayar BEYIN_VAULT <yol>` | Vault yolunu degistirir. Once `<yol>\motor\hooks\lib.ps1` **motor imzasini** arar; yoksa reddeder (`-Zorla` ile asilir). Yazarken `vault.txt.onceki` yedegi birakir ve geri donus komutunu ekrana yazar. | **Evet** (`vault.txt`) |

Ayrinti icin bkz. [7. bolum](#7-ayarlar).

### 5.4 Tasima / kurulum

| Komut | Ne yapar | Yazar mi? |
| --- | --- | --- |
| `guncelle` (`update`) | Motoru GitHub deposundan tazeler ve ardindan `kur.ps1` + `doktor` kosar. **Notlara dokunmaz.** `-KuruCalisma`, `-Zorla`, `-GeriAl`, `-Json`, `-Depo`, `-Dal`. | **Evet** (yalniz motor yuzeyi) |
| `kur` (`install`) | Kurulumu yeniden calistirir. `kur.ps1`'in tum parametrelerini kabul eder. | **Evet** |
| `yayinla` (`publish`) | Motoru + kurulumu bir GitHub deposuna gonderir. **Notlari gondermez** (izin listesi + sizinti taramasi). Varsayilan kuru; `-Uygula`, `-Gonder`. | Kuru (varsayilan) |
| `nerede` (`where`, `bilgi`) | Cozulen vault yolunu, cozum kaynagini, betik sayisini, launcher/sim/ayar dosyalarinin varligini ve motor surumunu basar. Kurulum tanisinin ilk adimi. | Hayir |

### 5.5 Duzeltme (nadiren gerekir)

| Komut | Ne yapar | Yazar mi? |
| --- | --- | --- |
| `yol-temizle` (`yol`) | Makine bolgesindeki mutlak kullanici yollarini kisaltir. **Varsayilan kuru**; yazmasi icin `-Uygula`. | Hayir (kuru) |
| `isaret-goc` | Isaret (watermark) semasini v2'ye gocurur. **Varsayilan kuru**; yazmasi icin `-Uygula`. | Hayir (kuru) |
| `sema-goc` | Durum dosyasi semasini gocurur. **Varsayilan kuru**; yazmasi icin `-Uygula`. | Hayir (kuru) |
| `ice-aktar` (`import`) | Disaridan oturum gecmisi ice aktarir (ChatGPT / Claude / Gemini disa aktarimi). Tamamen yerel calisir. **Varsayilan kuru**; yazmasi icin `-Uygula`. `-Dosya`, `-Kaynak`, `-EnFazla` (50). | Hayir (kuru) |

### 5.6 Yardim

| Komut | Ne yapar |
| --- | --- |
| `yardim` (`help`, `-h`, `--help`, `/?`) | Tum komutlarin kanonik listesini basar. Komut verilmezse varsayilan budur. |

---

## 6. Vault klasorleri ne ise yarar

Klasor adlari `brain.config.json` icindeki `directories` haritasinda tanimlidir.

| Klasor | Anlam | Sahip | Motor yazar mi? |
| --- | --- | --- | --- |
| `00-inbox` | Hizli yakalama | kurator | Hayir |
| `10-command-center` | Genel bakis, dashboard, Obsidian tablolari/haritalari | kurator | Hayir |
| `20-goals` | Hedefler | kurator | Hayir |
| `30-projects` | Proje isi | kurator | Hayir |
| `40-knowledge` | Kalici bilgi | kurator | Hayir |
| `50-research` | Arastirma | kurator | Hayir |
| `60-decisions` | Karar kayitlari | kurator | Hayir |
| `70-personal` | Kisisel | kurator | Hayir |
| `80-memory` | Kurallar, guncel odak, acik hatlar | kurator | Hayir |
| `85-daylogs` | Oturum ozetleri (gunluk log) | **makine** | **Evet** |
| `86-compiled` | Derlenmis kavram notlari, indeks, `son-durum.md` | **makine** | **Evet** |
| `86-compiled\sources` | `beyin al` ile alinan dis kaynak sayfalari | **makine** | **Evet** |
| `90-archive` | Arsiv (arsivlenen loglar, notlarin onceki surumleri) | **makine** | **Evet** |

### Iki bolge

- **Makine-sahipli** (`85-daylogs`, `86-compiled`, `90-archive`): motor onizlemesiz
  yazar. Icerigi **ham kanittir, kanonik bilgi degildir**. Elle duzenleme - bir
  sonraki kosu uzerine yazabilir.
- **Kuratorlu** (digerleri): motor buralara **kendiliginden yazmaz**. Vault'un
  yazma politikasi `preview-required`: ajan once onizleme gosterir, sen onaylarsan
  yazilir. Bir not kanonik hale gelmek icin senin onayinla kuratorlu alana tasinir.

### Ozel durumlar

- `86-compiled\son-durum.md` tamamen **turetilmistir** (proje bazinda gruplanmis
  son oturumlar; model cagirmaz). Silebilirsin, kendini yeniden kurar.
- Kavram notlarindaki `## Ilgili notlar` basligi **makine bakimlidir**. O bolume
  elle bir sey yazma: motor kendine ait olmayan bir satir gorurse o notu
  **atlar** (silmez, `engine.log`'a yazar) ve o not bir daha baglanti almaz.
  Baglantilari yanlis buluyorsan esigi degistir: `beyin bagla -MinCos ...`.
- `motor\` ve `templates\` motorun kendisidir; `kur.ps1` gunceller.

---

## 7. Ayarlar

Ayarlar `beyin ayar` komutuyla **tek merkezden** yonetilir. Elle `setx`
calistirmana gerek yok.

```powershell
beyin ayar                        # tum ayarlar: etkin deger + kaynak
beyin ayar BEYIN_OZETLEYICI       # yalniz o ayarin detayi
beyin ayar ozetleyici codex       # yaz (BEYIN_ oneki ve buyuk/kucuk harf serbest)
beyin ayar ozetleyici -Sil        # varsayilana dondur
beyin ayar -Json                  # tamami makine okunur
```

Yazilan degerler `%USERPROFILE%\.beyin\ayar.json` dosyasinda durur.

**Oncelik sirasi:** ortam degiskeni **>** ayar dosyasi **>** varsayilan. Ortam
degiskeni ustte kalir ki tek seferlik override mumkun olsun:

```powershell
$env:BEYIN_OZETLEYICI = 'codex'   # yalniz bu pencere icin
```

`beyin ayar` ciktisindaki **kaynak** sutunu her ayarin degerinin nereden geldigini
soyler - "ayari degistirdim ama bir sey degismedi" durumunun tanisi budur
(genelde ayni adda bir ortam degiskeni ustte kalmistir).

### Ayar envanteri

| Ayar | Ne ise yarar | Varsayilan |
| --- | --- | --- |
| `BEYIN_OZETLEYICI` | Ozetleyici arka uc. `auto` uygun olani secer. Secenekler: `auto`, `claude`, `codex`. | `auto` |
| `BEYIN_CODEX_MODEL` | Codex arka ucunun model adi. Bos birakilirsa Codex'in kendi varsayilani. | (bos) |
| `BEYIN_EMBED_MODEL` | Ollama gomme modeli. | `bge-m3` |
| `BEYIN_OLLAMA_URL` | Ollama adresi. `localhost` **yazma**: IPv6 denemesi yaklasik 2 saniye ekler, IP yaz. | `http://127.0.0.1:11434` |
| `BEYIN_FLUSH_BUTCE` | Gunluk model cagrisi tavani (1-1000). Derleyici rezervi her zaman bunun 10 ustudur. | `200` |
| `BEYIN_BRAIN_CLI` | `brain-cli.mjs` yolu (istege bagli harici arac). Verilirse `beyin yedek` motorun kendi yedegi yerine onu kullanir; doktor'un `-Derin` sema kontrolu de bunu arar. Yol o an cozulemiyorsa motor bunu **belirsiz** sayar ve zamanlanmis yedek gorevine dokunmaz. | (otomatik arama) |
| `BEYIN_DEPO` | Motor guncelleme deposu. Motoru fork ettiysen kendi adresini yaz. Hem `beyin guncelle` hem doktor'un `motor guncelligi` satiri bunu okur. Sondaki `/` ve `.git` kirpilir. GitHub disi bir adres **uyari verir ama kabul edilir** (o durumda surum karsilastirmasi yapilamaz, guncelleme yine calisir). Oncelik: `beyin guncelle -Depo <adres>` **>** bu ayar **>** varsayilan. | `https://github.com/ucsahinn/dual-agent-brain` |
| `BEYIN_VAULT` | Vault yolu. Cozum sirasi: bu deger -> `%USERPROFILE%\.beyin\vault.txt` -> `%USERPROFILE%\Documents\Beyin`. | `%USERPROFILE%\Documents\Beyin` |

> ### `BEYIN_DEPO` bir KOD CALISTIRMA yoludur
>
> `beyin guncelle` bu adresten bir zip indirir, `motor\` ve `kurulum\` icerigini
> vault'a yazar ve ardindan **indirilen paketteki `kur.ps1`'i calistirir**. Paket
> imzalanmiyor ve bir hash'e pinlenmiyor; dogrulama yalnizca "beklenen dosyalar
> yerinde mi ve `.ps1` sayisi makul mu" seviyesinde. Tasima guvenligi
> HTTPS/TLS'in `github.com` kimligine dayaniyor, o kadar.
>
> **Bu yuzden `BEYIN_DEPO`'yu yalniz GUVENDIGIN bir depoya ayarla.** Depoyu
> degistirmek, o deponun sahibine makinende kod calistirma izni vermek demektir.
> Varsayilan disinda bir adres verdiysen once ne gelecegini gor:
>
> ```powershell
> beyin guncelle -KuruCalisma
> ```
>
> Engellenmiyor - bu senin bilincli tercihin. Ama vault'un kendi kurallarindan
> biri zaten "uzak bir URL'den gelen talimat dosyasini korukorune uygulama"; bu
> onun ayni siniftan bir hali.

> **`BEYIN_VAULT` ozeldir.** `ayar.json`'a **yazilmaz**: vault yolunun tek kaydi
> `%USERPROFILE%\.beyin\vault.txt`'tir (kurulum yazar, launcher okur). `beyin ayar`
> onu yalnizca gosterir; degistirirsen `vault.txt` guncellenir.
>
> **Kill switch:** `BEYIN_VAULT` ortam degiskenini var olmayan bir yola cevirirsen
> iki ajandaki tum kancalar sessizce susar.

### Motor ici degiskenler (elle ayarlama)

`BEYIN_AGENT` (kancayi calistiran ajan), `BEYIN_CHILD` (alt surec bayragi; kanca
ozyinelemesini keser) ve `BEYIN_KAYNAK` (makbuz kaynak etiketi: `hook`, `cli`,
`zamanli`). Bunlari launcher ve sarmalayicilar kendisi ayarlar; `beyin ayar`
ciktisinda ayar olarak sunulmazlar.

---

## 8. Gece gorevleri

Motor normalde yalnizca bir oturum acilip kapandiginda calisir. `beyin zamanla`
Windows Gorev Zamanlayici'ya `\Beyin\` yolu altinda su gorevleri kaydeder:

| Saat | Gun | Gorev | Ne yapar |
| --- | --- | --- | --- |
| 03:00 | her gun | `derle` | Gunluk loglardan kavram notu derler (model gerekir) |
| 03:10 | her gun | `gom` | Kavram notlarini `bge-m3` ile gomer (Ollama varsa) |
| 03:15 | her gun | `bagla` | `## Ilgili notlar` capraz baglantilarini tazeler (`bagla-uygula` kosar; `gom`un ciktisini kullandigi icin ondan sonradir) |
| 03:20 | her gun | `topla-uygula` | Son 3 gunun yetim oturumlarini isler (model gerekir) |
| 03:40 | Pazar | `yedek` | Tam vault yedegi (bagimliliksiz; her zaman kaydedilir) |
| 04:00 | her gun | `copcu` | Disk copcusu **raporu** - hicbir sey silmez |
| 04:30 | Pazar | `bahcivan` | Kavram/skill/betik kullanim raporu (kuru; hicbir sey arsivlenmez) |
| 05:00 | Pazar | `denetle` | Kavram notu semantik denetimi (hizli yol; model cagirmaz, butce harcamaz) |

Komutlar:

```powershell
beyin zamanla                 # kaydet / guncelle (idempotent)
beyin zamanla -KuruCalisma    # ne yapacagini goster
beyin zamanla -Liste          # kayitli gorevler + son kosu sonucu
beyin zamanla -Kaldir         # hepsini sil
```

Bilmen gerekenler:

- **PC uykudaysa gorev makineyi UYANDIRMAZ.** Kacirilan kosu, makine acildiktan
  sonra ilk firsatta yapilir (`StartWhenAvailable`).
- Gorevler **kurulu** dagiticiyi cagirir (`%USERPROFILE%\.beyin\beyin.ps1`), depodaki
  kopyayi degil. Motoru guncelledikten sonra once `beyin kur` calistir; `zamanla`
  kayittan once her rotanin kurulu dagiticida gercekten var oldugunu dogrular ve
  tanimadigi komutun gorevini sesli atlar.
- Gorevler `beyin zamanli <komut>` sarmalayicisiyla kosar: `[zamanlayici]`
  logu ve makbuz birakir.
- **Kimlik on kontrolu bir tasarruf onlemidir, bir bariyer degil.** Model
  gerektiren gorevlerden (`derle`, `topla-uygula`, `derin`) once sarmalayici
  CLI oturumunun acik olup olmadigina bakar. Uc sonuc vardir:

  | Kontrol sonucu | Ne olur |
  | --- | --- |
  | Oturum **acik** | Gorev kosar. |
  | Oturum **gercekten yok** (CLI kurulu degil ya da cikis yapilmis) | Gorev atlanir, makbuza `KIMLIK_YOK` yazilir, cikis kodu **3**. Bosuna model cagrilmaz. |
  | Kontrol **sonuclanmadi** (zaman asimi, hata, taninmayan cikti) | Gorev **YINE DE kosar** ve engine.log'a `kimlik kontrolu sonuclanmadi ... is YINE DE deneniyor` dusulur. |

  Son satir onemlidir: sonuclanmamis bir kontrol "kimlik yok" demek degildir.
  Isin kendi hata yolu kimlik ve kota durumunu zaten ele alir (o durumda
  harcanan butce geri verilir), yani denemenin maliyeti yoktur; atlamanin
  maliyeti gecenin tamamidir.
- **Gorev cikis kodlari** (`beyin zamanla -Liste` ve Gorev Zamanlayici'da
  `LastTaskResult` olarak gorunur):

  | Kod | Anlami |
  | --- | --- |
  | `0x0` | Basarili. |
  | `0x1` | Sarmalayici yanlis cagrildi (komut bos ya da `zamanli zamanli`). |
  | `0x2` | `-Vault` bir vault degil - motor orada kurulu degil. |
  | `0x3` | Oturum gercekten yok: `KIMLIK_YOK`. |
  | Diger | Isin kendi cikis kodu; makbuzda `ZAMANLI_HATA` ve son log satiri yazar. |
  | `0x800710E0` | Gorev tetiklendi ama oturum acik degildi. |
  | `0xC000013A` | Gorev 3 saatlik calisma sinirinda durduruldu. |
  | `0x41301` / `0x41303` | "Su an kosuyor" / "henuz hic kosmadi" - hata degildir. |
- `bahcivan-uygula` ve `copcu-uygula` **zamanlanmis gorev degildir**. Tasiyan ve
  silen yollar bilincli olarak elle kosulur.
- Gorevler `~\.codex\hooks.json` dosyasina dokunmaz.

---

## 9. Sorun giderme

Her sorunun ilk adimi ayni:

```powershell
beyin durum
```

Doktor **salt-okunurdur**; hicbir seyi kendiliginden duzeltmez. Asagidaki tirnak
icindeki adlar doktor tablosundaki gercek kontrol satirlaridir.

### 9.1 Doktor kirmizi satir veriyor

**Belirti:** `TANI: N sorun / M kontrol`, altinda sorunlu satirlar listelenir.

**Tani:** `beyin doktor` (tam tablo). Her sorunlu satirin yaninda `Duzeltme`
sutunu zaten ne yapman gerektigini yazar - once orayi oku.

Doktor doksani askin satir basar; asagidaki tablo hepsini degil, **elle
mudahale gerektirenleri** listeler. Tabloda olmayan bir satir kirmizi yandiysa
`Duzeltme` sutunu zaten yeterlidir - her satir kendi tarifini tasir.

En sik gorulen satirlar ve anlamlari:

| Satir | Anlami |
| --- | --- |
| `ozetleyici (claude/codex)` | Ne `claude` ne `codex` bulunabiliyor. Ozetleme yapilamaz. |
| `gunluk butce` | Gunluk ozetleme tavani doldu (bkz. 9.2). |
| `is kuyrugu` / `derleme kuyrugu` | Bekleyen is birikmis. Genelde butce ya da ozetleyici sorununun sonucudur. |
| `global kanca ayari` / `kanca yollari` | Kanca girdileri eksik ya da yanlis yeri gosteriyor (bkz. 9.4). |
| `Codex SessionEnd` | Codex kapanis kancasi yok ya da onaylanmamis. |
| `embedding` | Vektor durumu (bkz. 9.3). |
| `makbuz (24 saat)` / `sifir bayt yazimi` / `makbuzsuz kosu` | Motor kostu ama makbuz birakmadi, ya da bir dosya 0 bayta dustu. |
| `capraz baglanti` | `bagla` kosusu notlarin gerisinde kalmis - genelde gece gorevi sessizce durmustur. |
| `not guncelligi` | Derleyici guncelleme blogu uretti ama hicbiri notlara islenmedi. |
| `kaynak alimi` | `beyin al` ile kac kaynak alinmis, en son ne zaman. Klasorun hic olmamasi gecerlidir. |
| `yedek tazeligi` | Son yedek 7 gunden eski ya da hic yok. |
| `surum tutarliligi` | Vault **icindeki** iki surum damgasi uyusmuyor (bkz. 9.8). |
| `motor guncelligi` | Kurulu motor, **yayinlanan** surumun gerisinde kalmis; ya da uzak depo **HTTP hatasi** veriyor (depo yok, ozel, ya da dal adi yanlis - bkz. 9.8 ve 9.9). Gercekten ag yoksa, depo GitHub disi bir adresse ya da bu vault yayinin kaynagi ise yesil doner ve sebebini yazar. |
| `ayar dosyasi` | `%USERPROFILE%\.beyin\ayar.json` bozuk, ya da bir ortam degiskeni yazdigin ayari eziyor. Tani: `beyin ayar` (kaynak sutunu). |
| `vault dosya izinleri` | Vault'a fazla genis erisim var (`kur.ps1 -IzinleriSikilastir`). |
| `yetim adaylari (7 gun)` | Kapanmamis oturumlar birikmis: `beyin topla 7`, sonra `beyin topla-uygula 7`. |
| `launcher izi` | Kanca, kasaya **hic ulasamadi**: kayitli kasa yolu erisilemiyor (harici/ag disk bagli degil, klasor tasindi) ya da kanca betigi eksik. O oturumlar hafizasiz acildi. |
| `zamanlanmis gorevler` | Gece gorevi eksik, basarisiz sonuc kodu verdi ya da 3 gundur hic kosmadi (bkz. [9.10](#910-gece-gorevleri-kosmadi)). |
| `oturum durumu` | Bayat oturum dosyasi kalmis - motor en az bir temizlik firsatini kacirmis. Genelde kanca sorununun belirtisidir. |
| `yansima kuyrugu` | Oturum sonunda hafiza guncellemesi onerilmis ama hic yazilmamis. Kuratorlu bolge **senin** sorumlulugunda. |
| `karantina` | Bir transkript 5+ kez denenip hala ozetlenememis. Sessiz filtre sessiz kayiptir - `engine.log`'a bak. |
| `cift tetiklenme` | Vault icinde `.claude\settings.json` var: kancalar **2 kez** calisir. O dosyayi sil. |
| `betik kodlamasi` | Bir motor betiginde BOM yok ya da satir sonu CRLF degil. Genelde betigi elle duzenlemenin sonucudur; PS 5.1 BOM'suz dosyayi ANSI okur. |
| `motor log boyutu` | `engine.log` tavani asmis, doktor yalnizca son bolumu okuyabilmis. |
| `kuratorlu katman` | `current-context.md` guncellenmeyeli 40'tan fazla oturum blogu yazilmis - hafizanin ust katmani geride kalmis. |
| `sir taramasi` | Notlarda sir benzeri bir desen bulundu ya da redaksiyon dusen bir yol var. Once bunu cozmeden yayin yapma. |

### 9.2 Gunluk model butcesi doldu

**Belirti:** `durum` ciktisinda `Butce : 200 / 200 flush tavani`; kuyruk buyuyor,
yeni gunluk log yazilmiyor.

**Tani:**

```powershell
beyin canli          # butce ve kuyruk ayni ekranda
beyin makbuz 1       # bugun ne harcandi, hangi betik
```

**Cozum:** Bu bir kayip degil, **gecikmedir**: isler kuyrukta durur ve ertesi gun
islenir. Beklemek istemiyorsan tavani yukselt:

```powershell
beyin ayar flush_butce 400
beyin ayar                 # 'kaynak' sutunu yeni degerin gecerli oldugunu gostermeli
```

### 9.3 Ollama kapali / kurulu degil

**Belirti:** `embedding` satiri `Ollama yok/kapali: anahtar kelime yolu` diyor.

**Bu bir hata degildir.** Motor anahtar kelime yoluna duser ve tam calisir. Ollama
yavassa kanca 800 ms icinde kelime yoluna geri doner.

**Anlamsal geri getirmeyi acmak icin:**

```powershell
# 1) Ollama'yi kur (ollama.com), sonra modeli indir:
ollama pull bge-m3

# 2) Kavram notlarini gom:
beyin gom

# 3) Capraz baglantilari kur (once kuru bak):
beyin bagla
beyin bagla-uygula
```

Doktor'un `embedding` satiri ayrica su durumlari ayirt eder: vektor indeksi yok,
model Ollama'da yok, indeks bayat (eksik %10 ustu ve 2 gunden eski).

### 9.4 Kanca calismiyor (oturum ozeti yazilmiyor)

**Belirti:** Oturum acip kapatiyorsun ama `85-daylogs` altinda yeni blok yok.

**Tani:**

```powershell
beyin nerede         # launcher, sim ve ayar dosyalari yerinde mi
beyin doktor         # 'global kanca ayari', 'kanca yollari', 'Codex SessionEnd'
beyin canli          # oturum gercekten kayda girmis mi
```

**Sik nedenler:**

1. **Codex kancasi onaylanmamis.** Codex her kanca tanimini hash'ler ve
   onaylanmamis kancayi **sessizce atlar**. Codex TUI'de `/hooks` calistir,
   `beyin` girdilerini onayla (Trusted olmali).
2. **Codex oturumu `/exit` ile kapatilmamis.** Pencere kapatilinca SessionEnd
   atesmez. Kayip degil: yetim tarayici 72 saate kadar geri gider. Elle toplamak
   icin `beyin topla 7` (kuru), sonra `beyin topla-uygula 7`.
3. **Kurulum eksik.** `beyin kur` tekrar calistir - idempotenttir.
4. **Ozetleyici yok.** `ozetleyici (claude/codex)` satiri kirmizi ise hicbir ozet
   uretilemez; bir CLI kur.

### 9.5 Vault bulunamadi

**Belirti:**

```
DOKTOR CALISTIRILAMADI: vault bulunamadi.
```

**Tani:**

```powershell
beyin nerede
```

`Cozum kaynagi` satiri yolun nereden geldigini soyler: `BEYIN_VAULT` ortam
degiskeni, `~\.beyin\vault.txt`, ya da varsayilan.

**Cozum:** Vault'u tasidiysan, **yeni konumundan** kurulumu bir kez calistir:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<yeni-yol>\kurulum\kur.ps1"
```

Bu hem `vault.txt`'yi yeniden yazar hem de skill baglantilarini yeniden isaret
eder. Yalnizca `vault.txt`'yi elle duzenlemek kancalari yasatir ama iki ajanda da
`beyin doktor` skill'i kaybolur (baglantilar mutlak hedefli junction'dir).

Eger `BEYIN_VAULT` yanlislikla var olmayan bir yola ayarlanmissa (kill switch)
temizle:

```powershell
[Environment]::SetEnvironmentVariable('BEYIN_VAULT', $null, 'User')
```

### 9.6 ExecutionPolicy hatasi

**Belirti:**

```
... cannot be loaded because running scripts is disabled on this system.
```

**Cozum:** Bu kilavuzdaki her komut zaten `-ExecutionPolicy Bypass` iceriyor;
hatayi aliyorsan bir yerde o bayragi atlamissindir. Dogru bicim:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
```

Bayrak yalnizca o tek cagri icin gecerlidir; makinenin genel politikasini
degistirmez. Kalici olarak degistirmek istersen (gerekli degildir):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Kancalar ve zamanlanmis gorevler kendi komut satirlarinda `-ExecutionPolicy
Bypass` tasir, yani bu hata onlari etkilemez.

### 9.7 `beyin` komutu bulunamiyor

**Belirti:**

```
beyin : The term 'beyin' is not recognized as the name of a cmdlet, function, ...
```

**Cozum sirasi:**

1. **YENI bir terminal ac.** En sik neden budur: PATH degisikligi yalnizca yeni
   acilan pencerelerde gecerlidir, kurulumu calistirdigin pencere eski PATH ile
   kalir.
2. **Kurulum ciktisinda PATH adiminin ne dedigine bak.** Kurulum bu adimi tek
   satirda raporlar: `kuruldu` (girdi eklendi), `zaten` (girdi vardi), `atlandi`
   (`-PathAtla` verildin ya da yazilamadi - sebebi satirin sonunda yazar).
   Kurulumu tekrar calistirip satiri okuyabilirsin (idempotenttir):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File <vault>\kurulum\kur.ps1
   ```

   Ayrica kurulumun dogrulama tablosundaki `beyin komutu` satiri, `beyin.cmd`
   dosyasinin varligina degil **kayit defterindeki PATH girdisine** bakar - yani
   gercekten kalici olarak kurulup kurulmadigini soyler.
3. **PATH girdisini kendin kontrol et:**

   ```powershell
   $env:Path -split ';' | Where-Object { $_ -like '*\.beyin*' }
   ```
4. **Tam yol her zaman calisir** - PATH hic kurulmasa bile:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.beyin\beyin.ps1" durum
   ```

### 9.8 Motor surumu eski

Iki ayri kontrol iki ayri seyi soyler:

- **`surum tutarliligi`** - vault'un **icindeki** surum damgalari uyusmuyor.
- **`motor guncelligi`** - kurulu motor, `BEYIN_DEPO`'da **yayinlanan** surumun
  gerisinde. Ag kontrolu yalnizca **tam doktorda** ve gunde **en fazla bir kez**
  yapilir; `beyin durum` hicbir zaman aga cikmaz, yalnizca onbellegi okur.

  Bu satir "ag yok" ile "depo okunamiyor"u **ayirir** - ikisi ayni sey degil:

  | Durum | Satir |
  | --- | --- |
  | Yerel surum yayindakinden eski | **SORUN** - `beyin guncelle` |
  | **HTTP hatasi** (depo yok, ozel, ya da dal adi yanlis) | **SORUN** - `beyin guncelle` bu haliyle zaten calismaz, bkz. [9.9](#99-beyin-guncelle-calismiyor--http-hatasi) |
  | DNS / baglanti / zaman asimi - gercekten ag yok | yesil, sebebi yazilir |
  | Depo GitHub disi bir adres | yesil: "surum karsilastirmasi yapilamadi" (guncelleme yine calisir) |
  | Bu vault yayinin **kaynagi** | yesil: guncelleme ters yonde calisir |

**Belirti:** Bu satirlardan biri kirmizi, ya da `beyin yardim` ciktisinda bu
kilavuzdaki bir komut yok.

**Tani:**

```powershell
beyin nerede         # 'Motor surumu' satiri
beyin doktor         # 'surum tutarliligi' + 'motor guncelligi'
beyin yardim         # komut gercekten kurulu mu
```

**Neden olur:** Depoyu guncelledin ama `kur.ps1` calistirmadin; ya da motoru hic
guncellemedin. Gece gorevleri ve kancalar **kurulu kopyayi**
(`%USERPROFILE%\.beyin\beyin.ps1` ve `<vault>\motor\`) kullanir, depodaki
dosyalari degil.

**Cozum:** Bkz. [12. bolum](#12-guncelleme). Once kuru bak:
`beyin guncelle -KuruCalisma`.

### 9.9 `beyin guncelle` calismiyor / HTTP hatasi

**Belirti:** Doktor'un `motor guncelligi` satiri "UZAK DEPO OKUNAMIYOR (HTTP
hatasi)" diyor, ya da `beyin guncelle` "AG YOK - paket indirilemedi" ile
dusuyor - ama internetin calisiyor.

**Tani:**

```powershell
beyin ayar BEYIN_DEPO      # hangi depoya bakiliyor, degeri nereden geliyor
beyin guncelle -KuruCalisma
```

**Uc olasi neden:**

1. **Depo adresi yanlis.** Motoru fork ettiysen kendi adresini yaz:

   ```powershell
   beyin ayar BEYIN_DEPO https://github.com/<kullanici>/<depo>
   ```

   Sondaki `/` ve `.git` kirpilir. Tek seferlik denemek icin ayari degistirmeden:
   `beyin guncelle -Depo https://github.com/<kullanici>/<depo> -KuruCalisma`.

2. **Depo OZEL (private).** Guncelleme kimlik dogrulamayan bir indirme kullanir,
   yani **ozel depoda calismaz**. Depoyu public yap ya da motoru elle guncelle
   (bkz. [12. bolum](#12-guncelleme), "Elle guncelleme").

3. **Dal adi yanlis.** Varsayilan `main`. Deponun dali baska bir adsa:
   `beyin guncelle -Dal <dal>`.

> Depo GitHub disi bir adresteyse (ornegin kendi Git sunucun) doktor
> **yesil** doner ve "surum karsilastirmasi yapilamadi" der: surum karsilastirmasi
> GitHub'a ozgu bir adres donusumune dayanir. Guncelligi elle takip et.

### 9.10 Gece gorevleri kosmadi

**Belirti:** Sabah `85-daylogs` dolu ama `86-compiled` bos; doktor'un
`zamanlanmis gorevler` satiri kirmizi; ya da hic belirti yok - is sessizce
yapilmamis.

**Tani - sirayla:**

```powershell
beyin zamanla -Liste     # kayitli gorevler + her birinin son kosu sonucu
beyin makbuz -Gun 3      # motor gercekte ne yazdi, hangi sonucla
```

`-Liste` ciktisindaki sonuc kodunun anlami [8. bolumdeki](#8-gece-gorevleri)
tabloda. En sik ucu:

1. **Gorev hic kayitli degil.** Surumle gelen yeni gece gorevleri kendiliginden
   kurulmaz. Cozum: `beyin zamanla` (fikirli - var olanlari bozmaz).

2. **`0x3` / makbuzda `KIMLIK_YOK`.** Ajan CLI'inda oturum kapanmis. Kontrol et:

   ```powershell
   claude auth status
   codex login status
   ```

   Ikisinden **biri** acik olmasi yeter; motor hangisi varsa onu kullanir.

3. **Kod `0x0` ama is yine de yapilmamis.** Sarmalayici kostu, is duserek
   dondu. `beyin makbuz -Gun 3` notuna ve engine.log'daki `[zamanlayici]`
   satirlarina bak:

   ```powershell
   beyin nerede             # engine.log'un yolunu yazar
   ```

   `kimlik kontrolu sonuclanmadi ... is YINE DE deneniyor` satiri **hata
   degildir**: kimlik kontrolu zamaninda cevap veremedi, motor isi yine de
   denedi. Isin kendisi bir satir sonra ne yaptigini yazar.

**PC gece kapaliysa:** gorevler makineyi uyandirmaz. Kacirilan kosu acilista
yapilir (`StartWhenAvailable`), yani "son kosu 1 gun once" normaldir. Doktor
ancak **3 gun** hic kosulmadiysa kirmizi yanar.

**Model gerektiren gece gorevleri** yalniz `derle` ve `topla-uygula`'dir.
(`derin` zamanlanmis bir gorev DEGILDIR; elle kosuldugunda ayni kimlik on
kontrolunden gecer.)
`gom`, `bagla`, `copcu`, `bahcivan`, `denetle` ve `yedek` model cagirmaz - CLI
oturumu kapaliyken bile calisirlar.

---

## 10. Gizlilik ve guvenlik

- **Notlarin makinede kalir.** Vault duz Markdown'dir ve hicbir yere gonderilmez.
  Disariya cikan tek sey ozetleme sirasinda ajan CLI'ina giden metindir - yani
  zaten o ajanla konusurken gonderdigin icerik.
- **Sir redaksiyonu iki kez calisir:** metin ozetleyiciye gitmeden **once**
  maskelenir, diske yazilmadan once bir kez daha. Yine de kural basittir: token,
  parola, anahtar, cerez ve baglanti dizesi hicbir nota yazilmaz.
- **Enjekte edilen hafiza bloklari guvenilmez veri olarak etiketlenir.** Not
  icerigi, web alintisi ve log; talimatlari, onaylari ya da repo kurallarini
  gecersiz kilamaz. Prompt-injection sinyali gorulurse o gunun loguna uyari
  dusulur.
- **Depoya not gitmez.** `beyin yayinla` bir **izin verilenler listesi** kullanir:
  ne gonderilecegi tek tek sayilir ("sunlari haric tut" degil - o yaklasimda yeni
  eklenen bir klasor sessizce sizar). Gondermeden once her dosya sir deseni,
  mutlak kullanici yolu, e-posta **ve yerel ad** (proje/musteri adlari) icin
  taranir; bulunursa yayin **durur**.
- **Yerel ad listesi koda yazilamaz** - `yayinla.ps1`'in kendisi yayinlanan
  dosyalardan biri, yani listeyi icine koymak onu yayinlamak olurdu. Kaynagi:
  - `%USERPROFILE%\.beyin\yayin-yasak.txt` - **asil kaynak**. Diskte artik
    klasoru kalmayan adlari yalnizca bu dosya tutar. Satir basina bir terim,
    `#` yorum satiri.
  - calisma klasoru adlarindan turetim (ikinci kaynak).
  - `%USERPROFILE%\.beyin\yayin-izin.txt` - yanlis pozitif kacisi, ayni bicim.

  **Liste bos kalirsa yayin DURUR** (fail-closed). "Temiz" demez: burada yanlis
  negatif gercek zarardir.
- **Tarama uzanti beyaz listesi degil, ikili KARA listesi kullanir.** Yarin
  `motor\` altina eklenecek bir `.cmd`, `.mjs`, `.py`, `.html` ya da
  `.gitignore` kendiliginden kapsama girer; beyaz liste unutuldugu anda sessizce
  sizdirirdi. Atlanan tek sey bilinen ikili uzantilar ve ilk 8 KB'inda NUL bayti
  olan dosyalardir. **8 MB ustu bir dosya atlanmaz**: bulgu olarak raporlanir ve
  yayini durdurur - "taranamadi" ile "temiz" ayni sey degildir.
- **Uzak yedegin yoktur ve bu bilincli bir karardir.** `beyin yedek` yerel bir
  kopya alir. Notlarini bir buluta ya da baska bir diske tasimak istiyorsan bunu
  **sen** kurarsin - motor senin adina hicbir yere bir sey yuklemez. Kendi
  yedegini kendin tut.
- **Dosya izinleri:** `kur.ps1 -IzinleriSikilastir` ile miras kirilir ve tam yetki
  yalniz sahibi + SYSTEM + Administrators'a birakilir. Opt-in'dir; doktor'un
  `vault dosya izinleri` satiri durumu raporlar.
- **`BEYIN_DEPO` bir kod calistirma yoludur.** Guncelleme o depodaki `kur.ps1`'i
  calistirir ve paket imzalanmaz. Ayrintisi ve uyarisi
  [7. bolumde](#7-ayarlar).
- **Kill switch:** `BEYIN_VAULT` degiskenini var olmayan bir yola cevir; iki
  ajandaki tum kancalar sessizce devre disi kalir.

---

## 11. Kaldirma

```powershell
# Once ne silinecegini gor:
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kaldir.ps1 -KuruCalisma

# Sonra kaldir:
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kaldir.ps1

# Kurulumun biraktigi *.yedek-* kopyalari da silmek istersen:
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kaldir.ps1 -Yedekleri
```

**Ne silinir:**

- Kanca girdileri (Claude ve Codex ayarlarindan)
- `%USERPROFILE%\.beyin` icindeki motor dosyalari: `beyin-launcher.ps1`,
  `beyin.ps1`, `beyin.cmd`, `vault.txt`, `ayar.json`, `yayin-yasak.txt`,
  `yayin-izin.txt` - ve klasorde bunlardan baska bir sey kalmadiysa klasorun
  kendisi
- Codex simi (`%USERPROFILE%\.claude\hooks\beyin-launcher.ps1`)
- **Kullanici PATH'indeki `%USERPROFILE%\.beyin` girdisi** - geri alinir. (Deger
  turu korunarak yazilir, yani PATH'indeki diger degisken girdileri donmaz.
  Degisiklik yine **yeni terminalde** gecerli olur.)
- Skill baglantilari ve `\Beyin\` zamanlanmis gorevleri

`-Yedekleri` verilmezse `*.yedek-*` kopyalar birakilir ve sayisi raporlanir.

**Ne silinmez:** **vault'un kendisi.** Notlarin, gunluk loglarin, kavram notlarin
ve git gecmisin oldugu gibi kalir. Beyin susar, hafiza kalir. Vault'u da silmek
istiyorsan klasoru elle sil - bu betik bunu asla yapmaz.

**Geri alinmayan tek sey:** `-IzinleriSikilastir` ile degistirilmis vault ACL'i.
Kaldirma bunu geri almaz ve sonuc bolumunde soyler. Geri almak icin:

```powershell
icacls "<vault>" /reset
```

---

## 12. Guncelleme

Motoru depodan guncellemek icin tek komut:

```powershell
beyin guncelle
```

Bu komut motoru GitHub deposundan tazeler, ardindan `kur.ps1` ve `doktor`
calistirir. Ayrica ne eklendi / ne degisti / ne silindi diye ozet basar.

| Parametre | Ne yapar |
| --- | --- |
| `-KuruCalisma` | Ne degisecegini gosterir, **hicbir sey yazmaz**. |
| `-Zorla` | Surum ayni olsa da yapar; kaynak-vault korumasini ve kuratorlu dosya korumasini asar. |
| `-GeriAl` | En son **gecerli** yedegi geri yukler ve `kur.ps1` kosar. |
| `-Json` | Makine okunur cikti. |
| `-Depo` / `-Dal` | Baska bir depo/dal. Depo verilmezse `BEYIN_DEPO` ayarindan cozulur; dal varsayilani `main`. |

Depo cozum sirasi: **`-Depo` parametresi > `BEYIN_DEPO` ayari > varsayilan.**
Depo adresinin guvenlik anlami icin bkz. [7. bolum](#7-ayarlar).

### Neye dokunur, neye dokunmaz

**Dokundugu kume - motor yuzeyi:**

- klasorler: `motor\hooks`, `motor\scripts`, `motor\skills`, `kurulum`,
  `templates`
- kok dosyalar: `AGENTS.md`, `CLAUDE.md`, `brain.config.json`, `.beyin-version`,
  `LICENSE`, `CHANGELOG.md`

**Bunun disinda kalan her sey hedef kumenin disindadir:** okunmaz, yedeklenmez,
yazilmaz, silinmez. Yani not klasorlerin (`85-daylogs`, `86-compiled`, `80-memory`
ve tum kuratorlu bolgeler), `.obsidian`, `.git` ve her duzeydeki `.state`
**aynen kalir**.

### Kuratorlu dosyalar ezilmez

`AGENTS.md`, `CLAUDE.md`, `brain.config.json` ve `templates\` altindaki her sey
senin kendi makinene gore duzenledigin dosyalardir. Bunlar yerelde
**degistirilmisse guncelleme onlari ATLAR** ve adiyla raporlar; uzerine yazmak
icin `-Zorla` gerekir. Pakette yeni gelen ya da yerelde hic degismemis olan
sessizce yazilir.

`templates\` artik guncelleniyor (daha once surumle gelen sablon duzeltmeleri
kurulu bir vault'a hic ulasmiyordu), ama **silme listesine girmez**: paketten
kaldirilan bir sablon senin diskinden silinmez.

`.beyin-version` bu korumanin **disindadir**: o dosya motorun surum damgasidir,
senin icerigin degil - korunsaydi surum karsilastirmasi kalici olarak yalan
soylerdi.

### Guvenlik aglari

- Yazmadan once yedek alinir: `motor\scripts\.state\guncelleme-yedek\<zaman damgasi>\`
  (en yeni uc tanesi tutulur).
- **Yedek tamamlanma isareti tasir.** Yedekleme dongusu tamamen bittikten sonra
  klasore bir `TAMAM.txt` yazilir: surum satiri, dosya sayisi ve tam goreli yol
  listesi. `-GeriAl` **en yeni GECERLI** yedegi alir; isareti olmayan ya da
  listesi diskle uyusmayan bir yedegi **reddeder**, hicbir seyi degistirmez ve
  sifir-disi cikar (kac adayin reddedildigini yazar).
- `kur.ps1` guncelleme sonrasi basarisiz olursa yedek **otomatik geri yuklenir**
  ve motor eski haline doner.
- `doktor` uyarisi guncellemeyi geri **almaz** (bir doktor uyarisi guncellemeyi
  bozuk yapmaz); cikti bunu acikca soyler ve gerekirse `-GeriAl` onerir.
- **Kaynak vault korumasi:** bu vault yayinin kaynagi ise guncelleme ters yonde
  calisip gelistirmeyi ezerdi; betik bunu tanir ve durur (`-Zorla` ile asilir).
- Hedef klasorlerden biri **junction/symlink** ise islem reddedilir
  (`GUNCELLE_PAKET_BOZUK`, cikis 2).

**Cikis kodlari artik anlamlidir** - basarisiz bir guncelleme 0 donmez. Sonuc
etiketleri makbuza yazilir: `GUNCELLE_OK`, `GUNCELLE_GUNCEL`, `GUNCELLE_KURU`,
`GUNCELLE_AG_YOK`, `GUNCELLE_PAKET_BOZUK`, `GUNCELLE_YEDEK_GECERSIZ`,
`GUNCELLE_KUR_BASARISIZ`, `GUNCELLE_GERI_ALINDI`, `GUNCELLE_KAYNAK_VAULT`,
`GUNCELLE_COKTU`.

> **Gecis notu:** `TAMAM.txt` isareti sonradan geldi. Daha once alinmis
> yedeklerde bu dosya yoktur, yani `-GeriAl` onlari **gecersiz sayar** ve
> kullanmaz. Ilk basarili `beyin guncelle` gecerli bir yedek uretir; ondan sonra
> `-GeriAl` normal calisir.

### Elle guncelleme (alternatif)

```powershell
cd <vault>
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File kurulum\kur.ps1
```

Elle yolda **`kur.ps1` calistirmak sarttir**: kancalar ve gece gorevleri kurulu
kopyayi (`%USERPROFILE%\.beyin\beyin.ps1`) cagirir, depodaki dosyayi degil.
Kurulum idempotenttir, icerigini ezmez.

### Guncelleme sonrasi

```powershell
beyin durum          # 'surum tutarliligi' satiri yesil olmali
beyin zamanla        # yeni bir gece gorevi eklendiyse kayitlari tazeler
```

Codex kullaniyorsan, kanca tanimi degistiyse Codex TUI'de `/hooks` ile yeniden
onaylaman gerekebilir.

---

## Ilgili belgeler

- [README.md](../README.md) - depo tanitimi ve hizli kurulum
- `AGENTS.md` (vault kokunde) - ajan calisma sozlesmesi
- `CLAUDE.md` (vault kokunde) - Claude Code icin yonlendirici
- `brain.config.json` (vault kokunde) - vault sozlesmesi ve klasor haritasi
