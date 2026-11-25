# Mindrop tasarım dili

## Ürün vaadi

**Mindrop, günlük hayatta karşına çıkan küçük bir bilgiyi aklındayken kaydetmek ve gerektiğinde geri bulmak için var.** Bu bilgi duyduğun bir isim, gördüğün bir kod, bir film adı veya o anda verdiğin bir karar olabilir. İhtiyaç beş dakika sonra da, bir yıl sonra da ortaya çıkabilir.

- **Kaydet.** Kullanıcı, bilgi hâlâ aklındayken birkaç saniye içinde onu kendi seçeceği, sonradan hatırlayabileceği bir anahtar kelimeyle kaydedebilmeli.
- **Geri bul.** Spotlight ana erişim yüzeyi. Kullanıcı gerektiğinde o kelimeyi arar ve gösterilebilen değeri doğrudan sonuçtan okur. Hassas kayıt Spotlight’ta kilitli anahtar kelime olarak bulunur. Değeri görmek için uygulamadaki mevcut kilit açma akışı kullanılır.
- **Kullan.** Uygulamada kayıt oluşturmak, kategorilere göz atmak, detayları okumak ve kaydın türüne uygun eylemi yapmak kolay olmalı.

Bir kullanım hikâyesi anlatırken kayıt anını, daha sonra hatırlanan kelimeyi ve bulunan değeri birbirine bağla. `parking` → `Level B2 blue zone 147`, `printer ink` → `305XL black` ve `shoe size` → `EU 42` örnekleri uygulamada, web’de ve mağazada aynı anlamı taşıyabilir. Ekran çekimlerinde gerçek kullanım senaryolarını örnek değerlerle göster.

## Gerçek kullanım örnekleri

Bu senaryolar geliştiricinin kendi kullanımından geliyor. Bunları uygulama ekran görüntülerinde, pazarlama metinlerinde ve “Böyle de kullanabilirsin” anlatımında kullan.

- **Havaalanındaki kapı numarası.** Kalkış kapısını gördüğünde `gate` anahtar kelimesiyle `C24` gibi bir değer kaydet. Terminalde yürürken kapıyı hatırlamak istediğinde Spotlight’a `gate` yaz ve kaydettiğin numarayı gör. Bu örnek, birkaç dakika sonra işe yarayan kısa bir bilgiyi anlatır. Görselde anahtar kelimeyi ve kapı numarasını gerçek Spotlight sonucunda göster.
- **YouTube’da duyulan film veya dizi önerisi.** Video oynarken duyduğun adı `film önerisi` ya da `dizi önerisi` gibi aklına gelecek bir kelimeyle kaydet. İzleyecek bir şey aradığında, videoyu hangi gün izlediğini hatırlaman gerekmeden kaydettiğin adı bul. Hızlı kayıt ekranı ile günler sonra çıkan Spotlight sonucunu aynı film veya dizi adıyla bağla.
- **Eşyaların periyodik bakım talimatları.** Kahve makinesi ya da robot süpürge gibi bir eşyanın bakım adımlarını, kılavuz elinin altındayken `kahve makinesi bakımı` gibi bir anahtar kelimeyle kaydet. Haftalar veya aylar sonra bakım yaparken kelimeyi ara ve kaydı açıp adımları oku. Bu örnekte detay ekranı, birden fazla satırı olan bir bilginin nasıl okunup kullanıldığını gösterir.

## Ortak marka dili

Yüzeyleri aynı marka işareti, palet, anlaşılır örnekler ve sakin bir görsel hiyerarşi birbirine bağlar. Sıcaklığı web’de kâğıt tonuyla, hızlı erişim hissini ise anahtar kelime ve değerin rahat okunmasıyla ver.

| Karar | Kullanım |
| --- | --- |
| Bricolage Grotesque | Web ve App Store’daki pazarlama başlıklarında **700**, kısa marka açıklamalarında **400** kullan. Web’deki ikincil metinlerin rolü aşağıdaki tipografi bölümünde tanımlıdır. Uygulama ekranları ve Spotlight, platform tipografisiyle çalışır. |
| Kobalt mavisi `#3456D1` | Ana marka rengi. Varsayılan uygulama ikonunun zemini ve pazarlama yüzeylerindeki vurgular. |
| Gece laciverti `#101522` | Ana ekran gradient’inin bitiş rengi, koyu modda sheet zemini ve koyu ikonun zemini. Web’de koyu bölümlerin zemini ve açık bölümlerin metin rengi. |
| Mavi-lacivert `#263554` | Koyu modda ana ekran gradient’inin sol üst başlangıç rengi. |
| Açık kobalt `#B9CAFF` | Gece laciverti zemin üzerindeki koyu mod QI işareti. |
| Mavi-gri `#25324A` | Koyu modda sheet ve form satırlarının zemini. How Mindrop Works ekranındaki Spotlight önizleme paneli de bu tonu kullanır. |
| Sıcak kırık beyaz `#F7F4EC` | Kâğıt hissi veren ikincil web zemini. |

Uygulama ikonunda **büyüteç ve imleç** birlikte QI işaretini oluşturur. Varsayılan görünümde kobalt mavisi `#3456D1` zemin üzerinde fildişi `#FCFAF5`, koyu görünümde gece laciverti `#101522` zemin üzerinde açık kobalt `#B9CAFF` kullan. Büyüteç kalın bir halka ve halkaya bağlı kısa, yuvarlak sapla Q gibi okunur. İmleç benzer kalınlıkta tek bir dikey çizgidir. İki şekli kapsülsüz, birlikte ortalanmış ve ikon genişliğinin yaklaşık %65’ini kaplayacak biçimde yerleştir. Ana ekran boyutunda ikisinin de okunabilirliğini kontrol et. Mevcut sürümü temsil eden görsellerde o sürümün gerçek ikonunu kullan.

Uygulama ikonu, Control Center’daki Yeni Kayıt kontrolü, Mac menü çubuğu, paylaşım uzantıları ve web’deki marka işareti aynı QI çizimini kullanır. Sistem şablonlarında renk ve boşluk platforma göre uygulanır. Ana çizim [Icon Composer SVG katmanında](Mindrop/Resources/mindrop_icon.icon/Assets/01-search-mark.svg) tutulur.

Uygulama içi eylemler ve kategoriler için SF Symbols kullan. Kategorinin simgesi listede, detayda, menüde ve Spotlight sonucunda aynıdır. Kategori renkleri mevcut paleti kullanır.

## İnce düşünülmüş ayrıntılar

Mindrop’ta özen, kullanıcının tam ihtiyaç duyduğu anda fark ettiği küçük ayrıntılarda hissedilmeli. Bir ayrıntı bilgiyi daha rahat okutabilir, bir eylemin sonucunu anlaşılır kılabilir veya aynı hikâyeyi uygulamadan web’e ve App Store’a taşıyabilir.

- **Uygulama.** Kopyalama eyleminin ardından görünen kısa “Kopyalandı” geri bildirimi kullanıcıya işlemin tamamlandığını söyler. Bir kodda benzer karakterlerin kolay ayırt edilmesi de aynı özenin tipografideki karşılığıdır.
- **Web.** Açılışın altında bir örnek kaydın anahtar kelimesiyle değerini ayıran ince çizgi, hem hızlı okumayı sağlar hem de küçük bir indeks kartını çağrıştırır.
- **App Store.** Başlıkta sözü edilen fayda, altındaki gerçek ekranda bir bakışta görülebilmeli. Bir örnek sonraki görselde devam ediyorsa anahtar kelime ve değer aynı kalmalı.

Bir ayrıntıyı değerlendirirken hangi anda fark edildiğine ve kullanıcıya ne kattığına bak. Özeni küçük ekranda, uzun bir değerle ve bir işlemin hemen sonrasında da kontrol et.

## Uygulama

İlk tasarım çalışması uygulamada yapılacak. iPhone’daki iki sütunlu cam kartlar, renkli kategori ikonları ve küçük anahtar kelime ile belirgin değer hiyerarşisi başlangıç referansıdır. Açık kararlar, ana ekranın yoğunluğu ve yerleşimi, kategori renginin ağırlığı, kobaltın uygulamadaki rolü ve detay eylemlerinin konumudur. Bunları mevcut davranışları göz önünde bulundurarak değerlendir. iPad ve Mac’te yerleşimi kendi ekran alanına ve platform davranışına göre ele al.

iPhone ve iPad’de koyu modda klasör listesi, klasör içi, hafıza detayı ve Son Silinenler sol üstte `#263554` ile başlayan ve sağ alta doğru gece laciverti `#101522` tonuna inen gradient’i kullanır. Ayarlar ve sheet’lerde zemin gece lacivertidir. Form satırları ve How Mindrop Works önizleme paneli mavi-gri `#25324A` kullanır. Aydınlık modda sistemin ekran ve satır zeminlerini kullan. Ana liste kartlarında varsayılan Liquid Glass, kategori simgelerinde kategori rengi kullanılır.

- **Kayıt ekleme.** Anahtar kelime ve değeri girişin odağı yap. iPhone ve iPad’de kayıt formunda anahtar kelime alanının klavyesindeki İleri tuşu odağı değer alanına taşır. Dört karakterden kısa bir anahtar kelimeyle kaydetmeye çalışıldığında Spotlight açıklamasını 1,5 saniye sistem pembesiyle vurgula. Değer boşsa yuvarlatılmış satırın tamamını pembe çerçeveyle işaretle ve kullanıcı bilgi girene kadar çerçeveyi göster. Her geçersiz kaydetme denemesinde uyarı metni ve boş değer alanı kısa süre sağa sola sallanır. Odağı ilk düzeltilmesi gereken alana taşı. Hareketi Azalt açıkken yalnızca renk vurgusu uygulanır. Kullanıcı daha sonra neyi arayacağını kayıt anında anlayabilmeli. Uygulama içinden ve paylaşım menüsünden kaydetme akışlarını göz önünde bulundur. Mevcut otomatik kategorileştirme ve sonradan düzenleme, hızlı kaydın bir parçasıdır.
- **App Store puanlaması.** Uygulamanın Yeni Kayıt ekranında beş başarılı kayıttan sonra, form kapandığında ve uygulama ön plandaysa StoreKit puanlama isteğini planla. Son istekten sonra en az beş yeni kayıt, 120 gün ve yeni bir uygulama sürümü gerekir. Cihazda başarılı kayıt sayısını ve son isteğin tarihini ve sürümünü tut. İsteğin gösterilip gösterilmeyeceğini StoreKit belirler.
- **Klasörler ve kategoriler.** iPhone ve iPad ana ekranında Genel ve kullanıcının eklediği klasörler tek sütunda görünür. Klasör satırları standart yazı boyutunda 60 punto yüksekliğindedir. Nötr cam satırda klasör simgesi, ad ve kayıt sayısı göster. Klasör simgelerinde aydınlık modda kobalt `#3456D1`, koyu modda `#E0E8FF` kullan. Yeni Klasör eylemi ana ekranın araç çubuğunda Yeni Kayıt’ın yanında yer alır. Mac’te klasörler kenar çubuğunda görünür. iPhone ve iPad’de tek dokunuş özel klasörü açar, uzun basınca satırın tamamı kayıt kartlarıyla aynı sistem menüsünü açar. Özel klasörün menüsünde Yeniden Adlandır eylemini Klasörü Sil’in üstünde göster. Mac’te bu eylemlere sağ tıklamayla erişilir. Yeniden Adlandır, Yeni Klasör formunu mevcut ad seçili ve giriş alanı odaklanmış olarak açar. Kaydet yalnızca klasörün adını günceller. Onay ekranında klasörün adını ve içindeki kayıtların Son Silinenler’e taşınacağını belirt. Silinmiş kayıt olduğunda Son Silinenler klasör listesinin sonunda sistem satırı olarak görünür. iPhone ve iPad’de bu satıra uzun basınca Çöp Kutusunu Boşalt eylemini göster. Eylem, klasör içindeki kalıcı silme onayını açar. Mevcut kayıtlar Genel’de açılır. Klasör içinde kayıtları kategori başlıkları altında iPhone ve iPad’in mevcut kart grid’iyle göster. Geri gidildiğinde klasör listesine dön. Çok kayıt olduğunda kategori başlıklarının, ikonların, anahtar kelimelerin ve değerlerin taranabilirliğini değerlendir. Kısa kodları, uzun bağlantıları ve gizli değerleri aynı tasarımda dene. Kategoriyi renk ile birlikte ad veya ikonla da belli et. [Klasör kararları](FOLDERS-AND-WIDGETS.md#otomatik-kategoriler-ve-klasörler)
- **Aşağı çekme.** iPhone ve iPad’de klasörler ekranı, klasör içindeki kayıt ızgarası, Yığın ve Son Silinenler en üstteyken aşağı çekiş, içeriğin üzerinde uçları saydamlaşan kobalt bir yay gösterir. Çekiş arttıkça ortası aşağı inip sivrilir ve uçları birbirine yaklaşır. Yay eşikte belirginleşir. Eşikten sonra her ek çekiş yayı biraz daha gerer ve bu değişim gitgide küçülür. Bırakıldığında yay, listenin geri sekmesinden bağımsız olarak toparlanır. Daha yüksek gerginlik, dönüş süresini 95 milisaniyeden 35 milisaniyeye doğru kısaltır. Eşik 156 puntoya kadar çıkar ve kısa pencerelerde kaydırma alanının yüksekliğine uyarlanır. Destekleyen cihazlarda parmak ekrandayken geçilen her tam yüzde adımı tok ve hafif bir haptik darbe verir. Sıfır sessizdir. Darbe şiddeti yüzde 100’e kadar artar ve daha derin çekişte üst sınırda devam eder. Eşik her geçildiğinde daha keskin bir tık gelir ve yakın adımlar kısa süreliğine hafifler. Eşiğin üzerinde parmak kaldırıldığında güçlü, kısa bir fırlatma darbesi gelir. Şiddeti, yüzde 100’ün üzeri dahil, bırakma anındaki çekişten hesaplanır. Eşik üzerinde bırakış ana ekranda Genel’e, klasör içinde o klasöre kayıt eklemek için Yeni Kayıt ekranını açar. Son Silinenler’de kalıcı silme onayı, Yığın’da Kayıt Seç açılır. Son Silinenler boşken bırakış yalnızca geri bildirim verir.
- **Klasör içinde çoklu seçim.** iPhone ve iPad’de filtreyi ve Kayıt Seç eylemini sağ altta aynı grupta göster. Arama düğmesini sabit bir boşlukla ayır. Seçim açıkken Kayıt Seç’in yerinde Bitti eylemini göster. Mac’te Kayıt Seç klasör araç çubuğunda yer alır. Seçim işaretini kartın ölçüsünü etkilemeden göster. Arama yaparken veya kategori filtresini değiştirirken seçimi koru. iPhone ve iPad’de seçim açıkken üst araç çubuğundaki Yeni Kayıt düğmesinin yerine seçili kayıt sayısını gösteren işlem menüsünü koy. Klasöre Taşı, Yığına Ekle ve Sil eylemlerini aynı menüde topla. Yığına Ekle’nin yanında Yığın simgesini kullan. Silmeden önce onay iste ve kayıtları Son Silinenler’e taşı.
- **Kayıt menüleri.** iPhone ve iPad’de klasör, arama, süresi dolmuş kayıtlar ve Yığın’da kayıt kartının tamamını Son Silinenler’deki gibi sistem menüsünün açıldığı yüzey olarak kullan. Uzun basınca eylemleri, tek dokunuşta kayıt detayını aç. Mac’te kayıt eylemlerini satır sonundaki üç nokta menüsünde ve sağ tıklamada göster.
- **Detay.** Değeri öne çıkar ve ona uygun eylemi kolay buldur. Wi‑Fi için QR kodu, tek başına bir web adresi için varsayılan tarayıcıda açma, uygun adres ve telefon kayıtları için yol tarifi veya arama gibi mevcut davranışları esas al. Değerin okunması, kopyalanması ve paylaşılması anlaşılır olsun. Geçici kayıtların kesin bitiş tarihini anahtar kelimenin altında, değer kartından önce göster. Alt satıra süre dolumuna veya kalıcı silmeye kalan zamanı koy. Hassas değerlerin ve QR kodlarının görünürlüğünü mevcut kilit açma davranışına bağla.
- **Yığın.** iPhone ve iPad ana ekranında Genel’in hemen üstünde, orta boy Ana Ekran widget’ının önizlemesi görünür. İlk altı uygun kayıt iki sütun ve üç satıra yerleşir. Önizlemede boş hücreler dahil tüm ızgara çizgilerini göster. Küçük anahtar kelimenin altında belirgin değer için iki satıra kadar yer ayır. Önizlemeye dokununca Yığın açılır. Yığın boşken aynı konumda doğrudan kayıt seçiciyi açan **Kayıt Seç** eylemini göster. Mac’te Yığın kenar çubuğunda kayıt sayısıyla görünür. Uygun kayıtların bağlam menüsünde Kopyala’nın hemen altında Yığına Ekle eylemini göster. Yığın ekranında kayıt seçme, sıralama ve Yığın’dan çıkarma eylemlerini sun. iPhone ve iPad’de Yığın satırını tam sola kaydırmak üyeliği hemen kaldırır ve kayıt kendi klasöründe kalır. [Yığın akışı](FOLDERS-AND-WIDGETS.md#yığın-ve-widgetlar)
- **Ana Ekran widget’ı.** Küçük boyda Yığın’ın ilk uygun kaydını göster. Anahtar kelimeye iki, değere beş satıra kadar yer ayır. Kısa değerleri büyük göster, uzun değerlerde yazıyı alana göre küçült. Orta boyda uygulamadaki önizlemeyle aynı 2 × 3 ızgarayı kullan. Büyük boyda ilk kayıt üstte tam genişlikte, sonraki sekiz kayıt altta 2 × 4 ızgaradadır. iPad’de çok büyük boyda ilk iki kayıt solda, sonraki on kayıt sağda 2 × 5 ızgaradadır. Tam renkli görünümde açık modda `#FFFFFF` → `#F1F4FF`, koyu modda `#2A3956` → `#192438` gradient’ini kullan. Öne çıkan kayıtların anahtar kelimelerinde açık modda kobalt `#3456D1`, koyu modda açık kobalt `#B9CAFF` kullan. Renkli ve saydam sistem görünümlerinde zemini sisteme bırak. Tüm boylar dokunulduğunda Yığın’ı açar. [Ana Ekran düzenleri](FOLDERS-AND-WIDGETS.md#ana-ekran-widgetı-ve-uygulama-önizlemesi)
- **Kilit ekranı widget’ı.** Saatin altındaki dikdörtgen alanda anahtar kelimeyi küçük, değeri daha büyük ve belirgin göster. Widget’ın rengi kilit ekranına uyum sağlar. Varsayılan düzen Alt alta; beş düzen arasından kilit ekranında seçim yapılabilir. Dörtlü ızgarada ilk değer sütuna sığmadığında tam genişlikte göster ve altta iki kayda yer ver. Widget’a dokununca Yığın’ı aç. Kilit ekranı ve Ana Ekran widget’ları için kaynak, Mindrop’un Yığın’dan ürettiği salt okunur veri kopyasıdır. [Beş widget düzeni](FOLDERS-AND-WIDGETS.md#kilit-ekranı-düzenleri)
- **Apple Watch widget’ı.** Uygun saat kadranlarında dikdörtgen komplikasyon ilk uygun kaydı gösterir. Akıllı Gruplama’da ilk iki uygun kayıt alt alta, anahtar kelimeler küçük ve değerler belirgin görünür. Akıllı Gruplama’nın zemini Yığın gradient’ini, komplikasyon kadranın sistem görünümünü kullanır. Widget’a dokunulduğunda saatte tam değerlerin okunabildiği Yığın ekranını aç. [Apple Watch düzenleri](FOLDERS-AND-WIDGETS.md#apple-watch)

## Cihazlar arasında erişim

iCloud senkronizasyonu açık ve kullanılabilir olduğunda, aynı iCloud hesabındaki desteklenen iPhone, iPad ve Mac’ler arasında güncel kayıtlara erişilebilir. Bir cihazda kaydedip diğerinde bulmayı gösterirken tamamlanmış senkronizasyon durumunu ve o cihazdaki gerçek sonuç görünümünü kullan. iCloud yedeklemesini geri yüklenebilen tarihli bir kopya olarak anlat.

## Web sitesi

Uygulama tasarımı ve yeni ekran görüntüleri netleşince web’i ayrı bir çalışma olarak ele al. Mevcut açılış yerleşimini ve standart Spotlight animasyonunu koru. Açılış metni, hızlı kayıt ile sonradan Spotlight’ta bulmayı aynı hikâyede bağlayabilir.

Uygulamadaki ince ayrıntılara web’de görünür yer ver. Her ayrıntıyı bir ihtiyaç, kullanıcının yaptığı eylem ve elde ettiği sonuç üzerinden anlat. Örneğin misafir Wi‑Fi bilgisini isterse QR kodunu gösterebilir, kaydettiği bir bağlantıyı varsayılan tarayıcıda açabilir veya iPhone’da kaydettiği bir bilgiyi Mac’te bulabilir. Kısa metni gerçek ekranla eşleştir ki kullanıcı hem neyi düşündüğümüzü hem de bunu kendi hayatında nerede kullanabileceğini görsün.

Yukarıdaki üç gerçek kullanım örneğini web’de ayrıntılandır. Okuyucu bilginin nerede karşısına çıktığını, hangi kelimeyle kaydettiğini, ne zaman tekrar ihtiyaç duyduğunu ve o anda ne gördüğünü anlayabilmeli. Ekran görüntüleriyle pazarlama metninde aynı örnek kelimeyi ve değeri kullan.

İndeks kartı hissini açılışın altındaki statik bölümlerde kullan. Onaylanan taslakta açık zemindeki üç adımı başlık, açıklama ve aralık ayırır. Altındaki lacivert bölümde küçük bir örnek kart, ince bir kobalt çizgi veya ufak bir ayraçla kâğıdı çağrıştırır. Bu taslağı yeni uygulama ekranlarıyla birlikte yeniden değerlendir.

### Stack bölümündeki cihaz görselleri

Stack’i Spotlight açılışının hemen altında **Today’s details, at a glance.** başlığıyla göster. Masaüstü kompozisyonunda üç gerçek ekran görüntüsünün her biri kendi cihaz çerçevesi içinde yer alır.

- **Solda** 9° sola yatık iPhone. Ana Ekran’da orta boy Stack widget’ı.
- **Ortada** dik iPhone. Kilit Ekranı’nda saatin altında, alt alta yerleşimli Stack widget’ı.
- **Sağ önde** 9° sağa yatık Apple Watch. Akıllı Gruplama’da Stack widget’ı.

Cihazları kenarlarından hafifçe üst üste bindir. Apple Watch’u ortadaki iPhone’un sağ alt köşesine al. Üç ekranda da `gate` ve `seat` kayıtlarının `C24` ve `18A` değerleri görünür kalsın. Mobilde Kilit Ekranı ile Apple Watch’u birlikte göster ve sola yatık Ana Ekran iPhone’unu bu çiftin altına yerleştir.

### Web’de iCloud senkronizasyonu

Ana sayfanın altbilgiden önceki son bölümünde **Save it here. Find it there.** başlığıyla iCloud senkronizasyonunu anlat. iPhone’da `Lisbon trip` klasörüne kaydedilen `hotel address` kaydını iPad ve Mac’te `12 Rua Exemplo, Lisbon` değeriyle göster.

- **iPad.** `Lisbon trip` klasörü açık ve adres kartı görünür. iPad’i dikey, düz karşıdan çekilmiş bir kadrajla Mac’in sol önüne yerleştir.
- **macOS.** Mindrop kenar çubuğunda `Lisbon trip` seçili, adresin detay ekranı açık. Mac’i yatay, düz karşıdan çekilmiş bir kadrajla arkaya yerleştir. İki cihazın çerçevesi kenarlarından hafifçe örtüşür.

Gerçek çekimleri aynı iCloud hesabındaki desteklenen cihazlar senkronizasyonu tamamladıktan sonra al. Kısa metin, isteğe bağlı iCloud Sync açıkken kayıtların, klasörlerin ve Stack’in cihazlar arasında güncel kaldığını söyler. Adres iki görselde de mobil genişlikte okunabilmeli.

### Günlük hayattan sahneler

Açılışın altında gerçek kullanım hikâyelerine ayrı bölümler ayır. Her bölüm tek bir tanıdık sahneyi anlatır. Fotoğraf, ihtiyacın doğduğu yeri ve nesneyi gösterir. Başlık o anda neye ihtiyaç duyulduğunu söyler. Gerçek Spotlight sonucu veya uygulama ekranı, Mindrop’la bilginin nasıl geri bulunduğunu ve kullanıldığını gösterir.

Kahve makinesi, otopark ve havaalanı, uygulama tasarımı tamamlandıktan sonra web aşamasında değerlendirilecek sahne fikirleridir. Aşağıdaki fotoğraflar sahne ve kadraj referansı olarak saklanır. Başlıklar ve kayıt değerleri örnektir.

| Sahne | Fotoğraf ve anlatım | Yanında gösterilecek gerçek ekran |
| --- | --- | --- |
| **Kahve makinesinin bakım günü** | Güneş alan mutfak tezgâhında espresso makinesi. Haftalar önce not ettiğin adımlara şimdi, makinenin başındayken ihtiyacın var. [Tim Schmidbauer · Unsplash](https://unsplash.com/photos/shiny-espresso-machine-on-a-kitchen-counter-65xj-7EuW3U) | Mindrop’ta `kahve makinesi bakımı` detay ekranı. Filtre sepetini durulama, damlama tepsisini temizleme ve su haznesini temizleme gibi örnek adımları ayrı satırlarda okunur göster. |
| **Arabayı nereye park etmiştim?** | Katlı otoparkta birbirine benzeyen sıralar ve mavi A kolonları. Arabaya dönerken aradığın ipucu fotoğrafta da okunur. [Declan Sun · Unsplash](https://unsplash.com/photos/an-empty-parking-garage-with-lettered-columns-OMLhHXm9eJg) | iPhone Spotlight’ta `parking` araması ve fotoğrafla eşleşen `Blue zone A` sonucu. |
| **Kapı kaçtı?** | Terminalde yürürken önce kaydettiğin kapı numarasına bakarsın. Aday fotoğrafta tabeladaki `21` okunuyor. [Celine Ly · Unsplash](https://unsplash.com/photos/airport-departure-gate-with-digital-display-showing-number-21-saf9QuAcjIk) | iPhone Spotlight’ta `gate` araması ve `21` sonucu. Kullanıcı kaydettiği numarayı geri bulur. |
| **Videoda önerilen film neydi?** | Evde koltuktan video izlerken bir film adı duyarsın. Adı hemen kaydedersin, birkaç gün sonra izleyecek bir şey ararken hatırlarsın. [Thirdman · Pexels](https://www.pexels.com/photo/photo-of-a-man-and-a-woman-watching-on-a-laptop-while-sitting-on-a-sofa-7237083/) | Mindrop kayıt ekranında `film önerisi` ve `Arrival`. Geri bulma anı da gösterilirse Spotlight’ta aynı anahtar kelimeyi ve film adını kullan. |
| **Misafir Wi‑Fi’a nasıl bağlanır?** | Evde yan yana oturup telefona bakan iki arkadaş. Misafir ağı sorduğunda QR kodunu açarsın. [RDNE Stock project · Pexels](https://www.pexels.com/photo/photograph-of-friends-looking-at-a-cell-phone-5921967/) | Mindrop’ta `misafir wifi` kaydının QR kodu. Örnek ağ verisiyle, kodun mevcut kilit açma akışından sonra göründüğü durum. |
| **Bu lambanın ampulü hangisiydi?** | Evde ampulü değiştirirken ambalajdaki küçük bilgiyi kaydedersin. Bir dahaki alışverişte duy tipini ve ışık rengini hatırlamak için ararsın. [cottonbro studio · Pexels](https://www.pexels.com/photo/person-holding-white-light-bulb-4107180/) | Spotlight’ta `ampul` araması ve `E27 · 2700 K` sonucu. |

Fotoğrafı ve ekranı yan yana dene. Mobilde birbirine yakın tut ve ekrandaki değerin büyütmeden okunabildiğini kontrol et. Fotoğrafta görünen bir bölüm harfi veya kapı numarası varsa aynı değeri kayıt örneğinde kullan. Kullanılacak son kadrajı yeni ekran görüntüleriyle birlikte seç. Havaalanı adayında havayolu ve mağaza yazıları bulunuyor. Kadrajda kapı numarası görünürken bu yazıların ne kadar öne çıktığına bak. [Unsplash lisansı](https://unsplash.com/license) · [Pexels lisansı](https://www.pexels.com/license/)

Fotoğrafı, başlığı ve ekrandaki örneği aynı ana bağla. Kullanıcı sahneyi görünce **“Ben de bunu yaşıyorum”**, sonucu görünce de **“Mindrop burada işime yarar”** diyebilmeli. Bu tanıdıklığı web tasarımını değerlendirirken ölçüt olarak kullan.

#### Nano Banana için fotoğraf tarifleri

Yukarıdaki fotoğraflar ışık ve kadraj referansı olarak kullanılabilir. Ortak tarifi aşağıdaki sahnelerden biriyle birleştir ve her sahneyi ayrı üret. Ekran fotoğrafın yanında ayrı yerleştirilecekse yalnızca sahneyi üret. Bölüm başlığını web’de Bricolage Grotesque ile diz.

**Ortak tarif**

> Mindrop web sitesi için gündelik hayattan tek bir fotogerçekçi fotoğraf üret. Sahne gerçek bir anda, göz hizasından çekilmiş gibi dursun. Yumuşak ortam ışığı, doğal gölgeler, hafif gren ve mat renkler kullan. Sıcak kırık beyaz, doğal ahşap ve nötr tonlar mekâna uyduğu yerde görünsün. Kobalt, varsa bir tabela veya gündelik eşya üzerinde küçük bir vurgu olarak kalsın. Yatay 4:3 kadrajla başla ve sahnenin ana ipucunu daha dar bir mobil kırpımda da görülecek yerde tut. Fotoğrafı tam kadraj ver. Logo, pazarlama yazısı, filigran, uygulama arayüzü veya cihaz maketi ekleme. Yalnızca sahne tarifinde istenen tabela karakterleri görünsün.

**Sahne tarifleri**

- **Kahve makinesi.** Yaşanmış bir ev mutfağında, ahşap tezgâhta kompakt paslanmaz çelik espresso makinesi. Filtre sepeti makinenin önünde, yanında katlanmış bir bez. Pencereden gelen sabah ışığı tezgâha düşüyor. Makinenin önü ve temizliğe hazırlanan parçalar kadrajın odağında.
- **Otopark.** Katlı otoparkta yürüyen birinin göz hizasından tekrar eden beton kolonlar ve park etmiş birkaç araç. Öndeki kolonda mavi bir bant ve üzerinde tek, okunaklı beyaz `A`. Plakalar seçilmiyor. Kadraja baktığında hangi bölüme döneceğini anlamalısın.
- **Havaalanı.** Gündüz, terminal koridorunda kapıya doğru yürüyen yolcular. Ön planda kadraja kısmen giren bir kabin valizi, biraz ileride tek ve net `21` numaralı kapı tabelası. Büyük camlardan doğal ışık geliyor. Tabela üzerinde havayolu adı veya logo bulunmuyor.
- **Film önerisi.** Akşam evde koltukta oturup dizüstü bilgisayardan bir video izleyen kişi. Omuz üzerinden çekilmiş anlık bir kare. Dizde bilgisayar, yanda koltuk lambası. Videonun içeriği ve ekrandaki yazılar seçilmiyor.
- **Misafir Wi‑Fi.** Evde mutfak masasında iki kahve fincanı. Ev sahibi kendi telefonunu misafirine doğru çeviriyor. Fotoğraf masaya ve ellere yakın. Telefon ekranı arayüzü okunmayacak açıdan görülüyor.
- **Ampul.** Evde masa lambasının yanında, bir el eski ampulü duyundan tutuyor. Işık kapalı. Ampul ve lamba aynı kadrajda görünüyor. Ampulün tipi ve renk sıcaklığı daha sonra gerçek Spotlight sonucunda okunacak.

**Telefon ekranını fotoğrafın içinde denemek**

Sahne fotoğrafını ve örnek verilerle alınmış gerçek ekran görüntüsünü iki ayrı referans olarak yükle. Örneğin kahve makinesi için şu düzenleme tarifini dene.

> Birinci görsel ev mutfağındaki kahve makinesi sahnesi. İkinci görsel gerçek Mindrop ekran görüntüsü. Makinenin önünde bakım yapan kişinin iPhone’u tek eliyle tuttuğu, omuz üzerinden çekilmiş doğal bir kare oluştur. Makine ve iPhone ekranı aynı kadrajda net görünsün. Ekran kameraya yakın bir açıyla dönük olsun. İkinci görseli telefonun ekranına yerleştir. Ekran görüntüsündeki yazıları, ikonları, renkleri ve yerleşimi aynen koru. Yalnızca ekran yüzeyine oturması için ölçeği ve perspektifi uyarla. Yansımalar yazıları örtmesin. Parmaklar cihazın kenarlarında kalsın. Sahnenin ışığını ve renklerini koru.

Çıktıda metni, ikonları ve kayıt değerini orijinal ekran görüntüsüyle karşılaştır. Yerleşim iyi görünüyorsa fakat arayüzde değişiklik varsa, son görselde gerçek ekran görüntüsünü telefonun ekran yüzeyine perspektifle oturt. Fotoğraf mobil boyutta okunduğunda uzun bakım metni küçülüyorsa ayrı Mindrop detay ekranını da değerlendir. Kısa Spotlight değerleri için fotoğraf içindeki ekran düzenini `Blue zone A` ve `21` ile dene.

### Web tipografisi

[Sofa ana sayfası](https://www.sofahq.com/) ve [Organize sayfasında](https://www.sofahq.com/organize) marka sesi ile okuma tipografisi farklı roller üstleniyor. 1280 px genişlikte yapılan incelemede **New Kansas 600**, ana manşette ve “Organize” gibi büyük bölüm manşetlerinde 60 px, iç sayfa bölüm manşetlerinde 48 px kullanılıyor. **Inter Variable** giriş açıklamasında 20 px, uzun özellik açıklamalarında 16–18 px. Küçük bölüm etiketleri, menü, düğmeler, bağlantılar, form alanları ve altbilgi de Inter ile diziliyor. Görsel hiyerarşiyi metnin rolü belirliyor. Örneğin küçük bir bölüm etiketi Inter ile dizilirken hemen altındaki büyük manşet New Kansas kullanabiliyor.

Mindrop için bu ayrımı aşağıdaki rollerle uygula. İkincil web fontu için başlangıç önerisi, mevcut sistem sans-serif ailesi.

| Web metni | Font ve kullanım |
| --- | --- |
| Ana manşet, bölümün ana vaadi ve anlatıyı taşıyan adım başlıkları | **Bricolage Grotesque 700**. “Find it faster.” ve “Give it a keyword.” gibi cümleler marka sesini taşır. |
| Kısa marka açıklaması | **Bricolage Grotesque 400**. Açılıştaki veya bölüm başlığındaki kısa destek metninde kullan. |
| Ayrıntılı kullanım hikâyesi ve açıklamalar | **Sistem fontu 400**. Havaalanı, YouTube önerisi ve bakım gibi örneklerin birkaç cümlelik anlatımlarında 16–18 px rahat bir başlangıç ölçüsüdür. |
| Bölüm etiketi, menü ve eylem metni | **Sistem fontu 500–600**. Menü, metin düğmeleri ve yönlendirme bağlantıları için 14–16 px aralığından başla. |
| Altbilgi, yardımcı ve yasal metin | **Sistem fontu 400**. Metni okunaklı tut ve ikincil önemini ağırlık ve aralıkla göster. |

Bir bölümde kısa ve güçlü bir ana başlık, onu açan bir açıklama ve varsa bu faydayı gösteren gerçek ekran yeterli. Küçük bir bölüm etiketi ancak bağlam ekliyorsa kullan. Başlık etiketlerini sayfanın anlam sırasına göre seç ve fontu metnin görsel rolüne göre uygula. Masaüstü ve mobilde satır kırılımlarını kendi metinlerimizle kontrol et.

## App Store görselleri

Yeni uygulamadan gerçek ekran görüntüleri al. İlk görsel için kullanıcının kendi bilgisini Spotlight’ta bulduğu an mevcut serinin temelidir. Devamında hızlı kayıt, kategorili kütüphane ve QR kodu veya tarayıcıda açma gibi türüne özel eylemlerle hikâyeyi tamamla. Cihazlar arası erişim önemliyse aynı kaydı iki cihazda gerçek ekranlarla göster. Her görselin pazarlama başlığını ekranın dışında Bricolage Grotesque ile diz.

## Çalışma sırası ve kaynaklar

Önce uygulama tasarımını güncelle ve yeni sürümden gerçek ekran görüntülerini al. App Store görsellerini bu ekranlarla hazırla. Web aşamasında günlük hayat sahnelerinden uygun olanları seç, görselleri Gemini’da yeni ekran görüntüleriyle hazırla ve ardından web sitesini güncelle.

- Uygulama tasarımı için [kayıt ekleme ekranını](Mindrop/Features/MemoryEditor/MemoryEditorView.swift), [iPhone ana ekranını](Mindrop/Features/MemoryList/MemoryListView.swift), [Mac kütüphanesini](Mindrop/Features/MemoryList/MacLibraryView.swift) ve [detay ekranını](Mindrop/Features/MemoryDetail/MemoryDetailView.swift) incele. İlk görsel referanslar masaüstündeki `Mindrop App Store Screenshots/01-iPhone-Dynamic-Island/en-US` klasöründedir.
- Web için [sayfa kaynağını](docs/index.html), [stilleri](docs/assets/site.css) ve [Spotlight demosunu](docs/assets/demo.js) kullan. Pazarlama metinlerini [gerçek font dosyasıyla](docs/assets/bricolage-grotesque.ttf) diz ve [lisansını](docs/assets/bricolage-grotesque-OFL.txt) fontla birlikte sakla.
- Pazarlama iddialarını [proje belgeleri](README.md), [gizlilik açıklaması](docs/privacy.html) ve gösterilecek uygulama sürümünün gerçek cihaz davranışıyla eşleştir. [Eski mağaza taslağını](AppStore/copy.md) önceki örnekleri ve ekran sırasını görmek için kullan. İçindeki gizlilik ve güvenlik metinleri eski ürün davranışını anlatır.
